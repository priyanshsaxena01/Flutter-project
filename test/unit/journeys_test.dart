import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/core/notifications/push_notifications.dart';
import 'package:fraud_shield/core/realtime/alert_stream_client.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/disputes/state/upload_queue_provider.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';

import '../helpers/test_app.dart';

/// Notifier-level journeys with a ProviderContainer (no widgets).
void main() {
  late TestHarness h;

  setUp(() => h = TestHarness());

  group('deny -> block -> case created', () {
    test('the main journey', () async {
      final c = await h.container();
      c.listen(alertsProvider, (_, _) {});
      await c.read(alertsProvider.future);
      final casesBefore = (await c.read(casesProvider.future)).length;

      final action = c.listen(alertActionProvider('alt_1004'), (_, _) {});
      await c
          .read(alertActionProvider('alt_1004').notifier)
          .deny(instrumentLabel: 'Credit card •• 7710');

      final state = action.read();
      expect(state.phase, AlertActionPhase.denied);
      expect(state.elapsed! < const Duration(seconds: 2), isTrue);
      expect(h.biometric.calls, 1);

      final alert = c
          .read(alertsProvider)
          .value!
          .firstWhere((a) => a.id == 'alt_1004');
      expect(alert.status, AlertStatus.denied);
      final instruments = await c.read(instrumentsProvider.future);
      expect(
        instruments.firstWhere((i) => i.id == 'ins_credit').blocked,
        isTrue,
      );
      final cases = await c.read(casesProvider.future);
      expect(cases, hasLength(casesBefore + 1));
      expect(cases.first.caseNumber, state.result!.caseNumber);
    });

    test('failed biometrics blocks nothing', () async {
      final c = await h.container();
      h.biometric.result = false;
      final action = c.listen(alertActionProvider('alt_1004'), (_, _) {});
      await c
          .read(alertActionProvider('alt_1004').notifier)
          .deny(instrumentLabel: 'Credit card');
      expect(action.read().error, contains('nothing was blocked'));
      expect(h.server.blockActions, 0);
    });

    test('a double tap sends one request with one key', () async {
      final c = await h.container();
      c.listen(alertActionProvider('alt_1004'), (_, _) {});
      final notifier = c.read(alertActionProvider('alt_1004').notifier);
      await Future.wait([
        notifier.deny(instrumentLabel: 'Card'),
        notifier.deny(instrumentLabel: 'Card'),
      ]);
      expect(h.biometric.calls, 1);
      expect(h.server.blockActions, 1);
    });
  });

  group('live alerts', () {
    test('a new alert appears without refresh and raises a push', () async {
      final c = await h.container();
      c.listen(alertsProvider, (_, _) {});
      c.listen(pushNotificationsProvider, (_, _) {});
      await c.read(alertsProvider.future);
      await waitFor(() => h.server.openStreams == 1);

      final id = h.server.simulateSuspiciousPayment()!;
      await waitFor(() => c.read(alertsProvider).value!.any((a) => a.id == id));
      final push = c.read(pushNotificationsProvider).single;
      expect(push.route, '/alerts/$id');
      expect(push.title, 'Did you spend ₹24,500?');
      expect(c.read(unreadAlertCountProvider), 3);
    });

    test('reconnects with backoff and fetches what it missed', () async {
      final c = await h.container();
      c.listen(alertsProvider, (_, _) {});
      final states = <LiveStatus>[];
      c.listen(liveStateProvider, (_, next) {
        final s = next.valueOrNull?.status;
        if (s != null) states.add(s);
      });
      await c.read(alertsProvider.future);
      await waitFor(() => h.server.openStreams == 1);

      h.server.setOffline(true); // drops the stream; reconnects fail
      final missed = h.server.simulateSuspiciousPayment()!;
      await waitFor(() => states.contains(LiveStatus.reconnecting));
      expect(c.read(alertsProvider).value!.any((a) => a.id == missed), isFalse);

      h.server.setOffline(false);
      await waitFor(
        () => c.read(alertsProvider).value!.any((a) => a.id == missed),
      );
      expect(c.read(alertStreamClientProvider).state.status, LiveStatus.live);
    });

    test('an alert for a blocked card needs no action', () async {
      final c = await h.container();
      c.listen(alertsProvider, (_, _) {});
      await c.read(alertsProvider.future);
      await waitFor(() => h.server.openStreams == 1);
      final id = h.server.simulateSuspiciousPayment(onBlockedInstrument: true)!;
      await waitFor(() => c.read(alertsProvider).value!.any((a) => a.id == id));
      final alert = c.read(alertsProvider).value!.firstWhere((a) => a.id == id);
      expect(alert.status, AlertStatus.instrumentBlocked);
      expect(alert.instrumentId, 'ins_debit');
    });

    test('logout closes the stream (session-driven)', () async {
      final c = await h.container();
      c.listen(alertsProvider, (_, _) {});
      await c.read(alertsProvider.future);
      await waitFor(() => h.server.openStreams == 1);
      await c.read(sessionProvider.notifier).logout();
      await waitFor(() => h.server.openStreams == 0);
      expect(c.read(sessionProvider).isSignedIn, isFalse);
    });
  });

  group('dispute flow', () {
    Future<ProviderContainer> startFlow(
      String txnId,
      DisputeReason reason,
    ) async {
      final c = await h.container();
      c.listen(disputeFlowProvider, (_, _) {});
      final txns = await c.read(transactionsProvider.future);
      c.read(disputeFlowProvider.notifier)
        ..start(txns.firstWhere((t) => t.id == txnId))
        ..chooseReason(reason);
      return c;
    }

    test('changing the reason clears answers', () async {
      final c = await startFlow('txn_3011', DisputeReason.unauthorised);
      final flow = c.read(disputeFlowProvider.notifier)
        ..answer('sharedOtp', 'no');
      flow.chooseReason(DisputeReason.duplicate);
      expect(c.read(disputeFlowProvider).answers, isEmpty);
    });

    test('invalid answers stay on the form with field errors', () async {
      final c = await startFlow('txn_3011', DisputeReason.wrongAmount);
      c.read(disputeFlowProvider.notifier).answer('agreedAmount', '9999');
      expect(await c.read(disputeFlowProvider.notifier).saveDraft(), isFalse);
      expect(
        c.read(disputeFlowProvider).fieldErrors.keys,
        containsAll(['agreedAmount', 'billAvailable']),
      );
      expect(h.server.db.disputes.length, 4); // nothing created
    });

    test(
      'wrong amount: draft, evidence, submit -> case for the difference',
      () async {
        final c = await startFlow('txn_3011', DisputeReason.wrongAmount);
        c.read(disputeFlowProvider.notifier)
          ..answer('agreedAmount', '300')
          ..answer('billAvailable', 'yes');
        expect(await c.read(disputeFlowProvider.notifier).saveDraft(), isTrue);
        final flow = c.read(disputeFlowProvider);
        expect(flow.disputedAmountPaise, 15600); // 456 - 300

        // Required evidence is enforced before calling the server.
        expect(
          await c.read(disputeFlowProvider.notifier).submit(evidenceCount: 0),
          isNull,
        );

        final queue = uploadQueueProvider(flow.disputeId!);
        c.listen(queue, (_, _) {});
        c.read(queue.notifier).addFiles([smallPng()]);
        await waitFor(
          () => c.read(queue).every((i) => i.status == UploadStatus.done),
        );
        final opened = await c
            .read(disputeFlowProvider.notifier)
            .submit(evidenceCount: 1);
        expect(opened!.disputedAmountPaise, 15600);
        expect(opened.reason, DisputeReason.wrongAmount);
      },
    );
  });

  group('evidence upload queue', () {
    test('fails at 90%: only that file is retried', () async {
      final c = await h.container();
      final disputeId = h.server.db.disputes.keys.first;
      final queue = uploadQueueProvider(disputeId);
      c.listen(queue, (_, _) {});

      h.server.chaos.failNextUploadAt90 = true;
      c.read(queue.notifier).addFiles([smallPng('a.png'), smallPng('b.png')]);
      await waitFor(
        () => c
            .read(queue)
            .every(
              (i) =>
                  i.status == UploadStatus.done ||
                  i.status == UploadStatus.failed,
            ),
      );
      final items = c.read(queue);
      expect(items[0].status, UploadStatus.failed);
      expect(items[1].status, UploadStatus.done);

      c.read(queue.notifier).retry(items[0].localId);
      await waitFor(
        () => c.read(queue).every((i) => i.status == UploadStatus.done),
      );
      final names = (h.server.db.disputes[disputeId]!['evidence']! as List).map(
        (e) => (e as Map)['name'],
      );
      expect(names.where((n) => n == 'a.png'), hasLength(1));
      expect(names.where((n) => n == 'b.png'), hasLength(1));
    });

    test('refuses files over the limits before uploading', () async {
      final c = await h.container();
      final disputeId = h.server.db.disputes.keys.first; // has 0 files
      final queue = uploadQueueProvider(disputeId);
      c.listen(queue, (_, _) {});
      final refused = c.read(queue.notifier).addFiles([
        for (var i = 0; i < 6; i++) smallPng('f$i.png'),
      ]);
      expect(refused, hasLength(1));
      expect(refused.single, contains('up to 5 files'));
      await waitFor(
        () => c.read(queue).every((i) => i.status == UploadStatus.done),
      );
      expect(c.read(queue), hasLength(5));
    });
  });

  group('messages', () {
    test('load older pages and send', () async {
      final c = await h.container();
      final provider = caseMessagesProvider('case_462');
      c.listen(provider, (_, _) {});
      final first = await c.read(provider.future);
      expect(first.items, hasLength(15));
      await c.read(provider.notifier).loadOlder();
      expect(c.read(provider).value!.items, hasLength(24));
      expect(c.read(provider).value!.hasOlder, isFalse);

      expect(await c.read(provider.notifier).send('Hello'), isTrue);
      final items = c.read(provider).value!.items;
      expect(items.first.from.api, 'BANK'); // the reply is newest
      expect(items[1].text, 'Hello');
    });
  });
}
