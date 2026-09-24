import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/idempotency.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/data/dispute_repository.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';

/// Immutable state of the guided dispute flow (F4):
/// transaction -> reason -> questions -> evidence -> review.
class DisputeFlowState {
  const DisputeFlowState({
    required this.createKey,
    required this.submitKey,
    this.txn,
    this.reason,
    this.answers = const {},
    this.disputeId,
    this.disputedAmountPaise,
    this.saving = false,
    this.error,
    this.fieldErrors = const {},
    this.existingCaseId,
  });

  final BankTransaction? txn;
  final DisputeReason? reason;
  final Map<String, String> answers;

  /// Set once the draft exists on the server.
  final String? disputeId;
  final int? disputedAmountPaise;

  /// One key per flow for creating the draft, one for submitting (B6).
  final String createKey;
  final String submitKey;

  final bool saving;
  final String? error;
  final Map<String, String> fieldErrors;

  /// Set when the server says a case already exists for this payment.
  final String? existingCaseId;

  DisputeFlowState copyWith({
    DisputeReason? reason,
    Map<String, String>? answers,
    String? disputeId,
    int? disputedAmountPaise,
    bool? saving,
    String? error,
    bool clearError = false,
    Map<String, String>? fieldErrors,
    String? existingCaseId,
  }) {
    return DisputeFlowState(
      createKey: createKey,
      submitKey: submitKey,
      txn: txn,
      reason: reason ?? this.reason,
      answers: answers ?? this.answers,
      disputeId: disputeId ?? this.disputeId,
      disputedAmountPaise: disputedAmountPaise ?? this.disputedAmountPaise,
      saving: saving ?? this.saving,
      error: clearError ? null : (error ?? this.error),
      fieldErrors: fieldErrors ?? this.fieldErrors,
      existingCaseId: existingCaseId ?? this.existingCaseId,
    );
  }
}

class DisputeFlowNotifier extends Notifier<DisputeFlowState> {
  @override
  DisputeFlowState build() => _fresh(null);

  static DisputeFlowState _fresh(BankTransaction? txn) => DisputeFlowState(
    txn: txn,
    createKey: newIdempotencyKey(),
    submitKey: newIdempotencyKey(),
  );

  DisputeContext contextFor(BankTransaction txn) => DisputeContext(
    txnAmountPaise: txn.amountPaise,
    txnAt: txn.at,
    today: ref.read(clockProvider)(),
  );

  /// Starts a new flow for [txn], unless one is already open for it.
  void start(BankTransaction txn) {
    if (state.txn?.id == txn.id) return;
    state = _fresh(txn);
  }

  void reset() => state = _fresh(null);

  /// Questions change by reason, so changing it clears the answers.
  void chooseReason(DisputeReason reason) {
    if (state.reason == reason) return;
    state = state.copyWith(
      reason: reason,
      answers: const {},
      fieldErrors: const {},
      clearError: true,
    );
  }

  void answer(String questionId, String value) {
    state = state.copyWith(
      answers: {...state.answers, questionId: value},
      fieldErrors: {...state.fieldErrors}..remove(questionId),
      clearError: true,
    );
  }

  /// Validates, then creates (or updates) the draft on the server.
  /// Returns true when the flow can move on to evidence.
  Future<bool> saveDraft() async {
    final txn = state.txn;
    final reason = state.reason;
    if (txn == null || reason == null) {
      state = state.copyWith(error: 'Choose what went wrong first.');
      return false;
    }
    final errors = DisputeRules.validate(
      reason,
      state.answers,
      contextFor(txn),
    );
    if (errors.isNotEmpty) {
      state = state.copyWith(
        fieldErrors: errors,
        error: 'Please check the highlighted answers.',
      );
      return false;
    }

    state = state.copyWith(saving: true, clearError: true);
    final repo = ref.read(disputeRepositoryProvider);
    final answers = DisputeRules.cleanAnswers(reason, state.answers);
    try {
      final existingId = state.disputeId;
      final dispute =
          existingId == null
              ? await repo.create(
                txnId: txn.id,
                reason: reason,
                answers: answers,
                idempotencyKey: state.createKey,
              )
              : await repo.update(existingId, reason: reason, answers: answers);
      state = state.copyWith(
        disputeId: dispute.id,
        disputedAmountPaise: dispute.disputedAmountPaise,
        saving: false,
      );
      return true;
    } on ValidationError catch (e) {
      state = state.copyWith(
        saving: false,
        error: e.message,
        fieldErrors: e.fieldErrors,
      );
    } on ConflictError catch (e) {
      state = state.copyWith(
        saving: false,
        error: e.message,
        existingCaseId: e.details['caseId'] as String?,
      );
    } on BankError catch (e) {
      state = state.copyWith(saving: false, error: e.message);
    }
    return false;
  }

  /// Submits and returns the new case, or null on error (shown in state).
  Future<DisputeCase?> submit({required int evidenceCount}) async {
    final reason = state.reason;
    final disputeId = state.disputeId;
    if (reason == null || disputeId == null || state.saving) return null;
    if (DisputeRules.evidenceRuleFor(reason) == EvidenceRule.required &&
        evidenceCount == 0) {
      state = state.copyWith(
        error: 'Please add at least one file as evidence for this dispute.',
      );
      return null;
    }

    state = state.copyWith(saving: true, clearError: true);
    try {
      final disputeCase = await ref
          .read(disputeRepositoryProvider)
          .submit(disputeId, idempotencyKey: state.submitKey);
      ref.invalidate(casesProvider);
      ref.invalidate(transactionsProvider);
      state = state.copyWith(saving: false);
      return disputeCase;
    } on ConflictError catch (e) {
      state = state.copyWith(
        saving: false,
        error: e.message,
        existingCaseId: e.details['caseId'] as String?,
      );
    } on BankError catch (e) {
      state = state.copyWith(saving: false, error: e.message);
    }
    return null;
  }
}

final disputeFlowProvider =
    NotifierProvider<DisputeFlowNotifier, DisputeFlowState>(
      DisputeFlowNotifier.new,
    );
