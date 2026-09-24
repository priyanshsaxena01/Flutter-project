import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/app/router.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';

void main() {
  const signedIn = SessionState.signedIn(
    token: 't',
    customerName: 'Priyansh Saxena',
    customerId: 'TEST_CUSTOM',
  );
  const signedOut = SessionState.signedOut();
  const restoring = SessionState.restoring();

  String? go(SessionState s, String location) {
    final uri = Uri.parse(location);
    return sessionRedirect(s, uri, uri.path);
  }

  test('a push deep link while logged out lands on login, then continues', () {
    final toLogin = go(signedOut, '/alerts/alt_1004');
    expect(toLogin, '/login?from=%2Falerts%2Falt_1004');
    expect(go(signedIn, toLogin!), '/alerts/alt_1004');
  });

  test('restoring shows splash and remembers the target', () {
    final toSplash = go(restoring, '/cases/case_1');
    expect(toSplash, startsWith('/splash?from='));
    expect(go(signedOut, toSplash!), '/login?from=%2Fcases%2Fcase_1');
  });

  test('signed in users skip login; logout needs no navigation code', () {
    expect(go(signedIn, '/login'), '/home');
    expect(go(signedIn, '/alerts'), isNull);
    expect(go(signedOut, '/home'), '/login?from=%2Fhome');
  });

  test('refuses unsafe redirect targets', () {
    expect(go(signedIn, '/login?from=https://evil.example'), '/home');
    expect(go(signedIn, '/login?from=//evil.example'), '/home');
    expect(go(signedIn, '/login?from=%2Flogin'), '/home');
  });
}
