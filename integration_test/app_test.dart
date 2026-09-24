import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fraud_shield/app/app.dart';
import 'package:fraud_shield/mock_server/mock_bank_server.dart';

/// The main journey on a real device or emulator:
/// sign in -> alert -> "No, it wasn't me" (fingerprint) -> blocked -> case.
///
///   flutter test integration_test/app_test.dart
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('deny -> block -> case created', (tester) async {
    // The real app with the built-in bank; only automatic alerts are off,
    // so no banner appears in the middle of the journey.
    final server = MockBankServer(autoAlerts: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [mockBankServerProvider.overrideWithValue(server)],
        child: const FraudShieldApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Customer ID'),
      'TEST_CUSTOM',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '0123456789',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    await tester.tap(find.text('Review now'));
    await tester.pumpAndSettle();

    final deny = find.byKey(const Key('deny-button'));
    await tester.ensureVisible(deny);
    await tester.tap(deny);
    await tester.pumpAndSettle();

    // The demo fingerprint prompt.
    await tester.tap(find.byKey(const Key('fingerprint-sensor')));
    await tester.pumpAndSettle();

    expect(find.text('Credit card •• 7710 is blocked'), findsOneWidget);
    expect(server.db.instruments['ins_credit']!['blocked'], isTrue);
    expect(server.blockActions, 1);

    final viewCase = find.text('View case');
    await tester.ensureVisible(viewCase);
    await tester.tap(viewCase);
    await tester.pumpAndSettle();
    expect(find.text('Dispute case'), findsOneWidget);
    expect(find.textContaining('FS-'), findsWidgets);
  });
}
