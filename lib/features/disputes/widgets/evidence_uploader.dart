import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';
import 'package:fraud_shield/features/disputes/state/upload_queue_provider.dart';

/// F5: pick files, upload each with progress, retry a failed one on its own.
/// Used by the new-dispute flow and by "Add evidence" on a case.
class EvidenceUploader extends ConsumerStatefulWidget {
  const EvidenceUploader({
    super.key,
    required this.disputeId,
    this.existing = const [],
  });

  final String disputeId;

  /// Files already attached on the server (for an existing case).
  final List<EvidenceFile> existing;

  @override
  ConsumerState<EvidenceUploader> createState() => _EvidenceUploaderState();
}

class _EvidenceUploaderState extends ConsumerState<EvidenceUploader> {
  List<String> _refused = const [];

  Future<void> _pick() async {
    final files = await ref
        .read(filePickerServiceProvider)
        .pickEvidence(context);
    if (files.isEmpty || !mounted) return;
    final refused = ref
        .read(uploadQueueProvider(widget.disputeId).notifier)
        .addFiles(files, alreadyOnServer: widget.existing.length);
    setState(() => _refused = refused);
  }

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(uploadQueueProvider(widget.disputeId));
    final total = widget.existing.length + queue.length;
    final full = total >= EvidenceRules.maxFiles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Up to ${EvidenceRules.maxFiles} files · JPG, PNG or PDF · '
          '5 MB each',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final e in widget.existing)
          _FileRow(
            name: e.name,
            size: e.sizeBytes,
            mimeType: e.mimeType,
            trailing: const StatusChip(
              label: 'Attached',
              icon: Icons.check,
              tone: Tone.success,
            ),
          ),
        for (final item in queue)
          _UploadRow(disputeId: widget.disputeId, item: item),
        for (final message in _refused) ...[
          const SizedBox(height: 8),
          InlineMessage(message: message, tone: Tone.warning),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('add-files'),
          onPressed: full ? null : () => unawaited(_pick()),
          icon: const Icon(Icons.attach_file),
          label: Text(
            full
                ? 'Maximum ${EvidenceRules.maxFiles} files added'
                : 'Add files',
          ),
        ),
      ],
    );
  }
}

class _UploadRow extends ConsumerWidget {
  const _UploadRow({required this.disputeId, required this.item});

  final String disputeId;
  final UploadItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(uploadQueueProvider(disputeId).notifier);
    final Widget trailing = switch (item.status) {
      UploadStatus.queued => const Text('Waiting…'),
      UploadStatus.uploading => Text('${(item.progress * 100).round()}%'),
      UploadStatus.done => const StatusChip(
        label: 'Uploaded',
        icon: Icons.check,
        tone: Tone.success,
      ),
      UploadStatus.failed => Wrap(
        spacing: 4,
        children: [
          TextButton(
            key: Key('retry-${item.file.name}'),
            onPressed: () => notifier.retry(item.localId),
            child: const Text('Retry'),
          ),
          IconButton(
            tooltip: 'Remove ${item.file.name}',
            onPressed: () => notifier.remove(item.localId),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    };

    return _FileRow(
      name: item.file.name,
      size: item.file.sizeBytes,
      mimeType: item.file.mimeType,
      trailing: trailing,
      below: switch (item.status) {
        UploadStatus.uploading => LinearProgressIndicator(
          value: item.progress,
          semanticsLabel: 'Uploading ${item.file.name}',
          semanticsValue: '${(item.progress * 100).round()}%',
        ),
        UploadStatus.failed => Text(
          '${item.error ?? 'Upload failed.'} Only this file needs retrying.',
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
        _ => null,
      },
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({
    required this.name,
    required this.size,
    required this.mimeType,
    required this.trailing,
    this.below,
  });

  final String name;
  final int size;
  final String mimeType;
  final Widget trailing;
  final Widget? below;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                mimeType == 'application/pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name),
                    Text(
                      EvidenceRules.formatSize(size),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              trailing,
            ],
          ),
          if (below != null) ...[const SizedBox(height: 6), below!],
        ],
      ),
    );
  }
}
