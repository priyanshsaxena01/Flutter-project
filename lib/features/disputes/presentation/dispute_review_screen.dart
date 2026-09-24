import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/disputes/presentation/dispute_evidence_screen.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/disputes/state/upload_queue_provider.dart';
import 'package:fraud_shield/features/disputes/widgets/dispute_widgets.dart';

/// /disputes/new/review — step 3: check everything, then submit.
class DisputeReviewScreen extends ConsumerWidget {
  const DisputeReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(disputeFlowProvider);
    final txn = flow.txn;
    final reason = flow.reason;
    final disputeId = flow.disputeId;
    if (txn == null || reason == null || disputeId == null) {
      return const MissingFlowScreen();
    }
    final files = [
      for (final i in ref.watch(uploadQueueProvider(disputeId)))
        if (i.status == UploadStatus.done) i.file,
    ];
    final disputed = flow.disputedAmountPaise ?? txn.amountPaise;

    Future<void> submit() async {
      final messenger = ScaffoldMessenger.of(context);
      final notifier = ref.read(disputeFlowProvider.notifier);
      final created = await notifier.submit(evidenceCount: files.length);
      if (created == null || !context.mounted) return;
      context.go('/cases/${created.id}');
      notifier.reset();
      messenger.showSnackBar(
        SnackBar(content: Text('Case ${created.caseNumber} is open.')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Step 3 of 3 · Review',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TransactionSummary(txn: txn),
          const SectionTitle('Your dispute'),
          InfoRow(label: 'Reason', value: reason.label),
          for (final q in DisputeRules.visibleQuestions(reason, flow.answers))
            if ((flow.answers[q.id] ?? '').trim().isNotEmpty)
              InfoRow(
                label: q.label,
                value: displayAnswer(q, flow.answers[q.id]!),
              ),
          InfoRow(label: 'Amount in dispute', value: Money.format(disputed)),
          if (disputed != txn.amountPaise)
            Text(
              'Only the extra ${Money.format(disputed)} is disputed, not the '
              'whole ${Money.format(txn.amountPaise)}.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          SectionTitle('Evidence (${files.length})'),
          if (files.isEmpty)
            const Text('No files added.')
          else
            for (final f in files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(f.name),
              ),
          const SizedBox(height: 16),
          const InlineMessage(
            tone: Tone.neutral,
            title: 'What happens next',
            message:
                'We open a case, contact the merchant and the card or UPI '
                'network, and decide on provisional credit within 10 days. '
                'You can follow every step in Disputes.',
          ),
          if (flow.error != null) ...[
            const SizedBox(height: 12),
            InlineMessage(message: flow.error!),
            if (flow.existingCaseId != null)
              TextButton(
                onPressed: () => context.go('/cases/${flow.existingCaseId}'),
                child: const Text('View the existing case'),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('submit-dispute'),
            onPressed: flow.saving ? null : () => unawaited(submit()),
            child:
                flow.saving
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Submit dispute'),
          ),
        ],
      ),
    );
  }
}
