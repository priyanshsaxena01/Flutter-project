import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';

class TransactionRepository {
  TransactionRepository(this._dio);

  final Dio _dio;

  Future<List<BankTransaction>> fetchRecent() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/transactions');
      return itemsOf(res.data).map(BankTransaction.fromJson).toList();
    });
  }
}

final transactionRepositoryProvider = Provider<TransactionRepository>(
  (ref) => TransactionRepository(ref.watch(dioProvider)),
);
