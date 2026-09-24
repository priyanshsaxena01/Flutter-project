import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/security/session_store.dart';
import 'package:fraud_shield/features/auth/data/auth_repository.dart';

enum SessionStatus { restoring, signedOut, signedIn }

/// Immutable session state. The router guard watches this.
class SessionState {
  const SessionState._(
    this.status, {
    this.token,
    this.customerName,
    this.customerId,
    this.expired = false,
  });

  const SessionState.restoring() : this._(SessionStatus.restoring);

  const SessionState.signedOut({bool expired = false})
    : this._(SessionStatus.signedOut, expired: expired);

  const SessionState.signedIn({
    required String token,
    required String customerName,
    required String customerId,
  }) : this._(
         SessionStatus.signedIn,
         token: token,
         customerName: customerName,
         customerId: customerId,
       );

  final SessionStatus status;
  final String? token;
  final String? customerName;
  final String? customerId;

  /// true when the server ended the session (the login screen says so).
  final bool expired;

  bool get isSignedIn => status == SessionStatus.signedIn;

  String get firstName => (customerName ?? '').split(' ').first;
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    unawaited(_restore());
    return const SessionState.restoring();
  }

  /// B1: restore the session from storage on launch.
  Future<void> _restore() async {
    final saved = await ref.read(sessionStoreProvider).read();
    if (saved == null) {
      state = const SessionState.signedOut();
      return;
    }
    // Reopening the app must ask for biometrics before showing anything.
    ref.read(appLockProvider.notifier).lock();
    state = SessionState.signedIn(
      token: saved.token,
      customerName: saved.customerName,
      customerId: saved.customerId,
    );
  }

  /// Throws BankError on failure; the login screen shows its message.
  Future<void> login(String customerId, String pin) async {
    final result = await ref
        .read(authRepositoryProvider)
        .login(customerId: customerId, pin: pin);
    await ref
        .read(sessionStoreProvider)
        .write(
          StoredSession(
            token: result.token,
            customerName: result.customerName,
            customerId: result.customerId,
          ),
        );
    ref.read(appLockProvider.notifier).unlock();
    state = SessionState.signedIn(
      token: result.token,
      customerName: result.customerName,
      customerId: result.customerId,
    );
  }

  /// Logout from the Security screen. The router guard moves to /login;
  /// no navigation code needed (B3).
  Future<void> logout() async {
    if (state.isSignedIn) await ref.read(authRepositoryProvider).logout();
    await _clear(expired: false);
  }

  /// Called by the 401 interceptor.
  void expire() {
    if (!state.isSignedIn) return;
    unawaited(_clear(expired: true));
  }

  Future<void> _clear({required bool expired}) async {
    await ref.read(sessionStoreProvider).clear();
    ref.read(appLockProvider.notifier).unlock();
    state = SessionState.signedOut(expired: expired);
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, SessionState>(
  SessionNotifier.new,
);
