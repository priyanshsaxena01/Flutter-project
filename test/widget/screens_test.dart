import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/app/router.dart';
import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/security/app_lock.dart';

import '../helpers/test_app.dart';

Finder inside(Key key, Finder matching) =>
    find.descendant(of: find.byKey(key), matching: matching);

Finder navBadge(String count) =>
    find.descendant(of: find.byType(NavigationBar), matching: find.text(count));

void main() {
  group('Login (B1)', () {
    testWidgets('validates, shows server errors, then signs in', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester, signedIn: false);

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(find.text('Enter your customer ID'), findsOneWidget);
      expect(find.text('Enter your PIN'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Customer ID'),
        'TEST_CUSTOM',
      );
      await tester.enterText(find.widgetWithText(TextFormField, 'PIN'), '9999');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.textContaining('4 attempts left'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'PIN'),
        '0123456789',
      );
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Hi Priyansh'), findsOneWidget);
    });

    testWidgets('a deep link while logged out lands on login first', (
      tester,
    ) async {
      final h = TestHarness();
      final c = await h.pumpApp(
        tester,
        signedIn: false,
        location: '/alerts/alt_1004',
      );
      expect(find.text('Sign in'), findsOneWidget);
      expect(c, isNotNull);
    });
  });

  group('Home', () {
    testWidgets('shows alerts needing action and the blocked card', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester);
      expect(find.text('2 payments need your answer'), findsOneWidget);
      expect(
        inside(const Key('home-instrument-ins_debit'), find.text('Blocked')),
        findsOneWidget,
      );
      expect(
        inside(const Key('home-instrument-ins_credit'), find.text('Active')),
        findsOneWidget,
      );
    });
  });

  group('Alerts (F1)', () {
    testWidgets('new alerts appear without refresh; unread count updates', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/alerts');

      expect(find.text('Electro World'), findsOneWidget);
      expect(find.text('High risk'), findsWidgets);
      expect(navBadge('2'), findsOneWidget);

      h.server.simulateSuspiciousPayment();
      await tester.pumpAndSettle();

      expect(find.text('Crypto Xchange'), findsOneWidget);
      expect(find.text('Did you spend ₹24,500?'), findsOneWidget); // push
      expect(navBadge('3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('push-banner')));
      await tester.pumpAndSettle();
      expect(find.text('Did you make this payment?'), findsOneWidget);
      expect(navBadge('2'), findsOneWidget); // opened = read
    });

    testWidgets('filters with a query parameter', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/alerts?status=RESOLVED');
      expect(find.text('Amazon'), findsOneWidget);
      expect(find.text('Electro World'), findsNothing);
    });
  });

  group('Confirm or deny (F2)', () {
    testWidgets('deny needs biometrics, then shows the block and case', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/alerts/alt_1004');

      h.biometric.result = false;
      await tester.tap(find.byKey(const Key('deny-button')));
      await tester.pumpAndSettle();
      expect(find.textContaining('nothing was blocked'), findsOneWidget);
      expect(h.server.blockActions, 0);

      h.biometric.result = true;
      await tester.tap(find.byKey(const Key('deny-button')));
      await tester.pumpAndSettle();
      expect(find.text('Credit card •• 7710 is blocked'), findsOneWidget);
      expect(find.textContaining('FS-2026-000500'), findsOneWidget);
      expect(h.server.blockActions, 1);

      await tester.tap(find.text('View case'));
      await tester.pumpAndSettle();
      expect(find.text('Dispute case'), findsOneWidget);
      expect(find.text('FS-2026-000500'), findsOneWidget);
    });

    testWidgets('"Yes, it was me" clears the alert', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/alerts/alt_1003');
      await tester.tap(find.byKey(const Key('confirm-button')));
      await tester.pumpAndSettle();
      expect(find.text('Thanks for confirming'), findsOneWidget);
      expect(h.biometric.calls, 0);
    });

    testWidgets('an alert for a blocked card needs no action', (tester) async {
      final h = TestHarness();
      final id = h.server.simulateSuspiciousPayment(onBlockedInstrument: true)!;
      await h.pumpApp(tester, location: '/alerts/$id');
      expect(find.text('Blocked — no action needed'), findsWidgets);
      expect(find.byKey(const Key('deny-button')), findsNothing);
    });
  });

  group('Block (F3)', () {
    testWidgets('block with a reason; blocked state shows on home', (
      tester,
    ) async {
      final h = TestHarness();
      final c = await h.pumpApp(tester, location: '/block');

      await tester.tap(find.byKey(const Key('block-ins_upi')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-SUSPICIOUS')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm-block')));
      await tester.pumpAndSettle();

      expect(find.text('UPI pri***@fsbank is blocked.'), findsOneWidget);
      expect(h.server.db.instruments['ins_upi']!['blocked'], isTrue);
      expect(h.biometric.calls, 1);

      c.read(routerProvider).go('/home');
      await tester.pumpAndSettle();
      expect(
        inside(const Key('home-instrument-ins_upi'), find.text('Blocked')),
        findsOneWidget,
      );
    });
  });

  group('Case tracker (F6, F7)', () {
    testWidgets('SLA turns amber in the last 2 days', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/cases/case_462');
      expect(find.text('2 days left'), findsOneWidget);
      final card = tester.widget<Card>(find.byKey(const Key('sla-card')));
      expect(card.color, StatusColors.light.warningContainer);
    });

    testWidgets('a breached SLA shows the escalation path', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/cases/case_437');
      expect(find.text('Overdue by 3 days'), findsOneWidget);
      expect(
        find.text('We missed our promise. How to escalate:'),
        findsOneWidget,
      );
      final card = tester.widget<Card>(find.byKey(const Key('sla-card')));
      expect(card.color, StatusColors.light.dangerContainer);
    });

    testWidgets('provisional credit shows the difference', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/cases/case_481');
      expect(
        find.text('₹2,500.00 less than the disputed amount of ₹12,500.00'),
        findsOneWidget,
      );
      expect(find.text('Decision made on time'), findsOneWidget);
    });

    testWidgets('cases list', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/cases');
      expect(find.textContaining('FS-2026-000462'), findsOneWidget);
      expect(find.text('Overdue by 3 days'), findsOneWidget);
    });
  });

  group('Dispute flow (F4, F5)', () {
    testWidgets('questions change by reason; evidence required; submit', (
      tester,
    ) async {
      final h = TestHarness();
      h.picker.next = [smallPng()];
      await h.pumpApp(tester, location: '/disputes/new');

      await tester.tap(find.text('Swiggy'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reason-UNAUTHORISED')));
      await tester.pumpAndSettle();
      expect(
        find.text('Is your card or phone still with you?'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('reason-WRONG_AMOUNT')));
      await tester.pumpAndSettle();
      expect(find.text('Is your card or phone still with you?'), findsNothing);
      await tester.enterText(find.byKey(const Key('q-agreedAmount')), '300');
      await tester.tap(inside(const Key('q-billAvailable'), find.text('Yes')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('flow-continue')));
      await tester.pumpAndSettle();

      expect(find.text('Required for this dispute'), findsOneWidget);
      FilledButton next() => tester.widget<FilledButton>(
        find.byKey(const Key('evidence-continue')),
      );
      expect(next().onPressed, isNull);

      await tester.tap(find.byKey(const Key('add-files')));
      await tester.pumpAndSettle();
      expect(find.text('Uploaded'), findsOneWidget);
      expect(next().onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('evidence-continue')));
      await tester.pumpAndSettle();
      expect(find.text('₹156.00'), findsOneWidget); // only the difference
      await tester.tap(find.byKey(const Key('submit-dispute')));
      await tester.pumpAndSettle();

      expect(find.text('Dispute case'), findsOneWidget);
      expect(find.text('FS-2026-000500'), findsOneWidget);
    });

    testWidgets('older than 90 days explains the window', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/disputes/new');
      await tester.tap(find.text('TravelNest Hotels'));
      await tester.pumpAndSettle();
      expect(find.text('Too old to dispute in the app'), findsOneWidget);
      expect(find.textContaining('1800-123-4567'), findsOneWidget);
    });
  });

  group('Security centre (F9)', () {
    testWidgets('the current device cannot be signed out; others can', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/security');

      expect(
        inside(const Key('device-dev-test'), find.text('This device')),
        findsOneWidget,
      );
      expect(
        inside(const Key('device-dev-test'), find.text('Sign out')),
        findsNothing,
      );

      await tester.tap(
        inside(const Key('device-dev_ipad'), find.text('Sign out')),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('device-dev_ipad')), findsNothing);
      expect(h.biometric.calls, 1);
    });

    testWidgets('logout goes to login with no navigation code', (tester) async {
      final h = TestHarness();
      await h.pumpApp(tester, location: '/security');
      await tester.tap(find.byKey(const Key('logout-button')));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    });
  });

  group('App lock (B2) and notification privacy', () {
    testWidgets('locks in the background; banners hide details', (
      tester,
    ) async {
      final h = TestHarness();
      await h.pumpApp(tester);

      // Background, then back again (frames only draw while visible).
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      await tester.pumpAndSettle();
      expect(find.text('FraudShield is locked'), findsOneWidget);

      h.server.simulateSuspiciousPayment();
      await tester.pumpAndSettle();
      final banner = find.byKey(const Key('push-banner'));
      expect(
        find.descendant(
          of: banner,
          matching: find.text('FraudShield security alert'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Did you spend'),
        ),
        findsNothing,
      );

      await tester.tap(find.text('Unlock'));
      await tester.pumpAndSettle();
      expect(find.text('FraudShield is locked'), findsNothing);
      expect(
        find.descendant(
          of: banner,
          matching: find.textContaining('Did you spend'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('"Log out instead" from the lock screen', (tester) async {
      final h = TestHarness();
      final c = await h.pumpApp(tester);
      c.read(appLockProvider.notifier).lock();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log out instead'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);
    });
  });
}
