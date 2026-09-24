import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/app/router.dart';

import '../helpers/test_app.dart';

/// The built-in demo fingerprint prompt, file sheet and demo controls,
/// exactly as the app ships them (no fakes).
void main() {
  testWidgets('fingerprint prompt: wrong finger, wrong PIN, then PIN', (
    tester,
  ) async {
    final h = TestHarness()..fakeDevice = false;
    await h.pumpApp(tester, location: '/alerts/alt_1004');

    await tester.tap(find.byKey(const Key('deny-button')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm it\'s you'), findsOneWidget);

    await tester.tap(find.text('Simulate a wrong finger'));
    await tester.pumpAndSettle();
    expect(find.text('Fingerprint not recognised. Try again.'), findsOneWidget);

    await tester.tap(find.text('Use device PIN'));
    await tester.pumpAndSettle();
    for (final d in ['9', '9', '9', '9']) {
      await tester.tap(find.widgetWithText(FilledButton, d));
      await tester.pump();
    }
    expect(find.text('Wrong PIN. Try again.'), findsOneWidget);
    for (final d in ['1', '2', '3', '4']) {
      await tester.tap(find.widgetWithText(FilledButton, d));
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(find.text('Confirm it\'s you'), findsNothing);
    expect(find.text('Credit card •• 7710 is blocked'), findsOneWidget);
  });

  testWidgets('fingerprint prompt: cancel blocks nothing', (tester) async {
    final h = TestHarness()..fakeDevice = false;
    await h.pumpApp(tester, location: '/alerts/alt_1004');
    await tester.tap(find.byKey(const Key('deny-button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.textContaining('nothing was blocked'), findsOneWidget);
    expect(h.server.blockActions, 0);
  });

  testWidgets('touching the sensor unlocks the app', (tester) async {
    final h = TestHarness()..fakeDevice = false;
    await h.pumpApp(tester);
    await tester.tap(find.byTooltip('Demo controls'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lock the app now'));
    await tester.pumpAndSettle();
    expect(find.text('FraudShield is locked'), findsOneWidget);

    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fingerprint-sensor')));
    await tester.pumpAndSettle();
    expect(find.text('FraudShield is locked'), findsNothing);
  });

  testWidgets('demo file sheet: add evidence to a case; big files refused', (
    tester,
  ) async {
    final h = TestHarness()..fakeDevice = false;
    await h.pumpApp(tester, location: '/cases/case_481/evidence');

    await tester.tap(find.byKey(const Key('add-files')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('invoice_INV-2231.pdf'));
    await tester.tap(find.text('photo_of_parcel.jpg'));
    await tester.pump();
    await tester.tap(find.text('Attach 2 files'));
    await tester.pumpAndSettle();

    expect(find.text('Uploaded'), findsOneWidget);
    expect(
      find.textContaining('photo_of_parcel.jpg is 6.2 MB'),
      findsOneWidget,
    );

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.text('Evidence (1/5)'), findsOneWidget);
  });

  testWidgets('demo controls and the activity log', (tester) async {
    final h = TestHarness();
    final c = await h.pumpApp(tester, location: '/demo');

    await tester.tap(find.text('Send a suspicious payment now'));
    await tester.pumpAndSettle();
    expect(find.text('Suspicious payment sent.'), findsOneWidget);

    await tester.tap(find.text('Card network down'));
    await tester.pumpAndSettle();
    expect(h.server.chaos.cardNetworkDown, isTrue);

    await tester.tap(find.text('Reset demo data'));
    await tester.pumpAndSettle();
    expect(h.server.db.alerts, hasLength(4));

    c.read(routerProvider).go('/alerts/alt_1003');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm-button')));
    await tester.pumpAndSettle();
    c.read(routerProvider).go('/security/activity');
    await tester.pumpAndSettle();
    expect(find.text('Confirmed a payment'), findsOneWidget);
  });

  testWidgets('messages: attach a file and load older messages', (
    tester,
  ) async {
    final h = TestHarness();
    h.picker.next = [smallPng('tracking.png')];
    await h.pumpApp(tester, location: '/cases/case_462/messages');

    // On a normal phone screen, scrolling up loads the older page.
    tester.view.physicalSize = const Size(1170, 2532);
    await tester.pumpAndSettle();
    const oldest =
        "Hi Priyansh, I'm Arjun from the disputes team. I'll be handling your "
        'case.';
    expect(find.text(oldest), findsNothing);
    for (var i = 0; i < 3; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();
    }
    expect(find.text(oldest), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -6000));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Attach a file'));
    await tester.pumpAndSettle();
    expect(find.text('tracking.png'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('message-input')), 'Tracking');
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Tracking'), findsOneWidget);
  });
}
