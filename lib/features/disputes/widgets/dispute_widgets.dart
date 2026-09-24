import 'package:flutter/material.dart';

import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/transactions/domain/bank_transaction.dart';

IconData reasonIcon(DisputeReason reason) => switch (reason) {
  DisputeReason.unauthorised => Icons.person_off_outlined,
  DisputeReason.notReceived => Icons.local_shipping_outlined,
  DisputeReason.duplicate => Icons.copy_all_outlined,
  DisputeReason.wrongAmount => Icons.price_change_outlined,
};

/// An answer as the customer would read it.
String displayAnswer(DisputeQuestion q, String value) => switch (q.type) {
  QuestionType.yesNo => value == DisputeRules.yes ? 'Yes' : 'No',
  QuestionType.date =>
    Dates.parseIsoDate(value) == null
        ? value
        : Dates.date(Dates.parseIsoDate(value)!),
  QuestionType.amount =>
    Money.parseRupees(value) == null
        ? value
        : Money.format(Money.parseRupees(value)!),
  QuestionType.text => value,
};

class TransactionSummary extends StatelessWidget {
  const TransactionSummary({super.key, required this.txn});

  final BankTransaction txn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.receipt_long_outlined, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(txn.merchant, style: theme.textTheme.titleMedium),
                  Text('${txn.instrumentLabel} · ${Dates.dateTime(txn.at)}'),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              Money.format(txn.amountPaise),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One question in the dispute form. The input changes with the type.
class QuestionField extends StatelessWidget {
  const QuestionField({
    super.key,
    required this.question,
    required this.value,
    required this.error,
    required this.onChanged,
    required this.firstDate,
    required this.lastDate,
  });

  final DisputeQuestion question;
  final String? value;
  final String? error;
  final ValueChanged<String> onChanged;
  final DateTime firstDate;
  final DateTime lastDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = question;
    switch (q.type) {
      case QuestionType.yesNo:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.label, style: theme.textTheme.bodyLarge),
            if (q.hint != null) Text(q.hint!, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: Key('q-${q.id}'),
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: DisputeRules.yes, label: Text('Yes')),
                ButtonSegment(value: DisputeRules.no, label: Text('No')),
              ],
              selected: {if (value != null && value!.isNotEmpty) value!},
              onSelectionChanged: (s) {
                if (s.isNotEmpty) onChanged(s.first);
              },
            ),
            if (error != null) _ErrorText(error!),
          ],
        );
      case QuestionType.text:
      case QuestionType.amount:
        final amount = q.type == QuestionType.amount;
        return TextFormField(
          key: Key('q-${q.id}'),
          initialValue: value,
          onChanged: onChanged,
          minLines: amount ? 1 : 1,
          maxLines: amount ? 1 : 3,
          keyboardType:
              amount
                  ? const TextInputType.numberWithOptions(decimal: true)
                  : TextInputType.multiline,
          decoration: InputDecoration(
            labelText: q.label,
            helperText: q.hint,
            helperMaxLines: 2,
            errorText: error,
            errorMaxLines: 3,
            prefixText: amount ? '₹ ' : null,
            border: const OutlineInputBorder(),
          ),
        );
      case QuestionType.date:
        final date = Dates.parseIsoDate(value);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(q.label, style: theme.textTheme.bodyLarge),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: Key('q-${q.id}'),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: date ?? lastDate,
                  firstDate: firstDate,
                  lastDate: lastDate,
                  helpText: q.label,
                );
                if (picked != null) onChanged(Dates.isoDate(picked));
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(date == null ? 'Pick a date' : Dates.date(date)),
            ),
            if (error != null) _ErrorText(error!),
          ],
        );
    }
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.error),
    ),
  );
}
