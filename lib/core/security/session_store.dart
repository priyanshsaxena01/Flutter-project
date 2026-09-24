import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What we keep between launches. Only the token and a display name;
/// never the PIN.
class StoredSession {
  const StoredSession({
    required this.token,
    required this.customerName,
    required this.customerId,
  });

  final String token;
  final String customerName;
  final String customerId;
}

/// Where the session lives.
///
/// The app ships with [MemorySessionStore] so it runs on every platform with
/// zero setup. To keep the session in the Keychain / Keystore, add
/// flutter_secure_storage and implement this interface (see README).
abstract class SessionStore {
  Future<StoredSession?> read();
  Future<void> write(StoredSession session);
  Future<void> clear();
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore([this._session]);

  StoredSession? _session;

  @override
  Future<StoredSession?> read() async => _session;

  @override
  Future<void> write(StoredSession session) async {
    _session = session;
  }

  @override
  Future<void> clear() async {
    _session = null;
  }
}

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => MemorySessionStore(),
);
