import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/idempotency.dart';
import 'package:fraud_shield/core/notifications/push_notifications.dart';
import 'package:fraud_shield/core/realtime/alert_stream_client.dart';
import 'package:fraud_shield/core/realtime/backoff.dart';
import 'package:fraud_shield/core/security/biometric_service.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/features/alerts/data/alert_repository.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';

/// Reconnect timing for the live stream. Tests make it fast.
final streamBackoffProvider = Provider<Backoff>((ref) => const Backoff());

/// The live connection. It exists while signed in and is torn down on
/// logout (it watches the session).
final alertStreamClientProvider = Provider<AlertStreamClient>((ref) {
  final signedIn = ref.watch(sessionProvider.select((s) => s.isSignedIn));
  final client = AlertStreamClient(
    dio: ref.watch(dioProvider),
    backoff: ref.watch(streamBackoffProvider),
  );
  ref.onDispose(client.dispose);
  if (signedIn) client.start();
  return client;
});

/// "Live" / "Reconnecting…" for the Alerts app bar.
final liveStateProvider = StreamProvider<LiveState>((ref) async* {
  final client = ref.watch(alertStreamClientProvider);
  yield client.state;
  yield* client.states;
});

/// The alert inbox (F1). New alerts from the stream are merged in without
/// a refresh; after a reconnect it fetches alerts since the newest id.
class AlertsNotifier extends AsyncNotifier<List<Alert>> {
  /// Alerts that arrive while the first page is still loading.
  final _early = <Alert>[];
  var _disposed = false;

  @override
  Future<List<Alert>> build() async {
    _disposed = false;
    ref.watch(sessionProvider.select((s) => s.token));
    final client = ref.watch(alertStreamClientProvider);
    final subscription = client.events.listen(_onEvent);
    ref.onDispose(() {
      _disposed = true;
      unawaited(subscription.cancel());
    });

    _early.clear();
    final alerts = await ref.read(alertRepositoryProvider).fetchAlerts();
    return AlertRules.merge(alerts, _early);
  }

  void _onEvent(RealtimeEvent event) {
    switch (event) {
      case AlertPushed(:final json):
        _onAlert(Alert.fromJson(json));
      case StreamReconnected():
        unawaited(_catchUp());
    }
  }

  void _onAlert(Alert alert) {
    final current = state.valueOrNull;
    final known =
        (current?.any((a) => a.id == alert.id) ?? false) ||
        _early.any((a) => a.id == alert.id);

    if (state.isLoading || current == null) _early.add(alert);
    if (current != null) state = AsyncData(AlertRules.merge(current, [alert]));

    if (!known &&
        (alert.status == AlertStatus.pending ||
            alert.status == AlertStatus.instrumentBlocked)) {
      ref
          .read(pushNotificationsProvider.notifier)
          .show(
            PushNotice(
              id: 'push-${alert.id}',
              title:
                  alert.status == AlertStatus.pending
                      ? 'Did you spend ${Money.compact(alert.amountPaise)}?'
                      : 'Payment declined on a blocked instrument',
              body: '${alert.merchant} · ${alert.instrumentLabel}',
              route: '/alerts/${alert.id}',
            ),
          );
    }
  }

  /// "The stream disconnects: reconnect with backoff and fetch missed
  /// alerts since the last id".
  Future<void> _catchUp() async {
    final current = state.valueOrNull;
    if (current == null) return;
    final newestId = current.isEmpty ? null : current.first.id;
    try {
      final missed = await ref
          .read(alertRepositoryProvider)
          .fetchAlerts(sinceId: newestId);
      if (_disposed) return;
      final latest = state.valueOrNull ?? current;
      state = AsyncData(AlertRules.merge(latest, missed));
    } on BankError {
      // The next reconnect tries again; the list keeps what it has.
    }
  }

  /// Pull-to-refresh. Keeps the old list on screen if it fails, and
  /// rethrows so the screen can say so.
  Future<void> refresh() async {
    final previous = state.valueOrNull;
    try {
      final alerts = await ref.read(alertRepositoryProvider).fetchAlerts();
      state = AsyncData(alerts);
    } on BankError catch (e, st) {
      if (previous == null) {
        state = AsyncError(e, st);
      } else {
        rethrow;
      }
    }
  }

  void upsert(Alert alert) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(AlertRules.merge(current, [alert]));
  }
}

final alertsProvider = AsyncNotifierProvider<AlertsNotifier, List<Alert>>(
  AlertsNotifier.new,
);

/// Alerts the user has opened (drives the unread badge).
class ReadAlertsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    ref.watch(sessionProvider.select((s) => s.token));
    return const {};
  }

  void markRead(String id) {
    if (state.contains(id)) return;
    state = {...state, id};
  }
}

final readAlertsProvider = NotifierProvider<ReadAlertsNotifier, Set<String>>(
  ReadAlertsNotifier.new,
);

/// "Unread count on the tab".
final unreadAlertCountProvider = Provider<int>((ref) {
  final alerts = ref.watch(alertsProvider).valueOrNull ?? const <Alert>[];
  return AlertRules.unreadCount(alerts, ref.watch(readAlertsProvider));
});

/// One alert fetched by id, for deep links opened before the list loads.
final alertFetchProvider = FutureProvider.autoDispose.family<Alert, String>(
  (ref, id) => ref.watch(alertRepositoryProvider).fetchAlert(id),
);

/// One alert: from the live list when it is there, otherwise fetched.
final alertProvider = Provider.autoDispose.family<AsyncValue<Alert>, String>((
  ref,
  id,
) {
  final fromList = ref.watch(
    alertsProvider.select(
      (v) => v.valueOrNull?.where((a) => a.id == id).firstOrNull,
    ),
  );
  if (fromList != null) return AsyncData(fromList);
  return ref.watch(alertFetchProvider(id));
});

// ---------------------------------------------------------------------------
// Confirm / deny (F2)
// ---------------------------------------------------------------------------

enum AlertActionPhase { idle, confirming, denying, confirmed, denied }

class AlertActionState {
  const AlertActionState({
    this.phase = AlertActionPhase.idle,
    this.error,
    this.result,
    this.elapsed,
  });

  final AlertActionPhase phase;
  final String? error;
  final DenyResult? result;

  /// How long deny-and-block took end to end (NFR: under 2 s).
  final Duration? elapsed;

  bool get busy =>
      phase == AlertActionPhase.confirming || phase == AlertActionPhase.denying;
}

class AlertActionNotifier
    extends AutoDisposeFamilyNotifier<AlertActionState, String> {
  /// Created once per alert screen and reused for every retry (B6), so a
  /// double tap or a retry on a flaky network gives one block, one case.
  final String denyKey = newIdempotencyKey();

  /// Also covers the time the fingerprint prompt is open.
  bool _inProgress = false;

  @override
  AlertActionState build(String alertId) => const AlertActionState();

  Future<void> confirm() async {
    if (_inProgress) return;
    _inProgress = true;
    final keepAlive = ref.keepAlive();
    state = const AlertActionState(phase: AlertActionPhase.confirming);
    try {
      final alert = await ref.read(alertRepositoryProvider).confirm(arg);
      ref.read(alertsProvider.notifier).upsert(alert);
      state = const AlertActionState(phase: AlertActionPhase.confirmed);
    } on BankError catch (e) {
      state = AlertActionState(error: e.message);
      if (e is ConflictError) ref.invalidate(alertFetchProvider(arg));
    } finally {
      _inProgress = false;
      keepAlive.close();
    }
  }

  Future<void> deny({required String instrumentLabel}) async {
    if (_inProgress) return;
    _inProgress = true;
    final keepAlive = ref.keepAlive();
    try {
      // Security NFR: deny requires biometrics.
      final verified = await ref
          .read(biometricServiceProvider)
          .confirm('Block $instrumentLabel and report this payment');
      if (!verified) {
        state = const AlertActionState(
          error: 'We could not confirm it\'s you, so nothing was blocked.',
        );
        return;
      }

      state = const AlertActionState(phase: AlertActionPhase.denying);
      final stopwatch = Stopwatch()..start();
      final result = await ref
          .read(alertRepositoryProvider)
          .deny(arg, idempotencyKey: denyKey);
      stopwatch.stop();

      ref.read(alertsProvider.notifier).upsert(result.alert);
      ref.invalidate(instrumentsProvider);
      ref.invalidate(casesProvider);
      ref.invalidate(transactionsProvider);
      state = AlertActionState(
        phase: AlertActionPhase.denied,
        result: result,
        elapsed: stopwatch.elapsed,
      );
    } on BankError catch (e) {
      // Same key on retry, so trying again is always safe.
      state = AlertActionState(error: e.message);
    } finally {
      _inProgress = false;
      keepAlive.close();
    }
  }
}

final alertActionProvider = NotifierProvider.autoDispose
    .family<AlertActionNotifier, AlertActionState, String>(
      AlertActionNotifier.new,
    );
