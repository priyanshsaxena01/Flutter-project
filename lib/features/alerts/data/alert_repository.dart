import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';

/// Alerts domain: GET /alerts, confirm, deny. Throws only BankError.
class AlertRepository {
  AlertRepository(this._dio);

  final Dio _dio;

  /// [sinceId] returns only alerts newer than that one (used after the
  /// live stream reconnects).
  Future<List<Alert>> fetchAlerts({String? status, String? sinceId}) {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>(
        '/alerts',
        queryParameters: {
          if (status != null) 'status': status,
          if (sinceId != null) 'sinceId': sinceId,
        },
      );
      return itemsOf(res.data).map(Alert.fromJson).toList();
    });
  }

  Future<Alert> fetchAlert(String id) {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/alerts/$id');
      return Alert.fromJson(asJson(res.data));
    });
  }

  /// "Yes, it was me".
  Future<Alert> confirm(String id) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>('/alerts/$id/confirm');
      return Alert.fromJson(asJson(res.data));
    });
  }

  /// "No, it wasn't me": blocks the instrument and opens a case.
  ///
  /// Safe to retry with the same [idempotencyKey]. If the server says it
  /// was already denied (for example the first response was lost), the
  /// user gets the same outcome instead of an error.
  Future<DenyResult> deny(String id, {required String idempotencyKey}) async {
    try {
      return await guardCall(() async {
        final res = await _dio.post<Map<String, Object?>>(
          '/alerts/$id/deny',
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        final data = asJson(res.data);
        final alert = Alert.fromJson(asJson(data['alert']));
        final disputeCase = asJson(data['case']);
        return DenyResult(
          alert: alert,
          instrumentLabel: alert.instrumentLabel,
          caseId: disputeCase['id']! as String,
          caseNumber: disputeCase['caseNumber']! as String,
          disputeId: disputeCase['disputeId']! as String,
        );
      });
    } on ConflictError catch (e) {
      if (e.code != 'ALREADY_DENIED') rethrow;
      final alert = await fetchAlert(id);
      return DenyResult(
        alert: alert,
        instrumentLabel: alert.instrumentLabel,
        caseId: e.details['caseId'] as String? ?? alert.caseId ?? '',
        caseNumber: e.details['caseNumber'] as String? ?? '',
        disputeId: e.details['disputeId'] as String? ?? '',
        alreadyDone: true,
      );
    }
  }
}

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => AlertRepository(ref.watch(dioProvider)),
);
