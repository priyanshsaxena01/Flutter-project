import 'package:flutter/material.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/motion/motion.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/domain/case_rules.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';

SlaStatus slaOf(DisputeCase c, DateTime now) => CaseRules.sla(
  openedAt: c.createdAt,
  dueAt: c.slaDueAt,
  now: now,
  met: c.slaMet,
);

Tone toneOf(SlaLevel level) => switch (level) {
  SlaLevel.onTrack => Tone.neutral,
  SlaLevel.dueSoon => Tone.warning,
  SlaLevel.breached => Tone.danger,
  SlaLevel.met => Tone.success,
};

IconData slaIcon(SlaLevel level) => switch (level) {
  SlaLevel.onTrack => Icons.schedule,
  SlaLevel.dueSoon => Icons.hourglass_bottom,
  SlaLevel.breached => Icons.error_outline,
  SlaLevel.met => Icons.check_circle_outline,
};

class CaseStatusChip extends StatelessWidget {
  const CaseStatusChip({super.key, required this.status});

  final CaseStatus status;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: status.label,
    icon: switch (status) {
      CaseStatus.open => Icons.folder_open,
      CaseStatus.inReview => Icons.manage_search,
      CaseStatus.credited => Icons.savings_outlined,
      CaseStatus.resolved => Icons.verified_outlined,
      CaseStatus.rejected => Icons.cancel_outlined,
    },
    tone: switch (status) {
      CaseStatus.resolved || CaseStatus.credited => Tone.success,
      CaseStatus.rejected => Tone.danger,
      CaseStatus.open || CaseStatus.inReview => Tone.neutral,
    },
  );
}

class SlaChip extends StatelessWidget {
  const SlaChip({super.key, required this.sla});

  final SlaStatus sla;

  @override
  Widget build(BuildContext context) => StatusChip(
    label: sla.level == SlaLevel.met ? 'Decision on time' : sla.label,
    icon: slaIcon(sla.level),
    tone: toneOf(sla.level),
  );
}

/// F6: SLA countdown. Amber in the last 2 days, red with the escalation
/// path once breached.
class SlaCard extends StatelessWidget {
  const SlaCard({
    super.key,
    required this.disputeCase,
    required this.now,
    required this.onMessage,
  });

  final DisputeCase disputeCase;
  final DateTime now;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sla = slaOf(disputeCase, now);
    final (background, foreground) = toneOf(sla.level).colors(context);
    final colors = StatusColors.of(context);
    final barColor = switch (sla.level) {
      SlaLevel.onTrack => theme.colorScheme.primary,
      SlaLevel.dueSoon => colors.warning,
      SlaLevel.breached => colors.danger,
      SlaLevel.met => colors.success,
    };

    return Card(
      key: const Key('sla-card'),
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(slaIcon(sla.level), color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Provisional credit decision',
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Semantics(
              liveRegion: true,
              child: Text(
                sla.label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            Text(
              sla.level == SlaLevel.met
                  ? 'The bank decided within the ${CaseRules.slaDays}-day promise.'
                  : 'Due by ${Dates.dateTime(disputeCase.slaDueAt)} '
                      '(${CaseRules.slaDays} days from opening)',
              style: TextStyle(color: foreground),
            ),
            if (sla.level != SlaLevel.met) ...[
              const SizedBox(height: 12),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: sla.progress),
                duration: Motion.duration(context, Motion.medium),
                builder:
                    (_, value, _) => LinearProgressIndicator(
                      value: value,
                      minHeight: 8,
                      color: barColor,
                      backgroundColor: foreground.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      semanticsLabel: 'Time used',
                      semanticsValue: '${(sla.progress * 100).round()}%',
                    ),
              ),
            ],
            if (sla.level == SlaLevel.breached) ...[
              const SizedBox(height: 16),
              Text(
                'We missed our promise. How to escalate:',
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              for (final step in const [
                '1. Message us on this case. It goes straight to a senior '
                    'disputes officer.',
                '2. Call 1800-123-4567 (24x7) and quote your case number.',
                '3. No answer within 30 days? Complain to the RBI Banking '
                    'Ombudsman at cms.rbi.org.in.',
              ])
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(step, style: TextStyle(color: foreground)),
                ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onMessage,
                icon: const Icon(Icons.priority_high),
                label: const Text('Escalate by message'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// F7: provisional credit, and how it compares to the disputed amount.
class CreditCard extends StatelessWidget {
  const CreditCard({super.key, required this.disputeCase});

  final DisputeCase disputeCase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final credited = disputeCase.provisionalCreditPaise!;
    final compare = CaseRules.compareCredit(
      disputedPaise: disputeCase.disputedAmountPaise,
      creditedPaise: credited,
    );
    return Card(
      key: const Key('credit-card'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              disputeCase.status == CaseStatus.resolved
                  ? 'Credit (now permanent)'
                  : 'Provisional credit',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              Money.format(credited),
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            if (disputeCase.provisionalCreditAt != null)
              Text(
                'Credited on ${Dates.date(disputeCase.provisionalCreditAt!)}',
              ),
            const SizedBox(height: 12),
            StatusChip(
              label: compare.summary,
              icon:
                  compare.matches
                      ? Icons.check_circle_outline
                      : Icons.difference_outlined,
              tone: compare.matches ? Tone.success : Tone.warning,
            ),
            if (disputeCase.creditNote != null) ...[
              const SizedBox(height: 12),
              Text(disputeCase.creditNote!),
            ],
            if (disputeCase.creditConditions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Conditions',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              for (final c in disputeCase.creditConditions)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [const Text('•  '), Expanded(child: Text(c))],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The case's auditable trail, oldest at the top.
class TimelineView extends StatelessWidget {
  const TimelineView({super.key, required this.entries});

  final List<TimelineEntry> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        for (var i = 0; i < entries.length; i++)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 32,
                  child: Column(
                    children: [
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: theme.colorScheme.primaryContainer,
                        child: Icon(
                          switch (entries[i].actor) {
                            TimelineActor.customer => Icons.person,
                            TimelineActor.bank => Icons.account_balance,
                            TimelineActor.system => Icons.shield,
                            TimelineActor.network => Icons.hub,
                          },
                          size: 14,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      if (i < entries.length - 1)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: theme.colorScheme.outlineVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entries[i].title,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (entries[i].detail != null) Text(entries[i].detail!),
                        Text(
                          Dates.dateTime(entries[i].at),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
