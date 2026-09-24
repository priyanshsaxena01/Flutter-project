import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/disputes/state/dispute_flow_provider.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';
import 'package:fraud_shield/features/transactions/state/transactions_provider.dart';

/// Step 1 of the dispute flow: pick the transaction.
class PickTransactionScreen extends ConsumerWidget {
  const PickTransactionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txns = ref.watch(transactionsProvider);
    final now = ref.watch(clockProvider)();
    Future<void> refresh() =>
        refreshQuietly(ref.refresh(transactionsProvider.future));

    return Scaffold(
      appBar: AppBar(title: const Text('Which payment?')),
      body: txns.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(itemHeight: 72),
        error:
            (e, _) => RefreshableList(
              onRefresh: refresh,
              children: [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(transactionsProvider),
                ),
              ],
            ),
        data:
            (list) => RefreshableList(
              onRefresh: refresh,
              children: [
                if (list.isEmpty)
                  const EmptyView(
                    icon: Icons.receipt_long_outlined,
                    title: 'No payments',
                    message: 'There is nothing to dispute yet.',
                  ),
                for (final t in list)
                  _TxnTile(
                    txn: t,
                    now: now,
                    onTap: () => unawaited(_open(context, ref, t, now)),
                  ),
              ],
            ),
      ),
    );
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    BankTransaction txn,
    DateTime now,
  ) async {
    if (txn.caseId != null) {
      final view = await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('Already disputed'),
              content: const Text('There is already a case for this payment.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Close'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('View case'),
                ),
              ],
            ),
      );
      if (view == true && context.mounted) context.go('/cases/${txn.caseId}');
      return;
    }
    if (txn.declined) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'This payment was declined, so no money left your account.',
          ),
        ),
      );
      return;
    }
    if (!DisputeRules.isWithinWindow(txn.at, now)) {
      await showOutsideWindowDialog(context, txn, now);
      return;
    }
    ref.read(disputeFlowProvider.notifier).start(txn);
    await context.push('/disputes/new/${txn.id}');
  }
}

/// Edge case: "Dispute for a transaction older than 90 days: explain the
/// window and offer support contact".
Future<void> showOutsideWindowDialog(
  BuildContext context,
  BankTransaction txn,
  DateTime now,
) {
  final age = DisputeRules.ageInDays(txn.at, now);
  return showDialog<void>(
    context: context,
    builder:
        (context) => AlertDialog(
          icon: const Icon(Icons.event_busy_outlined),
          title: const Text('Too old to dispute in the app'),
          content: Text(
            'Disputes can be raised within ${DisputeRules.windowDays} days of a '
            'payment. This one is $age days old.\n\n'
            'Our support team can still help:\n'
            '• Call 1800-123-4567 (24x7)\n'
            '• Email disputes@fraudshield.example\n'
            'Mention ${txn.merchant}, ${Money.format(txn.amountPaise)} on '
            '${Dates.date(txn.at)}.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
  );
}

class _TxnTile extends StatelessWidget {
  const _TxnTile({required this.txn, required this.now, required this.onTap});

  final BankTransaction txn;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tooOld = !DisputeRules.isWithinWindow(txn.at, now);
    final chip =
        txn.caseId != null
            ? const StatusChip(
              label: 'Case open',
              icon: Icons.folder_open,
              tone: Tone.neutral,
            )
            : txn.declined
            ? const StatusChip(
              label: 'Declined',
              icon: Icons.block,
              tone: Tone.neutral,
            )
            : tooOld
            ? const StatusChip(
              label: 'Older than 90 days',
              icon: Icons.event_busy_outlined,
              tone: Tone.warning,
            )
            : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      title: Text(txn.merchant),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${txn.instrumentLabel} · ${Dates.date(txn.at)}'),
          if (chip != null) ...[const SizedBox(height: 4), chip],
        ],
      ),
      trailing: Text(
        Money.format(txn.amountPaise),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
  }
}
