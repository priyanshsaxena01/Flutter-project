import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/biometric_service.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/instruments/data/instrument_repository.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';

/// Cards, UPI and net banking with their blocked state. Home, Block and
/// Alert screens all watch this, so a block shows everywhere at once.
class InstrumentsNotifier extends AsyncNotifier<List<Instrument>> {
  @override
  Future<List<Instrument>> build() {
    ref.watch(sessionProvider.select((s) => s.token));
    return ref.read(instrumentRepositoryProvider).fetchAll();
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Returns false when the fingerprint check failed. Throws BankError.
  Future<bool> block(
    Instrument instrument,
    BlockReason reason, {
    required String idempotencyKey,
  }) async {
    final verified = await ref
        .read(biometricServiceProvider)
        .confirm('Block ${instrument.displayName}');
    if (!verified) return false;
    final updated = await ref
        .read(instrumentRepositoryProvider)
        .block(instrument.id, reason, idempotencyKey: idempotencyKey);
    _replace(updated);
    return true;
  }

  Future<bool> unblock(
    Instrument instrument, {
    required String idempotencyKey,
  }) async {
    final verified = await ref
        .read(biometricServiceProvider)
        .confirm('Unblock ${instrument.displayName}');
    if (!verified) return false;
    final updated = await ref
        .read(instrumentRepositoryProvider)
        .unblock(instrument.id, idempotencyKey: idempotencyKey);
    _replace(updated);
    return true;
  }

  void _replace(Instrument updated) {
    final current = state.valueOrNull;
    if (current == null) {
      ref.invalidateSelf();
      return;
    }
    state = AsyncData([
      for (final i in current) i.id == updated.id ? updated : i,
    ]);
  }
}

final instrumentsProvider =
    AsyncNotifierProvider<InstrumentsNotifier, List<Instrument>>(
      InstrumentsNotifier.new,
    );
