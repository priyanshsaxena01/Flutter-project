import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';

/// Instrument control (F3). Throws only BankError.
class InstrumentRepository {
  InstrumentRepository(this._dio);

  final Dio _dio;

  Future<List<Instrument>> fetchAll() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/instruments');
      return itemsOf(res.data).map(Instrument.fromJson).toList();
    });
  }

  /// "Block is idempotent": the same key returns the first result, and an
  /// instrument that is already blocked counts as success.
  Future<Instrument> block(
    String id,
    BlockReason reason, {
    required String idempotencyKey,
  }) async {
    try {
      return await guardCall(() async {
        final res = await _dio.post<Map<String, Object?>>(
          '/instruments/$id/block',
          data: {'reason': reason.api},
          options: Options(headers: {'Idempotency-Key': idempotencyKey}),
        );
        return Instrument.fromJson(asJson(res.data));
      });
    } on ConflictError catch (e) {
      if (e.code != 'ALREADY_BLOCKED') rethrow;
      final current = e.details['instrument'];
      if (current is Map<String, Object?>) return Instrument.fromJson(current);
      final all = await fetchAll();
      return all.firstWhere((i) => i.id == id);
    }
  }

  Future<Instrument> unblock(String id, {required String idempotencyKey}) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/instruments/$id/unblock',
        options: Options(headers: {'Idempotency-Key': idempotencyKey}),
      );
      return Instrument.fromJson(asJson(res.data));
    });
  }
}

final instrumentRepositoryProvider = Provider<InstrumentRepository>(
  (ref) => InstrumentRepository(ref.watch(dioProvider)),
);
