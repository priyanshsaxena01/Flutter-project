import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/security/app_lock.dart';

/// Fingerprint / face check before safety-critical actions:
/// deny, block, device removal and app unlock (Security NFR).
abstract class BiometricService {
  /// Returns true only when the user proved it is them.
  Future<bool> confirm(String reason);
}

/// The real sensor on Android and iOS (local_auth), with the phone's own
/// PIN, pattern or password as the fallback (B2).
///
/// Where there is no sensor to use (Chrome, Windows, or a phone with no
/// screen lock), it shows the on-screen demo prompt instead, but only while
/// the app runs against the built-in bank. Against a real server it refuses.
class DeviceBiometricService implements BiometricService {
  DeviceBiometricService(
    this._ref, {
    LocalAuthentication? auth,
    bool? platformHasSensor,
  }) : _auth = auth ?? LocalAuthentication(),
       _platformHasSensor =
           platformHasSensor ??
           (!kIsWeb &&
               (defaultTargetPlatform == TargetPlatform.android ||
                   defaultTargetPlatform == TargetPlatform.iOS));

  final Ref _ref;
  final LocalAuthentication _auth;
  final bool _platformHasSensor;

  /// Error codes meaning "this phone has no screen lock set up".
  static const _noScreenLock = {
    auth_error.notAvailable,
    auth_error.passcodeNotSet,
  };

  Future<bool> _deviceSupported() async {
    if (!_platformHasSensor) return false;
    try {
      return await _auth.isDeviceSupported();
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> confirm(String reason) async {
    if (!await _deviceSupported()) return _fallback(reason);
    try {
      return await _ref
          .read(appLockProvider.notifier)
          .whileAuthenticating(
            () => _auth.authenticate(
              localizedReason: reason,
              options: const AuthenticationOptions(
                // Allow the phone PIN / pattern when no fingerprint is set up.
                biometricOnly: false,
                // Keep the prompt if the app is briefly backgrounded.
                stickyAuth: true,
              ),
            ),
            // The system prompt pauses the app; don't lock because of it.
            grace: const Duration(seconds: 1),
          );
    } on PlatformException catch (e) {
      if (_noScreenLock.contains(e.code)) return _fallback(reason);
      // Cancelled, locked out after too many tries, and so on.
      return false;
    }
  }

  Future<bool> _fallback(String reason) {
    if (!_ref.read(apiConfigProvider).useMock) return Future.value(false);
    return DemoBiometricService(_ref).confirm(reason);
  }
}

// ---------------------------------------------------------------------------
// The on-screen demo prompt (web, Windows, phones without a screen lock)
// ---------------------------------------------------------------------------

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

/// Real sensor on phones, demo prompt elsewhere.
final biometricServiceProvider = Provider<BiometricService>(
  DeviceBiometricService.new,
);
