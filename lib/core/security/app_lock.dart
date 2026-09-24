import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true = the lock overlay is showing (B2).
class AppLockNotifier extends Notifier<bool> {
  /// While the biometric prompt is open, a real device may pause the app.
  /// We must not re-lock because of our own prompt.
  bool _authInProgress = false;

  @override
  bool build() => false;

  void lock() {
    if (_authInProgress) return;
    state = true;
  }

  void unlock() => state = false;

  /// Wrap every call to the biometric prompt with this.
  Future<T> whileAuthenticating<T>(Future<T> Function() action) async {
    _authInProgress = true;
    try {
      return await action();
    } finally {
      _authInProgress = false;
    }
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);
