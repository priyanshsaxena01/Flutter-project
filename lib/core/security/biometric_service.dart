import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/app_lock.dart';

/// Fingerprint / face check before safety-critical actions:
/// deny, block, device removal and app unlock (Security NFR).
///
/// The app ships with [DemoBiometricService], which draws its own
/// fingerprint prompt so it works on Android, iOS, web and Windows with no
/// setup. To use the real sensor, implement this interface with the
/// local_auth package (see README) and override [biometricServiceProvider].
abstract class BiometricService {
  /// Returns true only when the user proved it is them.
  Future<bool> confirm(String reason);
}

/// A pending prompt. The UI (BiometricPromptHost) shows it and completes it.
class BiometricRequest {
  BiometricRequest(this.reason);

  final String reason;
  final _completer = Completer<bool>();

  Future<bool> get future => _completer.future;

  void _complete(bool ok) {
    if (!_completer.isCompleted) _completer.complete(ok);
  }
}

class BiometricPromptNotifier extends Notifier<BiometricRequest?> {
  @override
  BiometricRequest? build() => null;

  Future<bool> request(String reason) {
    // Only one prompt at a time; a second caller shares the first answer.
    final pending = state;
    if (pending != null) return pending.future;
    final request = BiometricRequest(reason);
    state = request;
    return request.future;
  }

  void resolve(bool ok) {
    final request = state;
    state = null;
    request?._complete(ok);
  }
}

final biometricPromptProvider =
    NotifierProvider<BiometricPromptNotifier, BiometricRequest?>(
      BiometricPromptNotifier.new,
    );

class DemoBiometricService implements BiometricService {
  DemoBiometricService(this._ref);

  final Ref _ref;

  /// The "device PIN" fallback accepted by the demo prompt.
  static const demoDevicePin = '1234';

  @override
  Future<bool> confirm(String reason) {
    return _ref
        .read(appLockProvider.notifier)
        .whileAuthenticating(
          () => _ref.read(biometricPromptProvider.notifier).request(reason),
        );
  }
}

final biometricServiceProvider = Provider<BiometricService>(
  DemoBiometricService.new,
);
