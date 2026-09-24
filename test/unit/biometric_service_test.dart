import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth/local_auth.dart';

import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/security/biometric_service.dart';

/// Stands in for the phone's fingerprint sensor.
class FakeLocalAuth implements LocalAuthentication {
  bool supported = true;
  bool result = true;
  PlatformException? error;
  int calls = 0;
  String? lastReason;
  AuthenticationOptions? lastOptions;

  @override
  Future<bool> isDeviceSupported() async => supported;

  @override
  Future<bool> authenticate({
    required String localizedReason,
    // Wider than the real type (allowed in an override); keeps the fake
    // free of local_auth's internal types.
    Iterable<Object> authMessages = const <Object>[],
    AuthenticationOptions options = const AuthenticationOptions(),
  }) async {
    calls++;
    lastReason = localizedReason;
    lastOptions = options;
    final e = error;
    if (e != null) throw e;
    return result;
  }

  @override
  Future<bool> get canCheckBiometrics async => supported;

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async => [
    BiometricType.fingerprint,
  ];

  @override
  Future<bool> stopAuthentication() async => true;
}

void main() {
  late FakeLocalAuth sensor;

  ProviderContainer container({
    bool platformHasSensor = true,
    bool realServer = false,
  }) {
    final c = ProviderContainer(
      overrides: [
        biometricServiceProvider.overrideWith(
          (ref) => DeviceBiometricService(
            ref,
            auth: sensor,
            platformHasSensor: platformHasSensor,
          ),
        ),
        if (realServer)
          apiConfigProvider.overrideWithValue(
            const ApiConfig(env: 'prod', baseUrl: 'https://api.example.com'),
          ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() => sensor = FakeLocalAuth());

  test(
    'uses the real sensor, with the phone PIN allowed as fallback',
    () async {
      final c = container();
      final ok = await c.read(biometricServiceProvider).confirm('Block card');
      expect(ok, isTrue);
      expect(sensor.calls, 1);
      expect(sensor.lastReason, 'Block card');
      expect(sensor.lastOptions!.biometricOnly, isFalse);
      expect(c.read(biometricPromptProvider), isNull); // no demo prompt
    },
  );

  test('a failed or cancelled scan returns false', () async {
    sensor.result = false;
    expect(
      await container().read(biometricServiceProvider).confirm('x'),
      isFalse,
    );
  });

  test('locked out after too many tries returns false', () async {
    sensor.error = PlatformException(code: auth_error.lockedOut);
    expect(
      await container().read(biometricServiceProvider).confirm('x'),
      isFalse,
    );
  });

  test(
    'no screen lock on the phone -> demo prompt (built-in bank only)',
    () async {
      sensor.error = PlatformException(code: auth_error.passcodeNotSet);
      final c = container();
      final result = c.read(biometricServiceProvider).confirm('Unlock');
      await Future<void>.delayed(Duration.zero);
      expect(c.read(biometricPromptProvider)?.reason, 'Unlock');
      c.read(biometricPromptProvider.notifier).resolve(true);
      expect(await result, isTrue);
    },
  );

  test('web / Windows use the demo prompt', () async {
    final c = container(platformHasSensor: false);
    final result = c.read(biometricServiceProvider).confirm('Unlock');
    await Future<void>.delayed(Duration.zero);
    expect(c.read(biometricPromptProvider), isNotNull);
    c.read(biometricPromptProvider.notifier).resolve(false);
    expect(await result, isFalse);
    expect(sensor.calls, 0);
  });

  test('against a real server there is no demo fallback', () async {
    sensor.supported = false;
    final c = container(realServer: true);
    expect(await c.read(biometricServiceProvider).confirm('x'), isFalse);
    expect(c.read(biometricPromptProvider), isNull);
  });

  test('the prompt pausing the app does not lock it', () async {
    final c = container();
    c.listen(appLockProvider, (_, _) {});
    final lock = c.read(appLockProvider.notifier);

    await lock.whileAuthenticating(() async {
      lock.lock(); // the system prompt paused the app
      return true;
    }, grace: const Duration(milliseconds: 50));
    lock.lock(); // late "paused" event just after the prompt closed
    expect(c.read(appLockProvider), isFalse);

    await Future<void>.delayed(const Duration(milliseconds: 80));
    lock.lock(); // a real trip to the background later on
    expect(c.read(appLockProvider), isTrue);
  });
}
