import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/state/upload_queue_provider.dart';
import 'package:fraud_shield/features/disputes/widgets/evidence_uploader.dart';

/// Add evidence to a case that is already open (for example after
/// "No, it wasn't me", where evidence is optional).
class CaseEvidenceScreen extends ConsumerWidget {
  const CaseEvidenceScreen({super.key, required this.caseId});

  final String caseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputeCase = ref.watch(caseProvider(caseId));
    return Scaffold(
      appBar: AppBar(title: const Text('Add evidence')),
      body: disputeCase.when(
        loading: () => const SkeletonList(itemCount: 3),
        error:
            (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(caseProvider(caseId)),
            ),
        data: (c) {
          final queue = ref.watch(uploadQueueProvider(c.disputeId));
          final uploadedHere = {
            for (final i in queue)
              if (i.status == UploadStatus.done) i.file.name,
          };
          // Files uploaded on this screen are shown by the queue.
          final existing = [
            for (final e in c.evidence)
              if (!uploadedHere.contains(e.name)) e,
          ];
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                '${c.caseNumber} · ${c.merchant}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              EvidenceUploader(disputeId: c.disputeId, existing: existing),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () {
                  ref.invalidate(caseProvider(caseId));
                  if (context.canPop()) {
                    context.pop();
                  } else {
                    context.go('/cases/$caseId');
                  }
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }
}
