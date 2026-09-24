import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/motion/motion.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/alerts/widgets/alert_widgets.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';

/// F2: "Yes, it was me" / "No, it wasn't me".
class AlertDetailScreen extends ConsumerStatefulWidget {
  const AlertDetailScreen({super.key, required this.alertId});

  final String alertId;

  @override
  ConsumerState<AlertDetailScreen> createState() => _AlertDetailScreenState();
}

class _AlertDetailScreenState extends ConsumerState<AlertDetailScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the alert marks it read (after this frame builds).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(readAlertsProvider.notifier).markRead(widget.alertId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final alert = ref.watch(alertProvider(widget.alertId));
    return Scaffold(
      appBar: AppBar(title: const Text('Security alert')),
      body: alert.when(
        loading: () => const SkeletonList(itemCount: 3, itemHeight: 140),
        error:
            (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(alertFetchProvider(widget.alertId)),
            ),
        data: (a) => _AlertBody(alert: a),
      ),
    );
  }
}

class _AlertBody extends ConsumerWidget {
  const _AlertBody({required this.alert});

  final Alert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final action = ref.watch(alertActionProvider(alert.id));
    final instrument =
        ref
            .watch(instrumentsProvider)
            .valueOrNull
            ?.where((i) => i.id == alert.instrumentId)
            .firstOrNull;
    final instrumentBlocked = instrument?.blocked ?? false;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                const SizedBox(height: 16),
                Text(
                  Money.format(alert.amountPaise),
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(alert.merchant, style: theme.textTheme.titleLarge),
                const Divider(height: 24),
                InfoRow(label: 'Paid with', value: alert.instrumentLabel),
                InfoRow(label: 'Where', value: alert.location),
                InfoRow(label: 'When', value: Dates.dateTime(alert.at)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        InlineMessage(
          tone: alert.riskLevel == RiskLevel.high ? Tone.danger : Tone.warning,
          title: 'Why we flagged it',
          message: alert.riskReason,
        ),
        const SizedBox(height: 20),
        ..._actions(context, ref, action, instrumentBlocked),
      ],
    );
  }

  List<Widget> _actions(
    BuildContext context,
    WidgetRef ref,
    AlertActionState action,
    bool instrumentBlocked,
  ) {
    final notifier = ref.read(alertActionProvider(alert.id).notifier);
    final error =
        action.error == null
            ? const <Widget>[]
            : [
              InlineMessage(message: action.error!),
              const SizedBox(height: 12),
            ];

    // Just denied on this screen: show the outcome with the lock animation.
    final result = action.result;
    if (action.phase == AlertActionPhase.denied && result != null) {
      return [
        _DeniedPanel(
          instrumentLabel: result.instrumentLabel,
          caseNumber: result.caseNumber,
          elapsed: result.alreadyDone ? null : action.elapsed,
          onViewCase: () => context.go('/cases/${result.caseId}'),
          onAddEvidence: () => context.push('/cases/${result.caseId}/evidence'),
        ),
      ];
    }

    switch (alert.status) {
      case AlertStatus.confirmed:
        return [
          const InlineMessage(
            tone: Tone.success,
            title: 'Thanks for confirming',
            message: 'No further action is needed.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Changed your mind? Block the instrument and raise a dispute.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed:
                () => context.push('/block?instrumentId=${alert.instrumentId}'),
            icon: const Icon(Icons.block),
            label: const Text('Block instrument'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => context.push('/disputes/new/${alert.txnId}'),
            icon: const Icon(Icons.gavel_outlined),
            label: const Text('Raise a dispute'),
          ),
        ];
      case AlertStatus.denied:
        return [
          InlineMessage(
            tone: Tone.danger,
            icon: Icons.lock,
            title: 'You reported this payment',
            message:
                '${alert.instrumentLabel} is blocked and a dispute case is '
                'open.',
          ),
          if (alert.caseId != null) ...[
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => context.go('/cases/${alert.caseId}'),
              child: const Text('View case'),
            ),
          ],
        ];
      case AlertStatus.instrumentBlocked:
        return [
          const InlineMessage(
            tone: Tone.neutral,
            icon: Icons.lock_outline,
            title: 'Blocked — no action needed',
            message:
                'This payment was declined because the instrument is '
                'already blocked. No money left your account.',
          ),
        ];
      case AlertStatus.pending:
        if (instrumentBlocked) {
          return [
            ...error,
            const InlineMessage(
              tone: Tone.neutral,
              icon: Icons.lock_outline,
              title: 'Blocked — no action needed',
              message:
                  'This instrument is already blocked, so it cannot be used '
                  'again. If this payment went through, you can dispute it.',
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => context.push('/disputes/new/${alert.txnId}'),
              icon: const Icon(Icons.gavel_outlined),
              label: const Text('Raise a dispute'),
            ),
          ];
        }
        final errorColor = Theme.of(context).colorScheme.error;
        final onErrorColor = Theme.of(context).colorScheme.onError;
        return [
          ...error,
          Text(
            'Did you make this payment?',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const Key('deny-button'),
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: onErrorColor,
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed:
                action.busy
                    ? null
                    : () => unawaited(
                      notifier.deny(instrumentLabel: alert.instrumentLabel),
                    ),
            icon:
                action.phase == AlertActionPhase.denying
                    ? const _ButtonSpinner()
                    : const Icon(Icons.block),
            label: Text(
              action.phase == AlertActionPhase.denying
                  ? 'Blocking…'
                  : 'No, it wasn\'t me — block it',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const Key('confirm-button'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            onPressed: action.busy ? null : () => unawaited(notifier.confirm()),
            icon:
                action.phase == AlertActionPhase.confirming
                    ? const _ButtonSpinner()
                    : const Icon(Icons.check),
            label: const Text('Yes, it was me'),
          ),
          const SizedBox(height: 12),
          Text(
            'Blocking needs your fingerprint. It stops ${alert.instrumentLabel} '
            'immediately and opens a dispute case for you.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ];
    }
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) => const SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2),
  );
}

class _DeniedPanel extends StatelessWidget {
  const _DeniedPanel({
    required this.instrumentLabel,
    required this.caseNumber,
    required this.elapsed,
    required this.onViewCase,
    required this.onAddEvidence,
  });

  final String instrumentLabel;
  final String caseNumber;
  final Duration? elapsed;
  final VoidCallback onViewCase;
  final VoidCallback onAddEvidence;

  @override
  Widget build(BuildContext context) {
    final colors = StatusColors.of(context);
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Card(
        color: colors.dangerContainer,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              LockConfirmation(color: colors.onDangerContainer),
              const SizedBox(height: 12),
              Text(
                '$instrumentLabel is blocked',
                style: theme.textTheme.titleLarge?.copyWith(
                  color: colors.onDangerContainer,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                caseNumber.isEmpty
                    ? 'A dispute case is open. We will keep you updated.'
                    : 'Dispute case $caseNumber is open. We will keep you '
                        'updated there.',
                style: TextStyle(color: colors.onDangerContainer),
                textAlign: TextAlign.center,
              ),
              if (elapsed != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Done in ${(elapsed!.inMilliseconds / 1000).toStringAsFixed(1)} s',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onDangerContainer,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onViewCase,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('View case'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onAddEvidence,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Add evidence (optional)'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
