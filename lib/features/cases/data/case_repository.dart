import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/cases/domain/case_message.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';

/// Cases and secure messages (F6, F7, F8). Throws only BankError.
class CaseRepository {
  CaseRepository(this._dio);

  final Dio _dio;

  Future<List<DisputeCase>> fetchAll() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/cases');
      return itemsOf(res.data).map(DisputeCase.fromJson).toList();
    });
  }

  Future<DisputeCase> fetch(String id) {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/cases/$id');
      return DisputeCase.fromJson(asJson(res.data));
    });
  }

  /// Newest first. Pass [cursor] from the previous page to load older ones.
  Future<MessagePage> messages(
    String caseId, {
    String? cursor,
    int limit = 15,
  }) {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>(
        '/cases/$caseId/messages',
        queryParameters: {'limit': limit, if (cursor != null) 'cursor': cursor},
      );
      return MessagePage(
        items: itemsOf(res.data).map(CaseMessage.fromJson).toList(),
        nextCursor: asJson(res.data)['nextCursor'] as String?,
      );
    });
  }

  Future<CaseMessage> send(
    String caseId,
    String text, {
    String? attachmentName,
    required String idempotencyKey,
  }) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/cases/$caseId/messages',
        data: {'text': text, 'attachmentName': attachmentName},
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return CaseMessage.fromJson(asJson(res.data));
    });
  }
}

final caseRepositoryProvider = Provider<CaseRepository>(
  (ref) => CaseRepository(ref.watch(dioProvider)),
);
