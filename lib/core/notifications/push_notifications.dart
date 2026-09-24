import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A push notification. The app ships with an in-app banner (no Firebase or
/// notification plugin to set up); the same notice could be handed to
/// flutter_local_notifications or FCM.
class PushNotice {
  const PushNotice({
    required this.id,
    required this.title,
    required this.body,
    required this.route,
  });

  final String id;

  /// Full text, e.g. "Did you spend ₹4,999?"
  final String title;
  final String body;

  /// Deep link opened on tap, e.g. "/alerts/alt_1004".
  final String route;

  /// Security NFR: no transaction details while the app is locked.
  static const lockedTitle = 'FraudShield security alert';
  static const lockedBody = 'Unlock the app to review it.';
}

class PushNotificationsNotifier extends Notifier<List<PushNotice>> {
  @override
  List<PushNotice> build() => const [];

  void show(PushNotice notice) {
    if (state.any((n) => n.id == notice.id)) return;
    state = [...state, notice];
  }

  void dismiss(String id) =>
      state = [
        for (final n in state)
          if (n.id != id) n,
      ];

  void clear() => state = const [];
}

final pushNotificationsProvider =
    NotifierProvider<PushNotificationsNotifier, List<PushNotice>>(
      PushNotificationsNotifier.new,
    );
