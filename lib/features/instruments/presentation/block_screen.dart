import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/idempotency.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/instruments/domain/instrument.dart';
import 'package:fraud_shield/features/instruments/state/instruments_provider.dart';
import 'package:fraud_shield/features/instruments/widgets/instrument_widgets.dart';

/// F3: block a card, UPI or net banking with a reason, and see which
/// instruments are blocked. /block?instrumentId=... highlights one.
class BlockScreen extends ConsumerStatefulWidget {
  const BlockScreen({super.key, this.highlightId});

  final String? highlightId;

  @override
  ConsumerState<BlockScreen> createState() => _BlockScreenState();
}

class _BlockScreenState extends ConsumerState<BlockScreen> {
  final _busy = <String>{};

  void _snack(String text, {SnackBarAction? action}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _block(Instrument instrument) async {
    final reason = await showModalBottomSheet<BlockReason>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => BlockReasonSheet(instrument: instrument),
    );
    if (reason == null) return;
    // One key for this confirmation, reused by "Retry" (B6).
    await _runBlock(instrument, reason, newIdempotencyKey());
  }

  Future<void> _runBlock(
    Instrument instrument,
    BlockReason reason,
    String key,
  ) async {
    if (_busy.contains(instrument.id)) return;
    setState(() => _busy.add(instrument.id));
    try {
      final done = await ref
          .read(instrumentsProvider.notifier)
          .block(instrument, reason, idempotencyKey: key);
      _snack(
        done
            ? '${instrument.displayName} is blocked.'
            : 'We could not confirm it\'s you, so nothing was blocked.',
      );
    } on BankError catch (e) {
      _snack(
        e.message,
        action: SnackBarAction(
          label: 'Retry',
          onPressed: () => unawaited(_runBlock(instrument, reason, key)),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy.remove(instrument.id));
    }
  }

  Future<void> _unblock(Instrument instrument) async {
    final sure = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text('Unblock ${instrument.displayName}?'),
            content: const Text(
              'Only unblock it if you are sure nobody else can use it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Unblock'),
              ),
            ],
          ),
    );
    if (sure != true) return;
    setState(() => _busy.add(instrument.id));
    try {
      final done = await ref
          .read(instrumentsProvider.notifier)
          .unblock(instrument, idempotencyKey: newIdempotencyKey());
      _snack(
        done
            ? '${instrument.displayName} is active again.'
            : 'We could not confirm it\'s you, so nothing changed.',
      );
    } on BankError catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy.remove(instrument.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final instruments = ref.watch(instrumentsProvider);
    Future<void> refresh() =>
        refreshQuietly(ref.read(instrumentsProvider.notifier).refresh());

    return Scaffold(
      appBar: AppBar(title: const Text('Block & unblock')),
      body: instruments.when(
        skipLoadingOnRefresh: true,
        loading: () => const SkeletonList(itemHeight: 150),
        error:
            (e, _) => RefreshableList(
              onRefresh: refresh,
              children: [
                ErrorView(
                  error: e,
                  onRetry: () => ref.invalidate(instrumentsProvider),
                ),
              ],
            ),
        data:
            (list) => RefreshableList(
              onRefresh: refresh,
              children: [
                if (list.isEmpty)
                  const EmptyView(
                    icon: Icons.credit_card_off_outlined,
                    title: 'No cards or UPI IDs',
                    message: 'Nothing to block on this account.',
                  ),
                for (final i in list) ...[
                  InstrumentCard(
                    instrument: i,
                    busy: _busy.contains(i.id),
                    highlighted: i.id == widget.highlightId,
                    onBlock: () => unawaited(_block(i)),
                    onUnblock: () => unawaited(_unblock(i)),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
      ),
    );
  }
}
