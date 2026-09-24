import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/idempotency.dart';
import 'package:fraud_shield/features/disputes/data/dispute_repository.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';

enum UploadStatus { queued, uploading, done, failed }

class UploadItem {
  const UploadItem({
    required this.localId,
    required this.file,
    required this.idempotencyKey,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.error,
  });

  final String localId;
  final PickedFile file;

  /// One key per file, kept across retries, so a retry after a dropped
  /// connection never stores the file twice.
  final String idempotencyKey;
  final UploadStatus status;
  final double progress;
  final String? error;

  UploadItem copyWith({
    UploadStatus? status,
    double? progress,
    String? error,
    bool clearError = false,
  }) {
    return UploadItem(
      localId: localId,
      file: file,
      idempotencyKey: idempotencyKey,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

/// Evidence upload queue for one dispute (F5): progress per file, and a
/// failed file is retried on its own ("fails at 90%: retry that file only").
class UploadQueueNotifier extends FamilyNotifier<List<UploadItem>, String> {
  var _pumping = false;
  var _seq = 0;
  var _disposed = false;

  @override
  List<UploadItem> build(String disputeId) {
    ref.onDispose(() => _disposed = true);
    return const [];
  }

  int get doneCount => state.where((i) => i.status == UploadStatus.done).length;

  bool get busy => state.any(
    (i) =>
        i.status == UploadStatus.uploading || i.status == UploadStatus.queued,
  );

  /// Adds files that pass the rules and starts uploading them.
  /// Returns a message for each file that was refused.
  /// [alreadyOnServer] counts evidence attached earlier (for a case).
  List<String> addFiles(List<PickedFile> files, {int alreadyOnServer = 0}) {
    final refused = <String>[];
    var count = alreadyOnServer + state.length;
    final added = <UploadItem>[];
    for (final file in files) {
      final problem = EvidenceRules.checkFile(
        name: file.name,
        sizeBytes: file.sizeBytes,
        mimeType: file.mimeType,
        filesSoFar: count,
      );
      if (problem != null) {
        refused.add(problem);
        continue;
      }
      added.add(
        UploadItem(
          localId: 'upload-${_seq++}',
          file: file,
          idempotencyKey: newIdempotencyKey(),
        ),
      );
      count++;
    }
    if (added.isNotEmpty) {
      state = [...state, ...added];
      unawaited(_pump());
    }
    return refused;
  }

  void retry(String localId) {
    _update(
      localId,
      (i) => i.copyWith(
        status: UploadStatus.queued,
        progress: 0,
        clearError: true,
      ),
    );
    unawaited(_pump());
  }

  /// Removes a file that is not uploading and not yet on the server.
  void remove(String localId) {
    state = [
      for (final i in state)
        if (i.localId != localId ||
            i.status == UploadStatus.uploading ||
            i.status == UploadStatus.done)
          i,
    ];
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    final repo = ref.read(disputeRepositoryProvider);
    try {
      while (!_disposed) {
        final next =
            state.where((i) => i.status == UploadStatus.queued).firstOrNull;
        if (next == null) break;
        _update(
          next.localId,
          (i) => i.copyWith(status: UploadStatus.uploading, progress: 0),
        );
        var reported = 0.0;
        try {
          await repo.uploadEvidence(
            arg,
            next.file,
            idempotencyKey: next.idempotencyKey,
            onProgress: (p) {
              // Throttle rebuilds to about every 2%.
              if (p - reported >= 0.02 || p >= 1) {
                reported = p;
                _update(next.localId, (i) => i.copyWith(progress: p));
              }
            },
          );
          _update(
            next.localId,
            (i) => i.copyWith(status: UploadStatus.done, progress: 1),
          );
        } on BankError catch (e) {
          _update(
            next.localId,
            (i) => i.copyWith(status: UploadStatus.failed, error: e.message),
          );
        }
      }
    } finally {
      _pumping = false;
    }
  }

  void _update(String localId, UploadItem Function(UploadItem) change) {
    if (_disposed) return;
    state = [for (final i in state) i.localId == localId ? change(i) : i];
  }
}

final uploadQueueProvider =
    NotifierProvider.family<UploadQueueNotifier, List<UploadItem>, String>(
      UploadQueueNotifier.new,
    );
