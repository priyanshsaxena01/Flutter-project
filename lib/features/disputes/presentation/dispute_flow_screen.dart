import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/motion/motion.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/disputes/presentation/pick_transaction_screen.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/disputes/widgets/dispute_widgets.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';

/// /disputes/new/:txnId — reason, then questions that change by reason.
class DisputeFlowScreen extends ConsumerWidget {
  const DisputeFlowScreen({super.key, required this.txnId});

  final String txnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flow = ref.watch(disputeFlowProvider);
    final txn = flow.txn;
    if (txn != null && txn.id == txnId) return _DisputeForm(txn: txn);

    // Opened by a deep link: load the payment, check it, start the flow.
    final loaded = ref.watch(transactionProvider(txnId));
    final now = ref.watch(clockProvider)();
    return Scaffold(
      appBar: AppBar(title: const Text('Raise a dispute')),
      body: loaded.when(
        loading: () => const SkeletonList(itemCount: 3),
        error:
            (e, _) => ErrorView(
              error: e,
              onRetry: () => ref.invalidate(transactionsProvider),
            ),
        data: (t) {
          if (t == null) {
            return const EmptyView(
              icon: Icons.search_off,
              title: 'Payment not found',
              message: 'It may be older than the payments we can show.',
            );
          }
          if (t.caseId != null) {
            return EmptyView(
              icon: Icons.folder_open,
              title: 'Already disputed',
              message: 'There is already a case for this payment.',
              actionLabel: 'View case',
              onAction: () => context.go('/cases/${t.caseId}'),
            );
          }
          if (!DisputeRules.isWithinWindow(t.at, now)) {
            return EmptyView(
              icon: Icons.event_busy_outlined,
              title: 'Too old to dispute in the app',
              message:
                  'Disputes can be raised within ${DisputeRules.windowDays} '
                  'days. Our support team can still help.',
              actionLabel: 'How to contact support',
              onAction:
                  () => unawaited(showOutsideWindowDialog(context, t, now)),
            );
          }
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => ref.read(disputeFlowProvider.notifier).start(t),
          );
          return const SkeletonList(itemCount: 3);
        },
      ),
    );
  }
}

class _DisputeForm extends ConsumerWidget {
  const _DisputeForm({required this.txn});

  final BankTransaction txn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final flow = ref.watch(disputeFlowProvider);
    final notifier = ref.read(disputeFlowProvider.notifier);
    final reason = flow.reason;
    final now = ref.watch(clockProvider)();

    Future<void> next() async {
      final ok = await notifier.saveDraft();
      if (ok && context.mounted) await context.push('/disputes/new/evidence');
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Raise a dispute')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Step 1 of 3 · What happened',
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          TransactionSummary(txn: txn),
          const SectionTitle('What went wrong?'),
          for (final r in DisputeReason.values)
            Semantics(
              selected: reason == r,
              button: true,
              child: Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side:
                      reason == r
                          ? BorderSide(
                            color: theme.colorScheme.primary,
                            width: 2,
                          )
                          : BorderSide.none,
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  key: Key('reason-${r.api}'),
                  leading: Icon(reasonIcon(r)),
                  title: Text(r.label),
                  subtitle: Text(r.description),
                  trailing:
                      reason == r
                          ? Icon(
                            Icons.check_circle,
                            color: theme.colorScheme.primary,
                          )
                          : null,
                  onTap: () => notifier.chooseReason(r),
                ),
              ),
            ),
          if (reason != null) ...[
            const SectionTitle('A few questions'),
            AnimatedSwitcher(
              duration: Motion.duration(context, Motion.short),
              child: Column(
                key: ValueKey(reason),
                children: [
                  for (final q in DisputeRules.visibleQuestions(
                    reason,
                    flow.answers,
                  ))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: QuestionField(
                        key: ValueKey('${reason.api}-${q.id}'),
                        question: q,
                        value: flow.answers[q.id],
                        error: flow.fieldErrors[q.id],
                        onChanged: (v) => notifier.answer(q.id, v),
                        firstDate: txn.at.subtract(const Duration(days: 365)),
                        // A future delivery date is allowed so the form can
                        // explain "wait until it has passed".
                        lastDate:
                            q.id == 'expectedBy'
                                ? now.add(const Duration(days: 60))
                                : now,
                      ),
                    ),
                ],
              ),
            ),
            InlineMessage(
              tone: Tone.neutral,
              icon: Icons.attach_file,
              title:
                  DisputeRules.evidenceRuleFor(reason) == EvidenceRule.required
                      ? 'Evidence needed next'
                      : 'Evidence optional',
              message: DisputeRules.evidenceHint(reason),
            ),
          ],
          if (flow.error != null) ...[
            const SizedBox(height: 12),
            InlineMessage(message: flow.error!),
            if (flow.existingCaseId != null)
              TextButton(
                onPressed: () => context.go('/cases/${flow.existingCaseId}'),
                child: const Text('View the existing case'),
              ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            key: const Key('flow-continue'),
            onPressed:
                reason == null || flow.saving ? null : () => unawaited(next()),
            child:
                flow.saving
                    ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Continue'),
          ),
        ],
      ),
    );
  }
}
