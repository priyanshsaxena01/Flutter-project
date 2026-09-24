import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/realtime/alert_stream_client.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';

/// Risk shown as colour + icon + text (Accessibility NFR).
class RiskBadge extends StatelessWidget {
  const RiskBadge({super.key, required this.level});

  final RiskLevel level;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: level.label,
    icon: switch (level) {
      RiskLevel.high => Icons.gpp_bad_outlined,
      RiskLevel.medium => Icons.report_outlined,
      RiskLevel.low => Icons.info_outline,
    },
    tone: switch (level) {
      RiskLevel.high => Tone.danger,
      RiskLevel.medium => Tone.warning,
      RiskLevel.low => Tone.neutral,
    },
  );
}

class AlertStatusChip extends StatelessWidget {
  const AlertStatusChip({
    super.key,
    required this.alert,
    this.instrumentBlocked = false,
  });

  final Alert alert;

  /// The alert is still pending, but its instrument is blocked already.
  final bool instrumentBlocked;

  @override
  Widget build(BuildContext context) {
    if (alert.status == AlertStatus.pending && instrumentBlocked) {
      return const StatusChip(
        label: 'Blocked — no action needed',
        icon: Icons.lock_outline,
        tone: Tone.neutral,
      );
    }
    return switch (alert.status) {
      AlertStatus.pending => const StatusChip(
        label: 'Needs your answer',
        icon: Icons.help_outline,
        tone: Tone.warning,
      ),
      AlertStatus.confirmed => const StatusChip(
        label: 'You confirmed',
        icon: Icons.check_circle_outline,
        tone: Tone.success,
      ),
      AlertStatus.denied => const StatusChip(
        label: 'Blocked · case open',
        icon: Icons.lock,
        tone: Tone.danger,
      ),
      AlertStatus.instrumentBlocked => const StatusChip(
        label: 'Blocked — no action needed',
        icon: Icons.lock_outline,
        tone: Tone.neutral,
      ),
    };
  }
}

class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.alert,
    required this.unread,
    required this.now,
    required this.onTap,
    this.instrumentBlocked = false,
  });

  final Alert alert;
  final bool unread;
  final DateTime now;
  final VoidCallback onTap;
  final bool instrumentBlocked;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (unread)
                    Semantics(
                      label: 'Unread',
                      child: Container(
                        width: 10,
                        height: 10,
                        margin: const EdgeInsets.only(top: 6, right: 8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      alert.merchant,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: unread ? FontWeight.bold : FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Money.format(alert.amountPaise),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${alert.instrumentLabel} · ${alert.location}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                Dates.timeAgo(alert.at, now),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  RiskBadge(level: alert.riskLevel),
                  AlertStatusChip(
                    alert: alert,
                    instrumentBlocked: instrumentBlocked,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Live" dot for the alerts stream, with a manual reconnect.
class LiveIndicator extends ConsumerWidget {
  const LiveIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = ref.watch(liveStateProvider).valueOrNull;
    final status = live?.status ?? LiveStatus.connecting;
    final colors = StatusColors.of(context);
    final (label, color) = switch (status) {
      LiveStatus.live => ('Live', colors.success),
      LiveStatus.connecting => ('Connecting…', colors.warning),
      LiveStatus.reconnecting => ('Reconnecting…', colors.warning),
      LiveStatus.idle => ('Offline', colors.danger),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'Live alerts: $label',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                status == LiveStatus.live ? Icons.circle : Icons.sync,
                size: 12,
                color: color,
              ),
              const SizedBox(width: 6),
              ExcludeSemantics(child: Text(label)),
            ],
          ),
        ),
        if (status == LiveStatus.reconnecting)
          TextButton(
            onPressed: () => ref.read(alertStreamClientProvider).reconnectNow(),
            child: const Text('Retry now'),
          ),
      ],
    );
  }
}
