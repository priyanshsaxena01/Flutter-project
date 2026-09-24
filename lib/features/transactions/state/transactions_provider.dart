import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/transactions/data/transaction_repository.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';

final transactionsProvider = FutureProvider.autoDispose<List<BankTransaction>>((
  ref,
) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(transactionRepositoryProvider).fetchRecent();
});

/// One transaction, from the recent list.
final transactionProvider = FutureProvider.autoDispose
    .family<BankTransaction?, String>((ref, id) async {
      final all = await ref.watch(transactionsProvider.future);
      return all.where((t) => t.id == id).firstOrNull;
    });
