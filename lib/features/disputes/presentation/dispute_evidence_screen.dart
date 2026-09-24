import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/disputes/state/upload_queue_provider.dart';
import 'package:fraud_shield/features/disputes/widgets/evidence_uploader.dart';

/// /disputes/new/evidence — step 2: upload evidence to the draft dispute.
class DisputeEvidenceScreen extends ConsumerWidget {
  const DisputeEvidenceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(disputeFlowProvider);
    final disputeId = flow.disputeId;
    final reason = flow.reason;
    if (disputeId == null || reason == null) return const MissingFlowScreen();

    final queue = ref.watch(uploadQueueProvider(disputeId));
    final done = queue.where((i) => i.status == UploadStatus.done).length;
    final busy = queue.any(
      (i) =>
          i.status == UploadStatus.uploading || i.status == UploadStatus.queued,
    );
    final required =
        DisputeRules.evidenceRuleFor(reason) == EvidenceRule.required;
    final canContinue = !busy && (!required || done > 0);

    return Scaffold(
      appBar: AppBar(title: const Text('Evidence')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Step 2 of 3 · Evidence',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          InlineMessage(
            tone: required ? Tone.warning : Tone.neutral,
            icon: Icons.attach_file,
            title: required ? 'Required for this dispute' : 'Optional',
            message: DisputeRules.evidenceHint(reason),
          ),
          const SizedBox(height: 16),
          EvidenceUploader(disputeId: disputeId),
          const SizedBox(height: 24),
          if (busy)
            const Text('Waiting for uploads to finish…')
          else if (required && done == 0)
            const Text('Add at least one file to continue.'),
          const SizedBox(height: 8),
          FilledButton(
            key: const Key('evidence-continue'),
            onPressed:
                canContinue ? () => context.push('/disputes/new/review') : null,
            child: Text(
              !required && done == 0 ? 'Continue without files' : 'Continue',
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown if a flow step is opened directly without starting the flow.
class MissingFlowScreen extends StatelessWidget {
  const MissingFlowScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Raise a dispute')),
      body: Center(
        child: EmptyView(
          icon: Icons.restart_alt,
          title: 'Start from the payment',
          message: 'Pick the payment you want to dispute first.',
          actionLabel: 'Choose a payment',
          onAction: () => context.go('/disputes/new'),
        ),
      ),
    );
  }
}
