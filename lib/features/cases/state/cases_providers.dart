import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';
import 'package:fraud_shield/core/network/idempotency.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/features/cases/data/case_repository.dart';
import 'package:fraud_shield/features/cases/domain/case_message.dart';
import 'package:fraud_shield/features/cases/domain/dispute_case.dart';

/// The app's clock. Tests override it to show "2 days left" and so on.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Ticks every 30 s so SLA countdowns stay current without a refresh.
final slaTickerProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  final now = ref.watch(clockProvider);
  yield now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => now());
});

final casesProvider = FutureProvider.autoDispose<List<DisputeCase>>((ref) {
  ref.watch(sessionProvider.select((s) => s.token));
  return ref.watch(caseRepositoryProvider).fetchAll();
});

final caseProvider = FutureProvider.autoDispose.family<DisputeCase, String>(
  (ref, id) => ref.watch(caseRepositoryProvider).fetch(id),
);

// ---------------------------------------------------------------------------
// Secure messages (F8): paginated, newest at the bottom.
// ---------------------------------------------------------------------------

class MessagesState {
  const MessagesState({
    required this.items,
    this.nextCursor,
    this.loadingOlder = false,
    this.sending = false,
    this.error,
  });

  /// Newest first (the list is drawn reversed, so newest is at the bottom).
  final List<CaseMessage> items;
  final String? nextCursor;
  final bool loadingOlder;
  final bool sending;
  final String? error;

  bool get hasOlder => nextCursor != null;

  MessagesState copyWith({
    List<CaseMessage>? items,
    String? nextCursor,
    bool clearCursor = false,
    bool? loadingOlder,
    bool? sending,
    String? error,
    bool clearError = false,
  }) {
    return MessagesState(
      items: items ?? this.items,
      nextCursor: clearCursor ? null : (nextCursor ?? this.nextCursor),
      loadingOlder: loadingOlder ?? this.loadingOlder,
      sending: sending ?? this.sending,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class CaseMessagesNotifier
    extends AutoDisposeFamilyAsyncNotifier<MessagesState, String> {
  /// One key per message being composed; kept if sending fails.
  String _sendKey = newIdempotencyKey();

  @override
  Future<MessagesState> build(String caseId) async {
    final page = await ref.read(caseRepositoryProvider).messages(caseId);
    return MessagesState(items: page.items, nextCursor: page.nextCursor);
  }

  Future<void> loadOlder() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasOlder || current.loadingOlder) return;
    state = AsyncData(current.copyWith(loadingOlder: true, clearError: true));
    try {
      final page = await ref
          .read(caseRepositoryProvider)
          .messages(arg, cursor: current.nextCursor);
      state = AsyncData(
        current.copyWith(
          items: _merge(current.items, page.items),
          nextCursor: page.nextCursor,
          clearCursor: page.nextCursor == null,
          loadingOlder: false,
        ),
      );
    } on BankError catch (e) {
      state = AsyncData(
        current.copyWith(loadingOlder: false, error: e.message),
      );
    }
  }

  /// Returns true when sent.
  Future<bool> send(String text, {String? attachmentName}) async {
    final current = state.valueOrNull;
    if (current == null || current.sending) return false;
    state = AsyncData(current.copyWith(sending: true, clearError: true));
    final repo = ref.read(caseRepositoryProvider);
    try {
      await repo.send(
        arg,
        text,
        attachmentName: attachmentName,
        idempotencyKey: _sendKey,
      );
      _sendKey = newIdempotencyKey();
      // Fetch the newest page to pick up the bank's reply too.
      final latest = await repo.messages(arg);
      final now = state.valueOrNull ?? current;
      state = AsyncData(
        now.copyWith(items: _merge(now.items, latest.items), sending: false),
      );
      ref.invalidate(caseProvider(arg));
      return true;
    } on BankError catch (e) {
      final now = state.valueOrNull ?? current;
      state = AsyncData(now.copyWith(sending: false, error: e.message));
      return false;
    }
  }

  static List<CaseMessage> _merge(List<CaseMessage> a, List<CaseMessage> b) {
    final byId = {for (final m in a) m.id: m, for (final m in b) m.id: m};
    return byId.values.toList()..sort((x, y) => y.at.compareTo(x.at));
  }
}

final caseMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<CaseMessagesNotifier, MessagesState, String>(
      CaseMessagesNotifier.new,
    );
