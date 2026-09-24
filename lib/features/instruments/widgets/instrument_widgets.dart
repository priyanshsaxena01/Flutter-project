import 'package:flutter/material.dart';

import 'package:fraud_shield/app/theme.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';

IconData instrumentIcon(InstrumentType type) => switch (type) {
  InstrumentType.card => Icons.credit_card,
  InstrumentType.upi => Icons.qr_code_2,
  InstrumentType.netBanking => Icons.language,
};

class InstrumentStatusChip extends StatelessWidget {
  const InstrumentStatusChip({super.key, required this.instrument});

  final Instrument instrument;

  @override
  Widget build(BuildContext context) =>
      instrument.blocked
          ? const StatusChip(
            label: 'Blocked',
            icon: Icons.lock,
            tone: Tone.danger,
          )
          : const StatusChip(
            label: 'Active',
            icon: Icons.check_circle_outline,
            tone: Tone.success,
          );
}

/// One instrument with its state and an action button.
class InstrumentCard extends StatelessWidget {
  const InstrumentCard({
    super.key,
    required this.instrument,
    required this.busy,
    required this.highlighted,
    required this.onBlock,
    required this.onUnblock,
  });

  final Instrument instrument;
  final bool busy;
  final bool highlighted;
  final VoidCallback onBlock;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final i = instrument;
    return Card(
      shape:
          highlighted
              ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: theme.colorScheme.primary, width: 2),
              )
              : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(instrumentIcon(i.type), size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(i.label, style: theme.textTheme.titleMedium),
                      Text(i.masked, style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InstrumentStatusChip(instrument: i),
            if (i.blocked && i.blockedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Blocked on ${Dates.dateTime(i.blockedAt!)}'
                '${i.blockReason == null ? '' : ' · ${i.blockReason!.label}'}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator()
            else if (!i.blocked)
              OutlinedButton.icon(
                key: Key('block-${i.id}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: onBlock,
                icon: const Icon(Icons.block),
                label: Text('Block ${i.label.toLowerCase()}'),
              )
            else if (i.blockReason?.canUnblock ?? true)
              TextButton.icon(
                key: Key('unblock-${i.id}'),
                onPressed: onUnblock,
                icon: const Icon(Icons.lock_open),
                label: const Text('Unblock'),
              )
            else
              Text(
                'Reported ${i.blockReason!.label.toLowerCase()}. A '
                'replacement is needed; it cannot be unblocked.',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks why the instrument is being blocked. Returns the reason via pop.
class BlockReasonSheet extends StatefulWidget {
  const BlockReasonSheet({super.key, required this.instrument});

  final Instrument instrument;

  @override
  State<BlockReasonSheet> createState() => _BlockReasonSheetState();
}

class _BlockReasonSheetState extends State<BlockReasonSheet> {
  BlockReason? _reason;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Block ${widget.instrument.displayName}',
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text('It stops working straight away for every payment.'),
            const SizedBox(height: 12),
            for (final r in BlockReason.values)
              Semantics(
                selected: _reason == r,
                child: ListTile(
                  key: Key('reason-${r.api}'),
                  selected: _reason == r,
                  leading: Icon(
                    _reason == r
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(r.label),
                  subtitle: Text(r.description),
                  onTap: () => setState(() => _reason = r),
                ),
              ),
            if (_reason != null && !_reason!.canUnblock)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: InlineMessage(
                  tone: Tone.warning,
                  message:
                      'Lost or stolen instruments cannot be unblocked. You '
                      'will need a replacement.',
                ),
              ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const Key('confirm-block'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                minimumSize: const Size.fromHeight(52),
              ),
              onPressed:
                  _reason == null
                      ? null
                      : () => Navigator.of(context).pop(_reason),
              icon: const Icon(Icons.fingerprint),
              label: const Text('Block now'),
            ),
          ],
        ),
      ),
    );
  }
}
