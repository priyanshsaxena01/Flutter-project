import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/cases/widgets/case_widgets.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';

/// F6 + F7: timeline, SLA countdown, provisional credit, evidence and a
/// link to secure messages.
class CaseDetailScreen extends ConsumerWidget {
  const CaseDetailScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputeCase = ref.watch(caseProvider(caseId));
    final now =
        ref.watch(slaTickerProvider).valueOrNull ?? ref.watch(clockProvider)();
    Future<void> refresh() =>
        refreshQuietly(ref.refresh(caseProvider(caseId).future));

    return Scaffold(
      appBar: AppBar(title: const Text('Dispute case')),
      body: disputeCase.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(itemCount: 4, itemHeight: 130),
        error:
            (e, _) => RefreshableList(
              onRefresh: refresh,
              children: [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(caseProvider(caseId)),
                ),
              ],
            ),
        data:
            (c) => RefreshableList(
              onRefresh: refresh,
              children: [
                _Header(disputeCase: c),
                const SizedBox(height: 12),
                if (!c.status.isClosed || c.hasCredit)
                  SlaCard(
                    disputeCase: c,
                    now: now,
                    onMessage: () => context.go('/cases/$caseId/messages'),
                  ),
                if (c.hasCredit) ...[
                  const SizedBox(height: 12),
                  CreditCard(disputeCase: c),
                ],
                SectionTitle(
                  'Evidence (${c.evidence.length}/${EvidenceRules.maxFiles})',
                  trailing:
                      c.status.isClosed ||
                              c.evidence.length >= EvidenceRules.maxFiles
                          ? null
                          : TextButton.icon(
                            onPressed:
                                () => context.go('/cases/$caseId/evidence'),
                            icon: const Icon(Icons.attach_file),
                            label: const Text('Add'),
                          ),
                ),
                if (c.evidence.isEmpty)
                  const Text('No files yet.')
                else
                  for (final e in c.evidence)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        e.mimeType == 'application/pdf'
                            ? Icons.picture_as_pdf_outlined
                            : Icons.image_outlined,
                      ),
                      title: Text(e.name),
                      subtitle: Text(EvidenceRules.formatSize(e.sizeBytes)),
                    ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => context.go('/cases/$caseId/messages'),
                  icon: const Icon(Icons.forum_outlined),
                  label: Text('Messages with the bank (${c.messageCount})'),
                ),
                const SectionTitle('Timeline'),
                TimelineView(entries: c.timeline),
              ],
            ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.disputeCase});

  final DisputeCase disputeCase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = disputeCase;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(c.caseNumber, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(c.merchant, style: theme.textTheme.titleLarge),
            Text(c.reason.label),
            const SizedBox(height: 12),
            CaseStatusChip(status: c.status),
            const Divider(height: 24),
            InfoRow(
              label: 'Disputed amount',
              value: Money.format(c.disputedAmountPaise),
            ),
            if (c.txnAmountPaise != c.disputedAmountPaise)
              InfoRow(
                label: 'Payment amount',
                value: Money.format(c.txnAmountPaise),
              ),
          ],
        ),
      ),
    );
  }
}
