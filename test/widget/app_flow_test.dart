import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_app.dart';

/// The main journey as a widget flow test:
/// sign in -> review the alert -> "No, it wasn't me" -> case -> message.
void main() {
  testWidgets('sign in, deny, see the case, message the bank', (tester) async {
    final h = TestHarness();
    await h.pumpApp(tester, signedIn: false);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Customer ID'),
      'TEST_CUSTOM',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'PIN'),
      '0123456789',
    );
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Review now'));
    await tester.pumpAndSettle();
    expect(find.text('Electro World'), findsOneWidget);

    await tester.tap(find.byKey(const Key('deny-button')));
    await tester.pumpAndSettle();
    expect(find.text('Credit card •• 7710 is blocked'), findsOneWidget);

    await tester.tap(find.text('View case'));
    await tester.pumpAndSettle();
    expect(
      find.text('Chargeback raised with the card network'),
      findsOneWidget,
    );

    await tester.tap(find.textContaining('Messages with the bank'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('message-input')),
      'Please help',
    );
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    expect(find.text('Please help'), findsOneWidget);
    expect(find.textContaining('added this to your case'), findsOneWidget);

    // Back on Home: the credit card now shows as blocked.
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('1 payment needs your answer'), findsOneWidget);
    expect(h.server.blockActions, 1);
  });
}
