import 'package:flutter_test/flutter_test.dart';

import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';

void main() {
  final today = DateTime(2026, 9, 24, 12);
  final ctx = DisputeContext(
    txnAmountPaise: 118000, // ₹1,180
    txnAt: DateTime(2026, 9, 10, 18),
    today: today,
  );

  List<String> ids(DisputeReason r, [Map<String, String> a = const {}]) =>
      DisputeRules.visibleQuestions(r, a).map((q) => q.id).toList();

  group('questions change by reason', () {
    test('each reason has its own questions', () {
      expect(ids(DisputeReason.unauthorised), [
        'instrumentWithYou',
        'sharedOtp',
        'lastGenuineUse',
      ]);
      expect(ids(DisputeReason.notReceived), [
        'itemDescription',
        'expectedBy',
        'contactedMerchant',
      ]);
      expect(ids(DisputeReason.duplicate), ['sameOrder', 'originalDate']);
      expect(ids(DisputeReason.wrongAmount), ['agreedAmount', 'billAvailable']);
    });

    test('not received: merchant response appears only after "yes"', () {
      expect(
        ids(DisputeReason.notReceived, {'contactedMerchant': 'no'}),
        isNot(contains('merchantResponse')),
      );
      expect(
        ids(DisputeReason.notReceived, {'contactedMerchant': 'yes'}),
        contains('merchantResponse'),
      );
    });

    test('hidden answers are dropped', () {
      final clean = DisputeRules.cleanAnswers(DisputeReason.notReceived, {
        'itemDescription': '  Shoes ',
        'contactedMerchant': 'no',
        'merchantResponse': 'left over from before',
      });
      expect(clean, {'itemDescription': 'Shoes', 'contactedMerchant': 'no'});
    });
  });

  group('evidence rule by reason', () {
    test('optional for unauthorised, required for not received', () {
      expect(
        DisputeRules.evidenceRuleFor(DisputeReason.unauthorised),
        EvidenceRule.optional,
      );
      expect(
        DisputeRules.evidenceRuleFor(DisputeReason.notReceived),
        EvidenceRule.required,
      );
      expect(
        DisputeRules.evidenceRuleFor(DisputeReason.duplicate),
        EvidenceRule.optional,
      );
      expect(
        DisputeRules.evidenceRuleFor(DisputeReason.wrongAmount),
        EvidenceRule.required,
      );
    });
  });

  group('validation', () {
    test('unauthorised needs both yes/no answers, not the optional text', () {
      final errors = DisputeRules.validate(DisputeReason.unauthorised, {}, ctx);
      expect(errors.keys, containsAll(['instrumentWithYou', 'sharedOtp']));
      expect(errors.containsKey('lastGenuineUse'), isFalse);

      final ok = DisputeRules.validate(DisputeReason.unauthorised, {
        'instrumentWithYou': 'yes',
        'sharedOtp': 'no',
      }, ctx);
      expect(ok, isEmpty);
    });

    test('not received: delivery date must have passed', () {
      final errors = DisputeRules.validate(DisputeReason.notReceived, {
        'itemDescription': 'Jacket',
        'expectedBy': '2026-10-01',
        'contactedMerchant': 'no',
      }, ctx);
      expect(errors['expectedBy'], contains('has not passed yet'));
    });

    test('not received: delivery cannot be before payment', () {
      final errors = DisputeRules.validate(DisputeReason.notReceived, {
        'itemDescription': 'Jacket',
        'expectedBy': '2026-09-01',
        'contactedMerchant': 'no',
      }, ctx);
      expect(errors['expectedBy'], contains('before you paid'));
    });

    test('not received: merchant response required after "yes"', () {
      final errors = DisputeRules.validate(DisputeReason.notReceived, {
        'itemDescription': 'Jacket',
        'expectedBy': '2026-09-20',
        'contactedMerchant': 'yes',
      }, ctx);
      expect(errors.keys, ['merchantResponse']);
    });

    test('duplicate: "no" means it is not a duplicate', () {
      final errors = DisputeRules.validate(DisputeReason.duplicate, {
        'sameOrder': 'no',
        'originalDate': '2026-09-10',
      }, ctx);
      expect(errors['sameOrder'], contains('not a duplicate'));
    });

    test('duplicate: first charge cannot be after this one', () {
      final errors = DisputeRules.validate(DisputeReason.duplicate, {
        'sameOrder': 'yes',
        'originalDate': '2026-09-12',
      }, ctx);
      expect(errors['originalDate'], contains('on or before'));
    });

    test('wrong amount: agreed amount must be below the charge', () {
      expect(
        DisputeRules.validate(DisputeReason.wrongAmount, {
          'agreedAmount': '1180',
          'billAvailable': 'yes',
        }, ctx)['agreedAmount'],
        contains('less than ₹1,180.00'),
      );
      expect(
        DisputeRules.validate(DisputeReason.wrongAmount, {
          'agreedAmount': 'abc',
          'billAvailable': 'yes',
        }, ctx)['agreedAmount'],
        'Enter a valid amount',
      );
      expect(
        DisputeRules.validate(DisputeReason.wrongAmount, {
          'agreedAmount': '980',
          'billAvailable': 'yes',
        }, ctx),
        isEmpty,
      );
    });

    test('dates must be real dates', () {
      final errors = DisputeRules.validate(DisputeReason.duplicate, {
        'sameOrder': 'yes',
        'originalDate': '2026-02-31',
      }, ctx);
      expect(errors['originalDate'], 'Pick a valid date');
    });
  });

  group('amount and window', () {
    test('wrong amount disputes only the difference', () {
      expect(
        DisputeRules.disputedAmountPaise(DisputeReason.wrongAmount, 118000, {
          'agreedAmount': '980',
        }),
        20000,
      );
      expect(
        DisputeRules.disputedAmountPaise(
          DisputeReason.unauthorised,
          118000,
          {},
        ),
        118000,
      );
    });

    test('90-day window, counted in whole days', () {
      final now = DateTime(2026, 9, 24, 9);
      expect(
        DisputeRules.isWithinWindow(
          now.subtract(const Duration(days: 90)),
          now,
        ),
        isTrue,
      );
      expect(
        DisputeRules.isWithinWindow(
          now.subtract(const Duration(days: 91)),
          now,
        ),
        isFalse,
      );
      expect(
        DisputeRules.ageInDays(now.subtract(const Duration(days: 120)), now),
        120,
      );
    });
  });
}
