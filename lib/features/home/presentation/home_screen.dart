import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/alerts/state/alerts_providers.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/domain/case_rules.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/cases/widgets/case_widgets.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';
import 'package:fraud_shield/features/instruments/widgets/instrument_widgets.dart';

/// /home: alerts summary, blocked instruments and open cases.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider.select((s) => s.firstName));
    final useMock = ref.watch(apiConfigProvider).useMock;

    Future<void> refresh() async {
      await Future.wait([
        refreshQuietly(ref.read(alertsProvider.notifier).refresh()),
        refreshQuietly(ref.read(instrumentsProvider.notifier).refresh()),
        refreshQuietly(ref.refresh(casesProvider.future)),
      ]);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(name.isEmpty ? 'FraudShield' : 'Hi $name'),
        actions: [
          if (useMock)
            IconButton(
              tooltip: 'Demo controls',
              onPressed: () => context.push('/demo'),
              icon: const Icon(Icons.science_outlined),
            ),
        ],
      ),
      body: RefreshableList(
        onRefresh: refresh,
        children: [
          const _AlertSummary(),
          SectionTitle(
            'Your cards & UPI',
            trailing: TextButton(
              onPressed: () => context.push('/block'),
              child: const Text('Block / unblock'),
            ),
          ),
          const _Instruments(),
          SectionTitle(
            'Disputes',
            trailing: TextButton(
              onPressed: () => context.go('/cases'),
              child: const Text('See all'),
            ),
          ),
          const _OpenCases(),
          const SectionTitle('Quick actions'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.block),
                label: const Text('Block a card or UPI'),
                onPressed: () => context.push('/block'),
              ),
              ActionChip(
                avatar: const Icon(Icons.gavel_outlined),
                label: const Text('Raise a dispute'),
                onPressed: () => context.push('/disputes/new'),
              ),
              ActionChip(
                avatar: const Icon(Icons.devices_outlined),
                label: const Text('Devices & logins'),
                onPressed: () => context.go('/security'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AlertSummary extends ConsumerWidget {
  const _AlertSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alerts = ref.watch(alertsProvider);
    final theme = Theme.of(context);
    return alerts.when(
      skipLoadingOnRefresh: true,
      loading:
          () => const SizedBox(height: 140, child: SkeletonList(itemCount: 1)),
      error: (e, _) => InlineMessage(message: friendlyMessage(e)),
      data: (list) {
        final pending = list.where((a) => a.needsAction).toList();
        if (pending.isEmpty) {
          return const InlineMessage(
            tone: Tone.success,
            icon: Icons.verified_user_outlined,
            title: 'All clear',
            message: 'No payments need your attention right now.',
          );
        }
        final top = pending.first;
        final colors = StatusColors.of(context);
        return Card(
          color: colors.dangerContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.gpp_maybe, color: colors.onDangerContainer),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        pending.length == 1
                            ? '1 payment needs your answer'
                            : '${pending.length} payments need your answer',
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onDangerContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Did you spend ${Money.format(top.amountPaise)} at '
                  '${top.merchant} (${top.location})?',
                  style: TextStyle(color: colors.onDangerContainer),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/alerts/${top.id}'),
                  child: const Text('Review now'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// "Blocked state visible on the home screen" (F3).
class _Instruments extends ConsumerWidget {
  const _Instruments();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instruments = ref.watch(instrumentsProvider);
    return instruments.when(
      skipLoadingOnRefresh: true,
      loading:
          () => const SizedBox(
            height: 200,
            child: SkeletonList(itemCount: 2, itemHeight: 64),
          ),
      error:
          (e, _) => ErrorView(
            error: e,
            onRetry: () => ref.invalidate(instrumentsProvider),
          ),
      data:
          (list) => Card(
            child: Column(
              children: [
                for (final i in list)
                  ListTile(
                    key: Key('home-instrument-${i.id}'),
                    leading: Icon(instrumentIcon(i.type)),
                    title: Text(i.label),
                    subtitle: Text(i.masked),
                    trailing: InstrumentStatusChip(instrument: i),
                    onTap: () => context.push('/block?instrumentId=${i.id}'),
                  ),
              ],
            ),
          ),
    );
  }
}

class _OpenCases extends ConsumerWidget {
  const _OpenCases();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cases = ref.watch(casesProvider);
    final now =
        ref.watch(slaTickerProvider).valueOrNull ?? ref.watch(clockProvider)();
    return cases.when(
      skipLoadingOnRefresh: true,
      loading:
          () => const SizedBox(
            height: 80,
            child: SkeletonList(itemCount: 1, itemHeight: 56),
          ),
      error: (e, _) => InlineMessage(message: friendlyMessage(e)),
      data: (list) {
        final open =
            list.where((c) => !c.status.isClosed).toList()
              ..sort((a, b) => a.slaDueAt.compareTo(b.slaDueAt));
        if (open.isEmpty) {
          return const Text('No open disputes.');
        }
        return Card(
          child: Column(
            children: [
              for (final c in open.take(3))
                ListTile(
                  title: Text(
                    '${c.merchant} · ${Money.format(c.disputedAmountPaise)}',
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SlaChip(sla: slaOf(c, now)),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.go('/cases/${c.id}'),
                ),
              if (open.any((c) => slaOf(c, now).level == SlaLevel.breached))
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text('A case is overdue. Open it to escalate.'),
                ),
            ],
          ),
        );
      },
    );
  }
}
