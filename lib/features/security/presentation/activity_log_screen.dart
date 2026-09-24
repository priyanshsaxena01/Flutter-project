import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/security/state/security_providers.dart';

/// The server's immutable action log: every change, with the client
/// timestamp and device id (Auditability NFR).
class ActivityLogScreen extends ConsumerWidget {
  const ActivityLogScreen({super.key});

  static String describe(String action) {
    final parts = action.split(' ');
    if (parts.length < 2) return action;
    final path = parts[1];
    if (path.endsWith('/deny')) return 'Reported a payment as not me';
    if (path.endsWith('/confirm')) return 'Confirmed a payment';
    if (path.endsWith('/unblock')) return 'Unblocked an instrument';
    if (path.endsWith('/block')) return 'Blocked an instrument';
    if (path.endsWith('/evidence')) return 'Uploaded evidence';
    if (path.endsWith('/submit')) return 'Submitted a dispute';
    if (path == '/disputes') return 'Started a dispute';
    if (path.endsWith('/messages')) return 'Sent a secure message';
    if (path.startsWith('/devices')) return 'Signed out a device';
    if (path == '/auth/login') return 'Signed in';
    if (path == '/auth/logout') return 'Signed out';
    if (parts[0] == 'PATCH') return 'Edited a dispute draft';
    return action;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final log = ref.watch(auditLogProvider);
    Future<void> refresh() =>
        refreshQuietly(ref.refresh(auditLogProvider.future));

    return Scaffold(
      appBar: AppBar(title: const Text('Activity log')),
      body: log.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(itemHeight: 64),
        error:
            (e, _) => RefreshableList(
              onRefresh: refresh,
              children: [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(auditLogProvider),
                ),
              ],
            ),
        data:
            (entries) => RefreshableList(
              onRefresh: refresh,
              children: [
                if (entries.isEmpty)
                  const EmptyView(
                    icon: Icons.receipt_long_outlined,
                    title: 'No activity yet',
                    message:
                        'Actions you take appear here with the time and device.',
                  ),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      (e.status ?? 200) < 300
                          ? Icons.check
                          : Icons.error_outline,
                    ),
                    title: Text(describe(e.action)),
                    subtitle: Text(
                      'Server ${Dates.dateTime(e.at)}'
                      '${e.clientAt == null ? '' : ' · device clock ${Dates.time(e.clientAt!)}'}'
                      '\nDevice ${e.deviceId} · result ${e.status ?? '-'}',
                    ),
                    isThreeLine: true,
                  ),
              ],
            ),
      ),
    );
  }
}
