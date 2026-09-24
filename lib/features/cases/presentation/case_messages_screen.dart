import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/device/file_picker_service.dart';
import 'package:fraud_shield/core/utils/dates.dart';
import 'package:fraud_shield/core/utils/validators.dart';
import 'package:fraud_shield/core/widgets/state_views.dart';
import 'package:fraud_shield/features/cases/domain/case_message.dart';
import 'package:fraud_shield/features/cases/state/cases_providers.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';

/// F8: two-way secure messages. Pages of 15, newest at the bottom; older
/// messages load when you scroll up.
class CaseMessagesScreen extends ConsumerStatefulWidget {
  const CaseMessagesScreen({super.key, required this.caseId});

  final String caseId;

  @override
  ConsumerState<CaseMessagesScreen> createState() => _CaseMessagesScreenState();
}

class _CaseMessagesScreenState extends ConsumerState<CaseMessagesScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  PickedFile? _attachment;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadOlder);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The list is reversed, so "older" is at the far end of the scroll.
  void _maybeLoadOlder() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    if (p.pixels >= p.maxScrollExtent - 200) {
      unawaited(
        ref.read(caseMessagesProvider(widget.caseId).notifier).loadOlder(),
      );
    }
  }

  Future<void> _attach() async {
    final files = await ref
        .read(filePickerServiceProvider)
        .pickEvidence(context);
    if (files.isEmpty || !mounted) return;
    final file = files.first;
    final problem = EvidenceRules.checkFile(
      name: file.name,
      sizeBytes: file.sizeBytes,
      mimeType: file.mimeType,
      filesSoFar: 0,
    );
    setState(() {
      _attachment = problem == null ? file : null;
      _inputError = problem;
    });
  }

  Future<void> _send() async {
    final error = Validators.message(_text.text);
    if (error != null) {
      setState(() => _inputError = error);
      return;
    }
    final sent = await ref
        .read(caseMessagesProvider(widget.caseId).notifier)
        .send(_text.text.trim(), attachmentName: _attachment?.name);
    if (sent && mounted) {
      _text.clear();
      setState(() {
        _attachment = null;
        _inputError = null;
      });
      if (_scroll.hasClients) {
        unawaited(
          _scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(caseMessagesProvider(widget.caseId));
    final state = messages.valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: messages.when(
                skipLoadingOnRefresh: true,
                loading: () => const SkeletonList(itemHeight: 64),
                error:
                    (e, _) => ErrorView(
                      error: e,
                      onRetry:
                          () => ref.invalidate(
                            caseMessagesProvider(widget.caseId),
                          ),
                    ),
                data:
                    (s) =>
                        s.items.isEmpty
                            ? const Center(
                              child: EmptyView(
                                icon: Icons.forum_outlined,
                                title: 'No messages yet',
                                message: 'Ask the disputes team anything here.',
                              ),
                            )
                            : ListView.builder(
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.all(16),
                              itemCount: s.items.length + (s.hasOlder ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == s.items.length) {
                                  return Center(
                                    child:
                                        s.loadingOlder
                                            ? const Padding(
                                              padding: EdgeInsets.all(12),
                                              child:
                                                  CircularProgressIndicator(),
                                            )
                                            : TextButton(
                                              onPressed:
                                                  () => unawaited(
                                                    ref
                                                        .read(
                                                          caseMessagesProvider(
                                                            widget.caseId,
                                                          ).notifier,
                                                        )
                                                        .loadOlder(),
                                                  ),
                                              child: const Text(
                                                'Load older messages',
                                              ),
                                            ),
                                  );
                                }
                                return _Bubble(message: s.items[index]);
                              },
                            ),
              ),
            ),
            if (state?.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: InlineMessage(message: state!.error!),
              ),
            _Composer(
              controller: _text,
              attachment: _attachment,
              error: _inputError,
              sending: state?.sending ?? false,
              onAttach: () => unawaited(_attach()),
              onRemoveAttachment: () => setState(() => _attachment = null),
              onSend: () => unawaited(_send()),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final CaseMessage message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final mine = message.from == MessageSender.customer;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine ? scheme.primaryContainer : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine ? 'You' : 'FraudShield disputes team',
                style: Theme.of(context).textTheme.labelMedium,
              ),
              const SizedBox(height: 2),
              Text(message.text),
              if (message.attachmentName != null) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.attach_file, size: 16),
                    Flexible(child: Text(message.attachmentName!)),
                  ],
                ),
              ],
              const SizedBox(height: 4),
              Text(
                Dates.dateTime(message.at),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.attachment,
    required this.error,
    required this.sending,
    required this.onAttach,
    required this.onRemoveAttachment,
    required this.onSend,
  });

  final TextEditingController controller;
  final PickedFile? attachment;
  final String? error;
  final bool sending;
  final VoidCallback onAttach;
  final VoidCallback onRemoveAttachment;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachment != null)
              InputChip(
                avatar: const Icon(Icons.attach_file, size: 18),
                label: Text(attachment!.name),
                onDeleted: onRemoveAttachment,
                deleteButtonTooltipMessage: 'Remove attachment',
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Attach a file',
                  onPressed: sending ? null : onAttach,
                  icon: const Icon(Icons.attach_file),
                ),
                Expanded(
                  child: TextField(
                    key: const Key('message-input'),
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText: 'Write a message',
                      errorText: error,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Send message',
                  onPressed: sending ? null : onSend,
                  icon:
                      sending
                          ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Icon(Icons.send),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
