import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/motion/motion.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/alerts/widgets/alert_widgets.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';

/// Filters for /alerts?status=... (query parameter).
enum AlertFilter {
  all(null, 'All'),
  pending('PENDING', 'Needs action'),
  resolved('RESOLVED', 'Resolved');

  const AlertFilter(this.query, this.label);

  final String? query;
  final String label;

  static AlertFilter fromQuery(String? q) => AlertFilter.values.firstWhere(
    (f) => f.query == q,
    orElse: () => AlertFilter.all,
  );

  bool matches(Alert a) => switch (this) {
    AlertFilter.all => true,
    AlertFilter.pending => a.status == AlertStatus.pending,
    AlertFilter.resolved => a.status != AlertStatus.pending,
  };
}

/// F1: the alert inbox. New alerts slide in without a refresh.
class AlertsScreen extends ConsumerStatefulWidget {
  const AlertsScreen({super.key, this.filter = AlertFilter.all});

  final AlertFilter filter;

  @override
  ConsumerState<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends ConsumerState<AlertsScreen> {
  /// Ids already on screen; anything else that appears is animated in.
  Set<String>? _seen;

  Future<void> _refresh() async {
    try {
      await ref.read(alertsProvider.notifier).refresh();
    } on BankError catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = ref.watch(alertsProvider);
    final readIds = ref.watch(readAlertsProvider);
    final now =
        ref.watch(slaTickerProvider).valueOrNull ?? ref.watch(clockProvider)();
    final blockedIds = {
      for (final i
          in ref.watch(instrumentsProvider).valueOrNull ?? const <Instrument>[])
        if (i.blocked) i.id,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: LiveIndicator()),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                for (final f in AlertFilter.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f.label),
                      selected: widget.filter == f,
                      onSelected:
                          (_) => context.go(
                            f.query == null
                                ? '/alerts'
                                : '/alerts?status=${f.query}',
                          ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: alerts.when(
              skipLoadingOnRefresh: true,
              loading: () => const SkeletonList(itemHeight: 120),
              error:
                  (e, _) => RefreshableList(
                    onRefresh: _refresh,
                    children: [
                      ErrorView(
                        error: e,
                        onRetry: () => ref.invalidate(alertsProvider),
                      ),
                    ],
                  ),
              data: (all) {
                final first = _seen == null;
                final seen = _seen ??= {for (final a in all) a.id};
                final visible = all.where(widget.filter.matches).toList();
                if (visible.isEmpty) {
                  return RefreshableList(
                    onRefresh: _refresh,
                    children: [
                      EmptyView(
                        icon: Icons.verified_user_outlined,
                        title:
                            widget.filter == AlertFilter.pending
                                ? 'Nothing needs your answer'
                                : 'No alerts yet',
                        message:
                            'We watch every payment. If something looks '
                            'unusual, you will hear from us instantly.',
                      ),
                    ],
                  );
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (context, index) {
                      final alert = visible[index];
                      final isNew = !first && !seen.contains(alert.id);
                      seen.add(alert.id);
                      return ArrivalAnimation(
                        key: ValueKey(alert.id),
                        animate: isNew,
                        child: AlertTile(
                          alert: alert,
                          now: now,
                          unread:
                              !readIds.contains(alert.id) &&
                              (alert.status == AlertStatus.pending ||
                                  alert.status ==
                                      AlertStatus.instrumentBlocked),
                          instrumentBlocked: blockedIds.contains(
                            alert.instrumentId,
                          ),
                          onTap: () => context.go('/alerts/${alert.id}'),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
