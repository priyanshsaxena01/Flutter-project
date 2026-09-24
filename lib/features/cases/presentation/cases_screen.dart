import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/cases/widgets/case_widgets.dart';

/// F6: all dispute cases with their SLA state.
class CasesScreen extends ConsumerWidget {
  const CasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(casesProvider);
    final now =
        ref.watch(slaTickerProvider).valueOrNull ?? ref.watch(clockProvider)();
    Future<void> refresh() => refreshQuietly(ref.refresh(casesProvider.future));

    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/disputes/new'),
        icon: const Icon(Icons.add),
        label: const Text('New dispute'),
      ),
      body: cases.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(itemHeight: 120),
        error:
            (e, _) => RefreshableList(
              onRefresh: refresh,
              children: [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(casesProvider),
                ),
              ],
            ),
        data:
            (list) => RefreshableList(
              onRefresh: refresh,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (list.isEmpty)
                  EmptyView(
                    icon: Icons.gavel_outlined,
                    title: 'No disputes',
                    message:
                        'If a payment looks wrong, raise a dispute and track it '
                        'here.',
                    actionLabel: 'Raise a dispute',
                    onAction: () => context.push('/disputes/new'),
                  ),
                for (final c in list) ...[
                  _CaseTile(
                    disputeCase: c,
                    now: now,
                    onTap: () => context.go('/cases/${c.id}'),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
      ),
    );
  }
}

class _CaseTile extends StatelessWidget {
  const _CaseTile({
    required this.disputeCase,
    required this.now,
    required this.onTap,
  });

  final DisputeCase disputeCase;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = disputeCase;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      c.merchant,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    Money.format(c.disputedAmountPaise),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Text('${c.caseNumber} · ${c.reason.label}'),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CaseStatusChip(status: c.status),
                  if (!c.status.isClosed) SlaChip(sla: slaOf(c, now)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
