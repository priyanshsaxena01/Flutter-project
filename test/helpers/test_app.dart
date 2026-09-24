import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/app/app.dart';
import 'package:fraud_shield/app/router.dart';
import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/realtime/backoff.dart';
import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/security/biometric_service.dart';
import 'package:fraud_shield/core/security/device_identity.dart';
import 'package:fraud_shield/core/security/session_store.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/mock_server/mock_bank_server.dart';

class FakeBiometricService implements BiometricService {
  bool result = true;
  int calls = 0;

  @override
  Future<bool> confirm(String reason) async {
    calls++;
    return result;
  }
}

class FakeFilePicker implements FilePickerService {
  List<PickedFile> next = [];

  @override
  Future<List<PickedFile>> pickEvidence(BuildContext context) async => next;
}

PickedFile smallPng([String name = 'receipt.png']) => PickedFile(
  name: name,
  sizeBytes: 200 * 1024,
  mimeType: 'image/png',
  bytes: Uint8List(200 * 1024),
);

/// Everything a test needs: a quiet in-app server with a fixed clock,
/// fake biometrics and file picker, and a known device.
class TestHarness {
  TestHarness({DateTime? now}) : now = now ?? DateTime(2026, 9, 24, 12);

  final DateTime now;
  late final MockBankServer server = MockBankServer.forTests(clock: () => now);
  final biometric = FakeBiometricService();
  final picker = FakeFilePicker();
  static const device = DeviceIdentity(id: 'dev-test', name: 'Test device');

  /// false = use the real demo fingerprint prompt and file sheet.
  bool fakeDevice = true;

  List<Override> overrides({bool signedIn = true}) {
    final store = MemorySessionStore(
      signedIn
          ? StoredSession(
            token: server.signInForTests(deviceId: device.id),
            customerName: 'Priyansh Saxena',
            customerId: 'TEST_CUSTOM',
          )
          : null,
    );
    return [
      mockBankServerProvider.overrideWithValue(server),
      if (fakeDevice)
        biometricServiceProvider.overrideWithValue(biometric)
      else
        // No sensor in a test: the real service shows the demo prompt.
        biometricServiceProvider.overrideWith(
          (ref) => DeviceBiometricService(ref, platformHasSensor: false),
        ),
      if (fakeDevice) filePickerServiceProvider.overrideWithValue(picker),
      deviceIdentityProvider.overrideWithValue(device),
      sessionStoreProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(() => now),
      streamBackoffProvider.overrideWithValue(
        const Backoff(
          initial: Duration(milliseconds: 20),
          max: Duration(milliseconds: 80),
          jitter: 0,
        ),
      ),
    ];
  }

  /// A container that has finished restoring a signed-in session.
  Future<ProviderContainer> container({bool signedIn = true}) async {
    final c = ProviderContainer(overrides: overrides(signedIn: signedIn));
    addTearDown(c.dispose);
    c.read(sessionProvider);
    await waitFor(
      () => c.read(sessionProvider).status != SessionStatus.restoring,
    );
    c.read(appLockProvider.notifier).unlock();
    return c;
  }

  /// Pumps the whole app, unlocked, optionally at [location].
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    bool signedIn = true,
    String? location,
  }) async {
    // A phone-width screen, tall enough that most screens fit without
    // scrolling in tests.
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides(signedIn: signedIn),
        child: const FraudShieldApp(),
      ),
    );
    await tester.pump();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FraudShieldApp)),
    );
    container.read(appLockProvider.notifier).unlock();
    await tester.pumpAndSettle();
    if (location != null) {
      container.read(routerProvider).go(location);
      await tester.pumpAndSettle();
    }
    return container;
  }
}

/// Polls [condition] in real time (for plain unit tests).
Future<void> waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) {
      throw TimeoutException('Condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class TimeoutException implements Exception {
  TimeoutException(this.message);

  final String message;

  @override
  String toString() => message;
}
