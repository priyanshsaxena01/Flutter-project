import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/notifications/push_notifications.dart';
import 'package:fraud_shield/core/security/app_lock.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';
import 'package:fraud_shield/features/security/state/security_providers.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';
import 'package:fraud_shield/mock_server/mock_bank_server.dart';

/// Controls for the built-in bank: send alerts on demand and switch on
/// failures ("chaos switches") to demo every edge case.
class DemoControlsScreen extends ConsumerStatefulWidget {
  const DemoControlsScreen({super.key});

  @override
  ConsumerState<DemoControlsScreen> createState() => _DemoControlsScreenState();
}

class _DemoControlsScreenState extends ConsumerState<DemoControlsScreen> {
  void _snack(String text) =>
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(apiConfigProvider).useMock) {
      return Scaffold(
        appBar: AppBar(title: const Text('Demo controls')),
        body: const Center(
          child: EmptyView(
            icon: Icons.cloud_outlined,
            title: 'Using a real server',
            message: 'Demo controls only work with the built-in bank.',
          ),
        ),
      );
    }

    final server = ref.watch(mockBankServerProvider);
    final chaos = server.chaos;

    Widget toggle(
      String title,
      String subtitle,
      bool value,
      void Function(bool) apply,
    ) => SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: (v) => setState(() => apply(v)),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Demo controls')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SectionTitle('Alerts'),
          ),
          ListTile(
            key: const Key('demo-send-alert'),
            leading: const Icon(Icons.bolt),
            title: const Text('Send a suspicious payment now'),
            subtitle: const Text('Arrives on the Alerts tab within a second'),
            onTap: () {
              final id = server.simulateSuspiciousPayment();
              _snack(
                id == null
                    ? 'Every card and UPI ID is blocked. Unblock one first.'
                    : 'Suspicious payment sent.',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.lock_clock),
            title: const Text('Send an alert for a blocked card'),
            subtitle: const Text('Shows "Blocked — no action needed"'),
            onTap: () {
              final id = server.simulateSuspiciousPayment(
                onBlockedInstrument: true,
              );
              _snack(id == null ? 'Block a card or UPI ID first.' : 'Sent.');
            },
          ),
          toggle(
            'Automatic suspicious payments',
            'One every ${server.autoAlertEvery.inSeconds} s while the app is open',
            server.autoAlerts,
            (v) => server.autoAlerts = v,
          ),
          ListTile(
            leading: const Icon(Icons.link_off),
            title: const Text('Drop the live connection'),
            subtitle: const Text('Watch it reconnect with backoff'),
            onTap: () {
              server.dropStreams();
              _snack('Connection dropped.');
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SectionTitle('Failures'),
          ),
          toggle(
            'Offline',
            'Every request fails as if there is no network',
            chaos.offline,
            server.setOffline,
          ),
          toggle(
            'Slow network',
            '8x slower. Try tapping Deny twice.',
            chaos.slowNetwork,
            (v) => chaos.slowNetwork = v,
          ),
          toggle(
            'Fail the next request',
            'The server answers 503 once',
            chaos.failNextRequest,
            (v) => chaos.failNextRequest = v,
          ),
          toggle(
            'Next upload fails at 90%',
            'Then retry just that file',
            chaos.failNextUploadAt90,
            (v) => chaos.failNextUploadAt90 = v,
          ),
          toggle(
            'Card network down',
            'Cases still open; the chargeback is raised later',
            chaos.cardNetworkDown,
            (v) => chaos.cardNetworkDown = v,
          ),
          toggle(
            'Expire the session',
            'The next request returns 401 and signs you out',
            chaos.expireSessionOnNextRequest,
            (v) => chaos.expireSessionOnNextRequest = v,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: SectionTitle('App'),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Lock the app now'),
            subtitle: const Text('Same as sending it to the background'),
            onTap: () => ref.read(appLockProvider.notifier).lock(),
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt),
            title: const Text('Reset demo data'),
            onTap: () {
              server.reset();
              ref
                ..invalidate(alertsProvider)
                ..invalidate(readAlertsProvider)
                ..invalidate(instrumentsProvider)
                ..invalidate(casesProvider)
                ..invalidate(transactionsProvider)
                ..invalidate(devicesProvider)
                ..invalidate(loginHistoryProvider);
              ref.read(disputeFlowProvider.notifier).reset();
              ref.read(pushNotificationsProvider.notifier).clear();
              _snack('Demo data reset.');
            },
          ),
        ],
      ),
    );
  }
}
