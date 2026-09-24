import 'package:flutter_riverpod/flutter_riverpod.dart';

/// true = the lock overlay is showing (B2).
class AppLockNotifier extends Notifier<bool> {
  /// The system fingerprint / PIN prompt pauses the app on a real phone.
  /// We must not lock the app because of our own prompt, so locking is
  /// ignored while a prompt is open and for a short grace period after.
  int _promptsOpen = 0;
  DateTime _graceUntil = DateTime(0);

  @override
  bool build() => false;

  void lock() {
    if (_promptsOpen > 0 || DateTime.now().isBefore(_graceUntil)) return;
    state = true;
  }

  void unlock() => state = false;

  /// Wrap every call to a biometric prompt with this.
  Future<T> whileAuthenticating<T>(
    Future<T> Function() action, {
    Duration grace = Duration.zero,
  }) async {
    _promptsOpen++;
    try {
      return await action();
    } finally {
      _promptsOpen--;
      final until = DateTime.now().add(grace);
      if (until.isAfter(_graceUntil)) _graceUntil = until;
    }
  }
}

final appLockProvider = NotifierProvider<AppLockNotifier, bool>(
  AppLockNotifier.new,
);
