import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import 'package:fraud_shield/core/realtime/backoff.dart';
import 'package:fraud_shield/core/realtime/sse_parser.dart';

enum LiveStatus { idle, connecting, live, reconnecting }

class LiveState {
  const LiveState(this.status, {this.attempt = 0, this.retryIn});

  final LiveStatus status;
  final int attempt;
  final Duration? retryIn;
}

sealed class RealtimeEvent {
  const RealtimeEvent();
}

/// A new or updated alert, as raw JSON (the feature layer builds the model).
final class AlertPushed extends RealtimeEvent {
  const AlertPushed(this.json);

  final Map<String, Object?> json;
}

/// The stream came back after a drop. Listeners should fetch anything they
/// missed since the last alert id they know.
final class StreamReconnected extends RealtimeEvent {
  const StreamReconnected();
}

/// Keeps a live Server-Sent Events connection to GET /alerts/stream open.
///
/// * Alerts arrive within a second of the server flagging them (Latency NFR).
/// * If the connection drops it reconnects with exponential backoff, sends
///   Last-Event-ID so the server replays missed events, and announces
///   [StreamReconnected] so the app can also re-fetch "since the last id".
/// * A 401 stops it; the auth interceptor has already signed the user out.
class AlertStreamClient {
  AlertStreamClient({
    required Dio dio,
    this.backoff = const Backoff(),
    Random? random,
  }) : _dio = dio,
       _random = random ?? Random();

  final Dio _dio;
  final Backoff backoff;
  final Random _random;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _states = StreamController<LiveState>.broadcast();

  LiveState _state = const LiveState(LiveStatus.idle);
  String? _lastEventId;
  bool _running = false;
  bool _everConnected = false;
  int _attempt = 0;
  CancelToken? _cancel;
  StreamSubscription<String>? _subscription;
  Timer? _retryTimer;

  Stream<RealtimeEvent> get events => _events.stream;
  Stream<LiveState> get states => _states.stream;
  LiveState get state => _state;

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_connect());
  }

  /// Skip the backoff wait (the "Reconnect now" button).
  void reconnectNow() {
    if (!_running || _state.status == LiveStatus.live) return;
    _retryTimer?.cancel();
    unawaited(_connect());
  }

  Future<void> _connect() async {
    if (!_running) return;
    _retryTimer?.cancel();
    _setState(
      LiveState(
        _everConnected ? LiveStatus.reconnecting : LiveStatus.connecting,
        attempt: _attempt,
      ),
    );

    final token = CancelToken();
    _cancel?.cancel('replaced');
    _cancel = token;
    try {
      final response = await _dio.get<ResponseBody>(
        '/alerts/stream',
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
          headers: {
            'Accept': 'text/event-stream',
            if (_lastEventId != null) 'Last-Event-ID': _lastEventId,
          },
        ),
        cancelToken: token,
      );
      if (!_running || token.isCancelled) return;

      final wasReconnect = _everConnected;
      _everConnected = true;
      _attempt = 0;
      _setState(const LiveState(LiveStatus.live));
      if (wasReconnect) _events.add(const StreamReconnected());

      final parser = SseParser();
      final lines = const LineSplitter().bind(
        utf8.decoder.bind(response.data!.stream),
      );
      _subscription = lines.listen(
        (line) {
          final message = parser.addLine(line);
          if (message != null) _onMessage(message);
        },
        onError: (Object _) => _scheduleReconnect(token),
        onDone: () => _scheduleReconnect(token),
        cancelOnError: true,
      );
    } on DioException catch (e) {
      if (!_running || token.isCancelled) return;
      if (e.response?.statusCode == 401) {
        stop();
        return;
      }
      _scheduleReconnect(token);
    }
  }

  void _onMessage(SseMessage message) {
    if (message.id != null) _lastEventId = message.id;
    if (message.event != 'alert') return;
    try {
      final json = jsonDecode(message.data);
      if (json is Map<String, Object?>) _events.add(AlertPushed(json));
    } on FormatException {
      // Ignore a malformed event rather than dropping the connection.
    }
  }

  void _scheduleReconnect(CancelToken token) {
    if (!_running || !identical(_cancel, token)) return;
    unawaited(_subscription?.cancel());
    _subscription = null;
    token.cancel('reconnecting');
    _attempt++;
    final delay = backoff.delayFor(_attempt, random: _random.nextDouble());
    _setState(
      LiveState(LiveStatus.reconnecting, attempt: _attempt, retryIn: delay),
    );
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () => unawaited(_connect()));
  }

  void stop() {
    _running = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    _cancel?.cancel('stopped');
    _cancel = null;
    _setState(const LiveState(LiveStatus.idle));
  }

  void dispose() {
    stop();
    unawaited(_events.close());
    unawaited(_states.close());
  }

  void _setState(LiveState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}
