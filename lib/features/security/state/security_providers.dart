import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/biometric_service.dart';
import 'package:fraud_shield/features/security/data/security_repository.dart';
import 'package:fraud_shield/features/security/domain/security_models.dart';

final devicesProvider = FutureProvider.autoDispose<List<Device>>(
  (ref) => ref.watch(securityRepositoryProvider).devices(),
);

final loginHistoryProvider = FutureProvider.autoDispose<List<LoginEvent>>(
  (ref) => ref.watch(securityRepositoryProvider).logins(),
);

final auditLogProvider = FutureProvider.autoDispose<List<AuditEntry>>(
  (ref) => ref.watch(securityRepositoryProvider).auditLog(),
);

/// Signing out devices needs a fingerprint check (Security NFR).
class DeviceActions {
  DeviceActions(this._ref);

  final Ref _ref;

  /// Returns false if the fingerprint check failed. Throws BankError.
  Future<bool> signOut(List<Device> devices) async {
    final label =
        devices.length == 1
            ? devices.single.name
            : '${devices.length} other devices';
    final verified = await _ref
        .read(biometricServiceProvider)
        .confirm('Sign out $label');
    if (!verified) return false;
    final repo = _ref.read(securityRepositoryProvider);
    try {
      for (final device in devices) {
        await repo.signOutDevice(device.id);
      }
    } finally {
      _ref.invalidate(devicesProvider);
    }
    return true;
  }
}

final deviceActionsProvider = Provider<DeviceActions>(DeviceActions.new);
