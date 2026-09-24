import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';

/// Pure business rules for the guided dispute flow (F4).
/// No Flutter imports, fully unit-tested per reason (Testability NFR).
/// The in-app server uses the same rules, so client and server agree.

enum QuestionType { yesNo, text, date, amount }

enum EvidenceRule { optional, required }

class DisputeQuestion {
  const DisputeQuestion({
    required this.id,
    required this.label,
    required this.type,
    this.required = true,
    this.hint,
    this.showWhen,
  });

  final String id;
  final String label;
  final QuestionType type;
  final bool required;
  final String? hint;

  /// Branching: the question only appears when another answer matches,
  /// written as (questionId, expectedValue).
  final (String, String)? showWhen;

  bool isVisible(Map<String, String> answers) {
    final condition = showWhen;
    if (condition == null) return true;
    return answers[condition.$1] == condition.$2;
  }
}

/// Facts about the transaction that some answers are checked against.
class DisputeContext {
  const DisputeContext({
    required this.txnAmountPaise,
    required this.txnAt,
    required this.today,
  });

  final int txnAmountPaise;
  final DateTime txnAt;
  final DateTime today;
}

class DisputeRules {
  const DisputeRules._();

  /// Disputes are accepted up to 90 days after the transaction.
  static const windowDays = 90;

  static const yes = 'yes';
  static const no = 'no';

  static const _questions = <DisputeReason, List<DisputeQuestion>>{
    DisputeReason.unauthorised: [
      DisputeQuestion(
        id: 'instrumentWithYou',
        label: 'Is your card or phone still with you?',
        type: QuestionType.yesNo,
      ),
      DisputeQuestion(
        id: 'sharedOtp',
        label: 'Did you share an OTP, PIN or password with anyone?',
        type: QuestionType.yesNo,
        hint: 'Answer honestly; it does not stop your claim.',
      ),
      DisputeQuestion(
        id: 'lastGenuineUse',
        label: 'Anything else we should know? (optional)',
        type: QuestionType.text,
        required: false,
        hint: 'For example, where you last used it yourself',
      ),
    ],
    DisputeReason.notReceived: [
      DisputeQuestion(
        id: 'itemDescription',
        label: 'What did you order?',
        type: QuestionType.text,
        hint: 'For example, "Blue denim jacket, size M"',
      ),
      DisputeQuestion(
        id: 'expectedBy',
        label: 'When was it supposed to arrive?',
        type: QuestionType.date,
      ),
      DisputeQuestion(
        id: 'contactedMerchant',
        label: 'Have you contacted the merchant?',
        type: QuestionType.yesNo,
      ),
      DisputeQuestion(
        id: 'merchantResponse',
        label: 'What did the merchant say?',
        type: QuestionType.text,
        showWhen: ('contactedMerchant', yes),
      ),
    ],
    DisputeReason.duplicate: [
      DisputeQuestion(
        id: 'sameOrder',
        label: 'Were both charges for the same purchase?',
        type: QuestionType.yesNo,
      ),
      DisputeQuestion(
        id: 'originalDate',
        label: 'Date of the first (correct) charge',
        type: QuestionType.date,
      ),
    ],
    DisputeReason.wrongAmount: [
      DisputeQuestion(
        id: 'agreedAmount',
        label: 'How much did you agree to pay?',
        type: QuestionType.amount,
        hint: 'In rupees, for example 980',
      ),
      DisputeQuestion(
        id: 'billAvailable',
        label: 'Do you have a bill or quote showing that amount?',
        type: QuestionType.yesNo,
      ),
    ],
  };

  /// Every question for a reason, including hidden branches.
  static List<DisputeQuestion> questionsFor(DisputeReason reason) =>
      _questions[reason]!;

  /// The questions to show right now, given the answers so far.
  static List<DisputeQuestion> visibleQuestions(
    DisputeReason reason,
    Map<String, String> answers,
  ) => [
    for (final q in questionsFor(reason))
      if (q.isVisible(answers)) q,
  ];

  /// "Evidence optional for unauthorised, required for not received".
  static EvidenceRule evidenceRuleFor(DisputeReason reason) => switch (reason) {
    DisputeReason.unauthorised => EvidenceRule.optional,
    DisputeReason.notReceived => EvidenceRule.required,
    DisputeReason.duplicate => EvidenceRule.optional,
    DisputeReason.wrongAmount => EvidenceRule.required,
  };

  static String evidenceHint(DisputeReason reason) => switch (reason) {
    DisputeReason.unauthorised =>
      'Optional. Add anything that helps, such as a screenshot of an OTP '
          'message you did not request.',
    DisputeReason.notReceived =>
      'Required. Add the order confirmation, and chats or emails with the '
          'merchant.',
    DisputeReason.duplicate =>
      'Optional. A statement or receipt showing both charges helps.',
    DisputeReason.wrongAmount =>
      'Required. Add the bill, quote or receipt showing the agreed amount.',
  };

  /// Only answers to visible questions are kept, trimmed.
  static Map<String, String> cleanAnswers(
    DisputeReason reason,
    Map<String, String> answers,
  ) => {
    for (final q in visibleQuestions(reason, answers))
      if ((answers[q.id] ?? '').trim().isNotEmpty) q.id: answers[q.id]!.trim(),
  };

  /// Returns an error for one answer, or null when it is fine.
  static String? validateAnswer(
    DisputeReason reason,
    DisputeQuestion q,
    String? rawValue,
    DisputeContext ctx,
  ) {
    final value = rawValue?.trim() ?? '';
    if (value.isEmpty) {
      if (!q.required) return null;
      return q.type == QuestionType.yesNo
          ? 'Please choose Yes or No'
          : 'Please answer this question';
    }

    switch (q.type) {
      case QuestionType.yesNo:
        if (value != yes && value != no) return 'Please choose Yes or No';
      case QuestionType.text:
        if (q.required && value.length < 3) return 'Please add a little more';
        if (value.length > 500) return 'Keep it under 500 characters';
      case QuestionType.date:
        final date = Dates.parseIsoDate(value);
        if (date == null) return 'Pick a valid date';
        if (date.isAfter(Dates.dayOf(ctx.today))) {
          return q.id == 'expectedBy'
              ? 'The delivery date has not passed yet. Please wait until '
                  'it has before raising a dispute.'
              : 'The date cannot be in the future';
        }
      case QuestionType.amount:
        final paise = Money.parseRupees(value);
        if (paise == null || paise <= 0) return 'Enter a valid amount';
        if (paise >= ctx.txnAmountPaise) {
          return 'Enter an amount less than '
              '${Money.format(ctx.txnAmountPaise)} (the amount charged)';
        }
    }

    // Reason-specific checks.
    if (reason == DisputeReason.duplicate &&
        q.id == 'sameOrder' &&
        value == no) {
      return 'If these were different purchases, this is not a duplicate '
          'charge. Please choose another reason.';
    }
    if (reason == DisputeReason.duplicate && q.id == 'originalDate') {
      final date = Dates.parseIsoDate(value)!;
      if (date.isAfter(Dates.dayOf(ctx.txnAt))) {
        return 'The first charge must be on or before '
            '${Dates.date(ctx.txnAt)}';
      }
    }
    if (reason == DisputeReason.notReceived && q.id == 'expectedBy') {
      final date = Dates.parseIsoDate(value)!;
      if (date.isBefore(Dates.dayOf(ctx.txnAt))) {
        return 'Delivery cannot be due before you paid on '
            '${Dates.date(ctx.txnAt)}';
      }
    }
    return null;
  }

  /// Validates every visible question. Empty map = all good.
  static Map<String, String> validate(
    DisputeReason reason,
    Map<String, String> answers,
    DisputeContext ctx,
  ) {
    final errors = <String, String>{};
    for (final q in visibleQuestions(reason, answers)) {
      final error = validateAnswer(reason, q, answers[q.id], ctx);
      if (error != null) errors[q.id] = error;
    }
    return errors;
  }

  /// The amount under dispute. For a wrong amount it is only the extra
  /// charged; otherwise the whole transaction.
  static int disputedAmountPaise(
    DisputeReason reason,
    int txnAmountPaise,
    Map<String, String> answers,
  ) {
    if (reason == DisputeReason.wrongAmount) {
      final agreed = Money.parseRupees(answers['agreedAmount'] ?? '');
      if (agreed != null && agreed > 0 && agreed < txnAmountPaise) {
        return txnAmountPaise - agreed;
      }
    }
    return txnAmountPaise;
  }

  static int ageInDays(DateTime txnAt, DateTime now) =>
      Dates.dayOf(now).difference(Dates.dayOf(txnAt)).inDays;

  static bool isWithinWindow(DateTime txnAt, DateTime now) =>
      ageInDays(txnAt, now) <= windowDays;
}
