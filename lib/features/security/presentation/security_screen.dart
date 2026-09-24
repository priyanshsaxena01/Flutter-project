import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/security/domain/security_models.dart';
import 'package:fraud_shield/features/security/state/security_providers.dart';

/// F9: profile, logout, signed-in devices and login history.
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _busy = false;

  Future<void> _signOut(List<Device> devices) async {
    if (_busy || devices.isEmpty) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final done = await ref.read(deviceActionsProvider).signOut(devices);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            done
                ? (devices.length == 1
                    ? '${devices.single.name} is signed out.'
                    : 'Other devices are signed out.')
                : 'We could not confirm it\'s you, so nothing changed.',
          ),
        ),
      );
    } on BankError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider);
    final devices = ref.watch(devicesProvider);
    final logins = ref.watch(loginHistoryProvider);
    final now = ref.watch(clockProvider)();
    final useMock = ref.watch(apiConfigProvider).useMock;

    Future<void> refresh() async {
      await Future.wait([
        refreshQuietly(ref.refresh(devicesProvider.future)),
        refreshQuietly(ref.refresh(loginHistoryProvider.future)),
      ]);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Security centre')),
      body: RefreshableList(
        onRefresh: refresh,
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(session.customerName ?? ''),
              subtitle: Text('Customer ID ${session.customerId ?? ''}'),
              trailing: OutlinedButton(
                key: const Key('logout-button'),
                onPressed:
                    () =>
                        unawaited(ref.read(sessionProvider.notifier).logout()),
                child: const Text('Log out'),
              ),
            ),
          ),
          ...devices.when(
            skipLoadingOnRefresh: true,
            loading:
                () => [
                  const SectionTitle('Signed-in devices'),
                  const SizedBox(
                    height: 160,
                    child: SkeletonList(itemCount: 2, itemHeight: 56),
                  ),
                ],
            error:
                (e, _) => [
                  const SectionTitle('Signed-in devices'),
                  ErrorView(
                    error: e,
                    onRetry: () => ref.invalidate(devicesProvider),
                  ),
                ],
            data: (list) {
              final others = list.where((d) => !d.current).toList();
              return [
                SectionTitle(
                  'Signed-in devices',
                  trailing:
                      others.isEmpty
                          ? null
                          : TextButton(
                            key: const Key('sign-out-others'),
                            onPressed:
                                _busy
                                    ? null
                                    : () => unawaited(_signOut(others)),
                            child: const Text('Sign out all others'),
                          ),
                ),
                Card(
                  child: Column(
                    children: [
                      for (final d in list)
                        ListTile(
                          key: Key('device-${d.id}'),
                          leading: Icon(
                            d.name.contains('Pixel') ||
                                    d.name.contains('Android')
                                ? Icons.phone_android
                                : d.name.contains('iPad') ||
                                    d.name.contains('iPhone')
                                ? Icons.tablet_mac
                                : Icons.computer,
                          ),
                          title: Text(d.name),
                          subtitle: Text(
                            '${d.location} · '
                            '${d.current ? 'active now' : Dates.timeAgo(d.lastSeen, now)}',
                          ),
                          // "Current device cannot be removed from itself".
                          trailing:
                              d.current
                                  ? const Tooltip(
                                    message:
                                        'You can\'t sign out the device you are '
                                        'using. Use Log out instead.',
                                    child: StatusChip(
                                      label: 'This device',
                                      icon: Icons.smartphone,
                                      tone: Tone.neutral,
                                    ),
                                  )
                                  : TextButton(
                                    onPressed:
                                        _busy
                                            ? null
                                            : () => unawaited(_signOut([d])),
                                    child: const Text('Sign out'),
                                  ),
                        ),
                    ],
                  ),
                ),
              ];
            },
          ),
          const SectionTitle('Recent logins'),
          logins.when(
            skipLoadingOnRefresh: true,
            loading:
                () => const SizedBox(
                  height: 160,
                  child: SkeletonList(itemCount: 2, itemHeight: 56),
                ),
            error:
                (e, _) => ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(loginHistoryProvider),
                ),
            data:
                (list) => Card(
                  child: Column(
                    children: [
                      for (final l in list.take(8))
                        ListTile(
                          leading: Icon(
                            l.success
                                ? Icons.check_circle_outline
                                : Icons.warning_amber,
                            color:
                                l.success
                                    ? StatusColors.of(context).success
                                    : StatusColors.of(context).danger,
                          ),
                          title: Text(
                            l.success ? 'Signed in' : 'Failed sign-in attempt',
                          ),
                          subtitle: Text(
                            '${l.deviceName} · ${l.location} · '
                            '${Dates.timeAgo(l.at, now)}',
                          ),
                        ),
                    ],
                  ),
                ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.receipt_long_outlined),
                  title: const Text('Activity log'),
                  subtitle: const Text('Every action, with time and device'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/security/activity'),
                ),
                if (useMock)
                  ListTile(
                    leading: const Icon(Icons.science_outlined),
                    title: const Text('Demo controls'),
                    subtitle: const Text('Send alerts, simulate failures'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/demo'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
