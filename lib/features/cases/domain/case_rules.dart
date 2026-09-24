import 'package:fraud_shield/core/utils/money.dart';

/// Pure SLA and credit rules for the case tracker (F6, F7). Unit-tested.

enum SlaLevel { onTrack, dueSoon, breached, met }

class SlaStatus {
  const SlaStatus({
    required this.level,
    required this.remaining,
    required this.progress,
  });

  final SlaLevel level;

  /// Time left until the due date; negative once breached.
  final Duration remaining;

  /// 0.0 when the case opened, 1.0 at the due date.
  final double progress;

  /// Whole days left, rounded up: 1 h left counts as "1 day left".
  int get daysLeft {
    if (remaining.isNegative) return 0;
    final minutes = remaining.inMinutes;
    return (minutes + 24 * 60 - 1) ~/ (24 * 60);
  }

  /// Whole days past the due time, at least 1 once breached.
  int get daysOverdue {
    if (!remaining.isNegative) return 0;
    final days = -remaining.inDays;
    return days < 1 ? 1 : days;
  }

  String get label => switch (level) {
    SlaLevel.met => 'Decision made on time',
    SlaLevel.breached =>
      'Overdue by $daysOverdue ${daysOverdue == 1 ? 'day' : 'days'}',
    SlaLevel.onTrack || SlaLevel.dueSoon =>
      remaining.inHours < 24
          ? 'Less than 1 day left'
          : '$daysLeft ${daysLeft == 1 ? 'day' : 'days'} left',
  };
}

class CaseRules {
  const CaseRules._();

  /// Days the bank has to decide on provisional credit.
  static const slaDays = 10;

  /// "turns amber in the last 2 days"
  static const dueSoonWindow = Duration(days: 2);

  static SlaStatus sla({
    required DateTime openedAt,
    required DateTime dueAt,
    required DateTime now,
    required bool met,
  }) {
    final total = dueAt.difference(openedAt);
    final elapsed = now.difference(openedAt);
    final remaining = dueAt.difference(now);
    final progress =
        total.inSeconds <= 0
            ? 1.0
            : (elapsed.inSeconds / total.inSeconds).clamp(0.0, 1.0);

    final SlaLevel level;
    if (met) {
      level = SlaLevel.met;
    } else if (remaining.isNegative || remaining == Duration.zero) {
      level = SlaLevel.breached;
    } else if (remaining <= dueSoonWindow) {
      level = SlaLevel.dueSoon;
    } else {
      level = SlaLevel.onTrack;
    }
    return SlaStatus(level: level, remaining: remaining, progress: progress);
  }

  /// "Credit amount matches the disputed amount or shows the difference".
  static CreditComparison compareCredit({
    required int disputedPaise,
    required int creditedPaise,
  }) => CreditComparison(
    disputedPaise: disputedPaise,
    creditedPaise: creditedPaise,
  );
}

class CreditComparison {
  const CreditComparison({
    required this.disputedPaise,
    required this.creditedPaise,
  });

  final int disputedPaise;
  final int creditedPaise;

  int get differencePaise => disputedPaise - creditedPaise;

  bool get matches => differencePaise == 0;

  String get summary {
    if (matches) {
      return 'Matches the disputed amount of ${Money.format(disputedPaise)}';
    }
    if (differencePaise > 0) {
      return '${Money.format(differencePaise)} less than the disputed amount '
          'of ${Money.format(disputedPaise)}';
    }
    return '${Money.format(-differencePaise)} more than the disputed amount '
        'of ${Money.format(disputedPaise)}';
  }
}
