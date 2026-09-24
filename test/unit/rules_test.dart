import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/core/realtime/backoff.dart';
import 'package:fraud_shield/core/realtime/sse_parser.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/utils/validators.dart';
import 'package:fraud_shield/features/alerts/domain/alert.dart';
import 'package:fraud_shield/features/cases/domain/case_rules.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';
import 'package:fraud_shield/mock_server/fraud_scoring.dart';

Alert _alert(String id, int seq, AlertStatus status) => Alert(
  id: id,
  seq: seq,
  txnId: 't',
  instrumentId: 'i',
  instrumentLabel: 'Card',
  merchant: 'M',
  amountPaise: 100,
  location: 'Pune',
  at: DateTime(2026),
  riskReason: '',
  riskLevel: RiskLevel.high,
  status: status,
);

void main() {
  group('Money', () {
    test('Indian grouping, always paise', () {
      expect(Money.format(499900), '₹4,999.00');
      expect(Money.format(12345678), '₹1,23,456.78');
      expect(Money.format(5), '₹0.05');
      expect(Money.format(-20000), '-₹200.00');
      expect(Money.compact(499900), '₹4,999');
      expect(Money.compact(499950), '₹4,999.50');
    });

    test('parses rupees into paise', () {
      expect(Money.parseRupees('980'), 98000);
      expect(Money.parseRupees('1,234.5'), 123450);
      expect(Money.parseRupees('₹ 12.05'), 1205);
      expect(Money.parseRupees('12.345'), isNull);
      expect(Money.parseRupees('abc'), isNull);
      expect(Money.parseRupees(''), isNull);
    });
  });

  group('Dates and validators', () {
    test('iso dates round-trip and reject rollovers', () {
      expect(Dates.isoDate(DateTime(2026, 3, 7)), '2026-03-07');
      expect(Dates.parseIsoDate('2026-03-07'), DateTime(2026, 3, 7));
      expect(Dates.parseIsoDate('2026-02-30'), isNull);
      expect(Dates.parseIsoDate('7/3/2026'), isNull);
    });

    test('time ago', () {
      final now = DateTime(2026, 9, 24, 12);
      expect(
        Dates.timeAgo(now.subtract(const Duration(seconds: 10)), now),
        'just now',
      );
      expect(
        Dates.timeAgo(now.subtract(const Duration(minutes: 5)), now),
        '5 min ago',
      );
      expect(
        Dates.timeAgo(now.subtract(const Duration(hours: 3)), now),
        '3 h ago',
      );
      expect(
        Dates.timeAgo(now.subtract(const Duration(hours: 30)), now),
        'yesterday',
      );
    });

    test('login validators', () {
      expect(Validators.customerId(''), isNotNull);
      expect(Validators.customerId('test_custom'), isNull);
      expect(Validators.customerId('TEST CUSTOM'), isNotNull);
      expect(Validators.customerId('ab'), isNotNull);
      expect(Validators.pin('12a4'), isNotNull);
      expect(Validators.pin('123'), isNotNull);
      expect(Validators.pin('0123456789'), isNull);
      expect(Validators.pin('01234567890'), isNotNull);
      expect(Validators.message('   '), isNotNull);
    });
  });

  group('Evidence rules (max 5 files, 5 MB each)', () {
    test('accepts images and PDF up to 5 MB', () {
      expect(
        EvidenceRules.checkFile(
          name: 'a.pdf',
          sizeBytes: 5 * 1024 * 1024,
          mimeType: 'application/pdf',
          filesSoFar: 4,
        ),
        isNull,
      );
    });

    test('refuses the 6th file, big files and videos', () {
      expect(
        EvidenceRules.checkFile(
          name: 'a.png',
          sizeBytes: 10,
          mimeType: 'image/png',
          filesSoFar: 5,
        ),
        contains('up to 5 files'),
      );
      expect(
        EvidenceRules.checkFile(
          name: 'big.jpg',
          sizeBytes: 5 * 1024 * 1024 + 1,
          mimeType: 'image/jpeg',
          filesSoFar: 0,
        ),
        contains('5 MB or smaller'),
      );
      expect(
        EvidenceRules.checkFile(
          name: 'v.mp4',
          sizeBytes: 10,
          mimeType: 'video/mp4',
          filesSoFar: 0,
        ),
        contains('only photos'),
      );
    });

    test('sizes and types', () {
      expect(EvidenceRules.formatSize(1536), '1.5 KB');
      expect(EvidenceRules.formatSize(5 * 1024 * 1024), '5.0 MB');
      expect(EvidenceRules.mimeTypeForName('x.JPG'), 'image/jpeg');
    });
  });

  group('SLA timer', () {
    final opened = DateTime(2026, 9, 14, 12);
    final due = opened.add(const Duration(days: 10));

    SlaStatus at(DateTime now, {bool met = false}) =>
        CaseRules.sla(openedAt: opened, dueAt: due, now: now, met: met);

    test('shows days remaining', () {
      final s = at(due.subtract(const Duration(days: 6)));
      expect(s.level, SlaLevel.onTrack);
      expect(s.daysLeft, 6);
      expect(s.label, '6 days left');
      expect(s.progress, closeTo(0.4, 0.001));
    });

    test('turns amber in the last 2 days', () {
      expect(at(due.subtract(const Duration(days: 3))).level, SlaLevel.onTrack);
      expect(at(due.subtract(const Duration(days: 2))).level, SlaLevel.dueSoon);
      final s = at(due.subtract(const Duration(hours: 36)));
      expect(s.level, SlaLevel.dueSoon);
      expect(s.label, '2 days left');
      expect(
        at(due.subtract(const Duration(hours: 5))).label,
        'Less than 1 day left',
      );
    });

    test('breached after the due time', () {
      final s = at(due.add(const Duration(days: 3)));
      expect(s.level, SlaLevel.breached);
      expect(s.label, 'Overdue by 3 days');
      expect(s.progress, 1.0);
    });

    test('met once credit is given', () {
      expect(
        at(due.add(const Duration(days: 3)), met: true).level,
        SlaLevel.met,
      );
    });
  });

  group('Provisional credit', () {
    test('matches the disputed amount', () {
      final c = CaseRules.compareCredit(
        disputedPaise: 20000,
        creditedPaise: 20000,
      );
      expect(c.matches, isTrue);
      expect(c.summary, 'Matches the disputed amount of ₹200.00');
    });

    test('shows the difference', () {
      final c = CaseRules.compareCredit(
        disputedPaise: 1250000,
        creditedPaise: 1000000,
      );
      expect(c.differencePaise, 250000);
      expect(
        c.summary,
        '₹2,500.00 less than the disputed amount of ₹12,500.00',
      );
    });
  });

  group('Live stream helpers', () {
    test('backoff doubles and caps', () {
      const b = Backoff();
      expect(b.delayFor(1), const Duration(seconds: 1));
      expect(b.delayFor(2), const Duration(seconds: 2));
      expect(b.delayFor(4), const Duration(seconds: 8));
      expect(b.delayFor(10), const Duration(seconds: 30));
      expect(b.delayFor(1, random: 0), const Duration(milliseconds: 800));
      expect(b.delayFor(1, random: 1), const Duration(milliseconds: 1200));
    });

    test('SSE parser handles ids, events, multi-line data and heartbeats', () {
      final p = SseParser();
      expect(p.addLine(': ping'), isNull);
      expect(p.addLine(''), isNull);
      p
        ..addLine('id: 7')
        ..addLine('event: alert')
        ..addLine('data: {"a":1,')
        ..addLine('data: "b":2}');
      final m = p.addLine('')!;
      expect(m.id, '7');
      expect(m.event, 'alert');
      expect(m.data, '{"a":1,\n"b":2}');
      p.addLine('data: x');
      expect(p.addLine('')!.event, 'message');
    });
  });

  group('Alert list rules', () {
    test('merge keeps one copy per id, newest first', () {
      final merged = AlertRules.merge(
        [
          _alert('a', 1, AlertStatus.pending),
          _alert('b', 2, AlertStatus.pending),
        ],
        [
          _alert('a', 1, AlertStatus.confirmed),
          _alert('c', 3, AlertStatus.pending),
        ],
      );
      expect(merged.map((a) => a.id), ['c', 'b', 'a']);
      expect(merged.last.status, AlertStatus.confirmed);
    });

    test('unread counts only unopened alerts that need attention', () {
      final alerts = [
        _alert('a', 1, AlertStatus.pending),
        _alert('b', 2, AlertStatus.pending),
        _alert('c', 3, AlertStatus.confirmed),
        _alert('d', 4, AlertStatus.instrumentBlocked),
      ];
      expect(AlertRules.unreadCount(alerts, {}), 3);
      expect(AlertRules.unreadCount(alerts, {'a', 'd'}), 1);
    });
  });

  group('Fraud scoring', () {
    const profile = CustomerProfile(
      homeCity: 'Pune',
      homeCountry: 'IN',
      averageSpendPaise: 180000,
    );

    test('foreign, large, high-risk payments are HIGH risk', () {
      final r = FraudScorer.assess(
        const PaymentCandidate(
          merchant: 'Crypto Xchange',
          category: 'crypto',
          amountPaise: 2450000,
          city: 'Singapore',
          country: 'SG',
          instrumentLabel: 'Credit card',
          knownMerchant: false,
        ),
        profile,
      );
      expect(r.level, 'HIGH');
      expect(r.summary, contains('Unusual location: Singapore, SG'));
      expect(r.raisesAlert, isTrue);
    });

    test('a normal local payment raises no alert', () {
      final r = FraudScorer.assess(
        const PaymentCandidate(
          merchant: 'Chai Point',
          category: 'food',
          amountPaise: 12000,
          city: 'Pune',
          country: 'IN',
          instrumentLabel: 'UPI',
          knownMerchant: true,
        ),
        profile,
      );
      expect(r.level, 'LOW');
      expect(r.raisesAlert, isFalse);
    });
  });
}
