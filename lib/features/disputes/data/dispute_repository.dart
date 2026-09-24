import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';

/// Disputes domain (F4, F5). Throws only BankError.
class DisputeRepository {
  DisputeRepository(this._dio);

  final Dio _dio;

  /// Creates a draft dispute (reason + answers) so evidence can be
  /// attached to it before it is submitted.
  Future<Dispute> create({
    required String txnId,
    required DisputeReason reason,
    required Map<String, String> answers,
    required String idempotencyKey,
  }) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/disputes',
        data: {'txnId': txnId, 'reason': reason.api, 'answers': answers},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Dispute.fromJson(asJson(res.data));
    });
  }

  /// Changes the reason or answers of a draft.
  Future<Dispute> update(
    String id, {
    required DisputeReason reason,
    required Map<String, String> answers,
  }) {
    return guardCall(() async {
      final res = await _dio.patch<Map<String, Object?>>(
        '/disputes/$id',
        data: {'reason': reason.api, 'answers': answers},
      );
      return Dispute.fromJson(asJson(res.data));
    });
  }

  /// Uploads one file, reporting progress from 0.0 to 1.0.
  Future<EvidenceFile> uploadEvidence(
    String disputeId,
    PickedFile file, {
    required String idempotencyKey,
    void Function(double progress)? onProgress,
  }) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/disputes/$disputeId/evidence',
        data: file.bytes,
        options: Options(
          contentType: file.mimeType,
          headers: {
            'X-File-Name': Uri.encodeComponent(file.name),
            'Idempotency-Key': idempotencyKey,
          },
        ),
        onSendProgress: (sent, total) {
          if (total > 0 && onProgress != null) onProgress(sent / total);
        },
      );
      return EvidenceFile.fromJson(asJson(res.data));
    });
  }

  /// Submits the dispute and opens a case.
  Future<DisputeCase> submit(String id, {required String idempotencyKey}) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/disputes/$id/submit',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return DisputeCase.fromJson(asJson(asJson(res.data)['case']));
    });
  }
}

final disputeRepositoryProvider = Provider<DisputeRepository>(
  (ref) => DisputeRepository(ref.watch(dioProvider)),
);
