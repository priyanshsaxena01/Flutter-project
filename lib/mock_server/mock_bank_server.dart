import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/utils/money.dart';
import 'package:fraud_shield/features/disputes/domain/dispute.dart';
import 'package:fraud_shield/features/disputes/domain/dispute_rules.dart';
import 'package:fraud_shield/features/disputes/domain/evidence_rules.dart';
import 'package:fraud_shield/mock_server/fraud_scoring.dart';
import 'package:fraud_shield/mock_server/mock_http_adapter.dart';
import 'package:fraud_shield/mock_server/mock_seed.dart';

/// A pretend bank server that runs inside the app, so there is nothing to
/// install. It follows the FraudShield API contract exactly (paths, integer
/// paise, ISO dates, the error shape, Idempotency-Key, a live alert stream),
/// so the app code is the same code you would ship against a real server.
///
/// Demo login:  customer ID  TEST_CUSTOM   PIN  0123456789
final mockBankServerProvider = Provider<MockBankServer>((ref) {
  final server = MockBankServer();
  ref.onDispose(server.dispose);
  return server;
});

/// "Chaos switches" to demo failure paths. Toggle them on the Demo screen.
class ChaosSwitches {
  bool offline = false;
  bool slowNetwork = false;
  bool failNextRequest = false;
  bool expireSessionOnNextRequest = false;
  bool failNextUploadAt90 = false;
  bool cardNetworkDown = false;
}

class MockBankServer {
  MockBankServer({
    this.latency = const Duration(milliseconds: 350),
    this.heartbeat = const Duration(seconds: 15),
    this.firstAutoAlertAfter = const Duration(seconds: 20),
    this.autoAlertEvery = const Duration(seconds: 60),
    this.uploadDelayPer64Kb = const Duration(milliseconds: 25),
    this.reviewAfter = const Duration(seconds: 20),
    this.creditAfter = const Duration(seconds: 60),
    bool autoAlerts = true,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now,
       _autoAlerts = autoAlerts {
    reset();
  }

  /// A quiet server for tests: instant answers and no timers.
  factory MockBankServer.forTests({DateTime Function()? clock}) =>
      MockBankServer(
        latency: Duration.zero,
        heartbeat: null,
        uploadDelayPer64Kb: Duration.zero,
        autoAlerts: false,
        clock: clock,
      );

  static const demoCustomerId = 'TEST_CUSTOM';
  static const demoPin = '0123456789';
  static const creditCapPaise = 1000000;

  final Duration latency;
  final Duration? heartbeat;
  final Duration firstAutoAlertAfter;
  final Duration autoAlertEvery;
  final Duration uploadDelayPer64Kb;

  /// New cases move along by themselves, so the demo feels alive:
  /// assigned after [reviewAfter], provisional credit after [creditAfter].
  final Duration reviewAfter;
  final Duration creditAfter;

  final DateTime Function() _clock;
  final chaos = ChaosSwitches();
  final _random = Random();

  late MockDb _db;
  final _tokens = <String, String>{}; // token -> device id
  final _idempotent = <String, MockResponse>{};
  final _inflight = <String, Future<MockResponse>>{};
  final _events = <({int id, Map<String, Object?> data})>[];
  final _connections = <_SseConnection>{};
  int _eventId = 0;
  int _failedLogins = 0;
  int _traceSeq = 1;
  int _templateIndex = 0;
  bool _autoAlerts;
  Timer? _firstAutoTimer;
  Timer? _autoTimer;

  /// How many times an instrument actually went from active to blocked.
  /// Tests use it to prove "one block" under retries.
  int blockActions = 0;

  DateTime get now => _clock();
  MockDb get db => _db;
  int get openStreams => _connections.length;
  List<Map<String, Object?>> get auditLog => List.unmodifiable(_db.audit);

  bool get autoAlerts => _autoAlerts;
  set autoAlerts(bool value) {
    _autoAlerts = value;
    _syncAutoTimer();
  }

  /// Back to the demo data. Signed-in sessions stay valid.
  void reset() {
    _db = MockDb();
    seedDemoData(_db, now);
    _idempotent.clear();
    _events.clear();
    _failedLogins = 0;
    blockActions = 0;
    dropStreams();
  }

  void setOffline(bool value) {
    chaos.offline = value;
    if (value) dropStreams();
  }

  /// Simulates the live connection breaking (for example a tunnel).
  void dropStreams() {
    for (final c in [..._connections]) {
      c.close();
    }
  }

  void dispose() {
    _firstAutoTimer?.cancel();
    _autoTimer?.cancel();
    dropStreams();
  }

  /// Tests: a valid token for [deviceId] without going through login.
  String signInForTests({
    String deviceId = 'dev-test',
    String deviceName = 'Test device',
  }) {
    final token = 'tok-${_hex(16)}';
    _tokens[token] = deviceId;
    _registerDevice(deviceId, deviceName);
    return token;
  }

  // -------------------------------------------------------------------------
  // Request pipeline
  // -------------------------------------------------------------------------

  Future<MockResponse> handle(MockRequest req) async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(chaos.slowNetwork ? latency * 8 : latency);
    }
    if (chaos.offline) throw const MockNetworkDown();

    final method = req.method;
    final s = req.segments;
    final isLogin = method == 'POST' && req.path == '/auth/login';

    if (chaos.failNextRequest) {
      chaos.failNextRequest = false;
      return _error(
        503,
        'SERVICE_UNAVAILABLE',
        'Our systems are busy right now. Please try again in a moment.',
      );
    }

    if (!isLogin) {
      if (chaos.expireSessionOnNextRequest) {
        chaos.expireSessionOnNextRequest = false;
        _tokens.clear();
        return _error(
          401,
          'SESSION_EXPIRED',
          'Your session has expired. Please sign in again.',
        );
      }
      final token = _bearer(req);
      if (token == null) {
        return _error(401, 'UNAUTHENTICATED', 'Please sign in again.');
      }
      _touchDevice(_tokens[token]!, req.header('x-device-name'));
    }

    final isUpload =
        method == 'POST' &&
        s.length == 3 &&
        s[0] == 'disputes' &&
        s[2] == 'evidence';
    final body = isUpload ? const <String, Object?>{} : await req.readJson();

    final MockResponse response;
    if (!_needsIdempotencyKey(method, s)) {
      response = await _route(req, body);
    } else {
      final key = req.header('idempotency-key');
      if (key == null || key.isEmpty) {
        response = _error(
          400,
          'IDEMPOTENCY_KEY_REQUIRED',
          'Missing Idempotency-Key header.',
        );
      } else {
        response = await _idempotently(
          '$method ${req.path}|$key',
          () => _route(req, body),
        );
      }
    }

    if (method != 'GET') _audit(req, response.status);
    return response;
  }

  /// Same key -> same response. A second request that arrives while the
  /// first is still running waits for it instead of running twice
  /// ("Deny tapped twice on a slow network: one block, one case").
  Future<MockResponse> _idempotently(
    String storeKey,
    Future<MockResponse> Function() run,
  ) async {
    final stored = _idempotent[storeKey];
    if (stored != null) return stored.snapshot();

    final running = _inflight[storeKey];
    if (running != null) {
      final first = await running;
      return first.isSuccess ? first.snapshot() : first;
    }

    final future = run();
    _inflight[storeKey] = future;
    try {
      final response = await future;
      // Only successes are remembered, so a request that failed validation
      // can be fixed and retried with the same key.
      if (response.isSuccess) _idempotent[storeKey] = response.snapshot();
      return response;
    } finally {
      _inflight.remove(storeKey)?.ignore();
    }
  }

  static bool _needsIdempotencyKey(String method, List<String> s) {
    if (method != 'POST' || s.isEmpty) return false;
    final n = s.length;
    return (s[0] == 'alerts' && n == 3 && s[2] == 'deny') ||
        (s[0] == 'instruments' && n == 3) ||
        (s[0] == 'disputes' && (n == 1 || n == 3)) ||
        (s[0] == 'cases' && n == 3 && s[2] == 'messages');
  }

  Future<MockResponse> _route(
    MockRequest req,
    Map<String, Object?> body,
  ) async {
    final m = req.method;
    final s = req.segments;
    final n = s.length;
    final device = req.header('x-device-id') ?? 'unknown';
    if (n == 0) return _notFound('page');

    switch (s[0]) {
      case 'auth':
        if (m == 'POST' && n == 2 && s[1] == 'login') return _login(req, body);
        if (m == 'POST' && n == 2 && s[1] == 'logout') return _logout(req);
      case 'alerts':
        if (m == 'GET' && n == 1) return _listAlerts(req);
        if (m == 'GET' && n == 2 && s[1] == 'stream') return _openStream(req);
        if (m == 'GET' && n == 2) return _getAlert(s[1]);
        if (m == 'POST' && n == 3 && s[2] == 'confirm') return _confirm(s[1]);
        if (m == 'POST' && n == 3 && s[2] == 'deny') return _deny(s[1]);
      case 'instruments':
        if (m == 'GET' && n == 1) {
          return MockResponse(200, {
            'items': [..._db.instruments.values],
          });
        }
        if (m == 'POST' && n == 3 && s[2] == 'block') {
          return _block(s[1], body['reason'] as String?);
        }
        if (m == 'POST' && n == 3 && s[2] == 'unblock') return _unblock(s[1]);
      case 'transactions':
        if (m == 'GET' && n == 1) return _listTransactions();
      case 'disputes':
        if (m == 'POST' && n == 1) return _createDispute(body);
        if (m == 'GET' && n == 2) {
          final d = _db.disputes[s[1]];
          return d == null ? _notFound('dispute') : MockResponse(200, d);
        }
        if (m == 'PATCH' && n == 2) return _updateDispute(s[1], body);
        if (m == 'POST' && n == 3 && s[2] == 'evidence') {
          return _uploadEvidence(s[1], req);
        }
        if (m == 'POST' && n == 3 && s[2] == 'submit') {
          return _submitDispute(s[1]);
        }
      case 'cases':
        if (m == 'GET' && n == 1) return _listCases();
        if (m == 'GET' && n == 2) return _getCase(s[1]);
        if (m == 'GET' && n == 3 && s[2] == 'messages') {
          return _listMessages(s[1], req);
        }
        if (m == 'POST' && n == 3 && s[2] == 'messages') {
          return _postMessage(s[1], body);
        }
      case 'devices':
        if (m == 'GET' && n == 1) return _listDevices(device);
        if (m == 'DELETE' && n == 2) return _removeDevice(s[1], device);
      case 'security':
        if (m == 'GET' && n == 2 && s[1] == 'logins') {
          final items = [..._db.logins]
            ..sort((a, b) => _time(b, 'at').compareTo(_time(a, 'at')));
          return MockResponse(200, {'items': items});
        }
        if (m == 'GET' && n == 2 && s[1] == 'audit') {
          final items = _db.audit.reversed.take(100).toList();
          return MockResponse(200, {'items': items});
        }
    }
    return _notFound('page');
  }

  // -------------------------------------------------------------------------
  // Auth and devices
  // -------------------------------------------------------------------------

  MockResponse _login(MockRequest req, Map<String, Object?> body) {
    final id = (body['customerId'] as String? ?? '').trim().toUpperCase();
    final pin = body['pin'] as String? ?? '';
    final deviceId = req.header('x-device-id') ?? 'unknown';
    final deviceName = req.header('x-device-name') ?? 'Unknown device';

    if (_failedLogins >= 5) {
      return _error(
        423,
        'LOGIN_LOCKED',
        'Too many wrong PINs. Login is locked for 30 minutes. Call '
            '1800-123-4567 if you need help now.',
      );
    }
    if (id != _db.customer['id'] || pin != _db.customer['pin']) {
      _failedLogins++;
      _db.logins.add({
        'at': iso(now),
        'deviceName': deviceName,
        'location': 'Pune, IN',
        'success': false,
      });
      final left = 5 - _failedLogins;
      if (left == 0) {
        return _error(
          423,
          'LOGIN_LOCKED',
          'Too many wrong PINs. Login is locked for 30 minutes.',
        );
      }
      return _error(
        401,
        'INVALID_CREDENTIALS',
        'Customer ID or PIN is incorrect. $left '
            '${left == 1 ? 'attempt' : 'attempts'} left.',
      );
    }

    _failedLogins = 0;
    final token = 'tok-${_hex(16)}';
    _tokens[token] = deviceId;
    _registerDevice(deviceId, deviceName);
    _db.logins.add({
      'at': iso(now),
      'deviceName': deviceName,
      'location': 'Pune, IN',
      'success': true,
    });
    return MockResponse(200, {
      'token': token,
      'customer': {'id': _db.customer['id'], 'name': _db.customer['name']},
    });
  }

  MockResponse _logout(MockRequest req) {
    final token = _bearer(req);
    if (token != null) _tokens.remove(token);
    return const MockResponse(200, {'ok': true});
  }

  String? _bearer(MockRequest req) {
    final auth = req.header('authorization') ?? '';
    if (!auth.startsWith('Bearer ')) return null;
    final token = auth.substring(7);
    return _tokens.containsKey(token) ? token : null;
  }

  void _registerDevice(String id, String name) {
    _db.devices[id] = {
      'id': id,
      'name': '$name · FraudShield app',
      'location': 'Pune, IN',
      'lastSeen': iso(now),
    };
  }

  void _touchDevice(String id, String? name) {
    final device = _db.devices[id];
    if (device == null) {
      _registerDevice(id, name ?? 'Unknown device');
    } else {
      device['lastSeen'] = iso(now);
    }
  }

  MockResponse _listDevices(String currentId) {
    final items = [
      for (final d in _db.devices.values)
        {...d, 'current': d['id'] == currentId},
    ];
    items.sort((a, b) {
      if (a['current'] == true) return -1;
      if (b['current'] == true) return 1;
      return _time(b, 'lastSeen').compareTo(_time(a, 'lastSeen'));
    });
    return MockResponse(200, {'items': items});
  }

  MockResponse _removeDevice(String id, String currentId) {
    if (!_db.devices.containsKey(id)) return _notFound('device');
    if (id == currentId) {
      return _error(
        409,
        'CURRENT',
        'You can\'t sign out the device you are using. Use Log out instead.',
      );
    }
    _db.devices.remove(id);
    _tokens.removeWhere((_, device) => device == id);
    return MockResponse(200, {'removed': id});
  }

  void _audit(MockRequest req, int status) {
    _db.audit.add(
      Map<String, Object?>.unmodifiable({
        'id': 'aud_${_db.audit.length + 1}',
        'at': iso(now),
        'clientAt': req.header('x-client-timestamp'),
        'deviceId': req.header('x-device-id') ?? 'unknown',
        'action': '${req.method} ${req.path}',
        'idempotencyKey': req.header('idempotency-key'),
        'status': status,
      }),
    );
  }

  // -------------------------------------------------------------------------
  // Alerts and the live stream
  // -------------------------------------------------------------------------

  Map<String, Object?> _alertJson(Map<String, Object?> a) => {
    ...a,
    'instrumentLabel': _instrumentLabel(a['instrumentId']! as String),
  };

  String _instrumentLabel(String id) {
    final i = _db.instruments[id];
    return i == null ? '' : '${i['label']} ${i['masked']}';
  }

  MockResponse _listAlerts(MockRequest req) {
    final q = req.uri.queryParameters;
    var items = _db.alerts.values.toList();
    final status = q['status'];
    if (status != null && status.isNotEmpty) {
      items = items.where((a) => a['status'] == status).toList();
    }
    final sinceId = q['sinceId'];
    if (sinceId != null && sinceId.isNotEmpty) {
      final since = (_db.alerts[sinceId]?['seq'] as int?) ?? 0;
      items = items.where((a) => (a['seq']! as int) > since).toList();
    }
    items.sort((a, b) => (b['seq']! as int).compareTo(a['seq']! as int));
    return MockResponse(200, {
      'items': [for (final a in items) _alertJson(a)],
      'nextCursor': null,
    });
  }

  MockResponse _getAlert(String id) {
    final a = _db.alerts[id];
    return a == null ? _notFound('alert') : MockResponse(200, _alertJson(a));
  }

  MockResponse _confirm(String id) {
    final a = _db.alerts[id];
    if (a == null) return _notFound('alert');
    switch (a['status']) {
      case 'CONFIRMED':
        return MockResponse(200, _alertJson(a));
      case 'DENIED':
        return _error(
          409,
          'ALREADY_DENIED',
          'You already reported this payment as not made by you. The '
              'instrument is blocked and a case is open.',
          details: {'caseId': a['caseId']},
        );
      case 'INSTRUMENT_BLOCKED':
        return _error(
          409,
          'INSTRUMENT_BLOCKED',
          'This payment was declined because the instrument is blocked. '
              'No action is needed.',
        );
    }
    a['status'] = 'CONFIRMED';
    a['actionedAt'] = iso(now);
    _emitAlert(a);
    return MockResponse(200, _alertJson(a));
  }

  /// "No, it wasn't me": block the instrument and open an unauthorised
  /// dispute case, in one call, so it completes well under 2 seconds.
  MockResponse _deny(String id) {
    final a = _db.alerts[id];
    if (a == null) return _notFound('alert');
    switch (a['status']) {
      case 'DENIED':
        final c = _db.cases[a['caseId']];
        return _error(
          409,
          'ALREADY_DENIED',
          'You already reported this payment. The instrument is blocked and '
              'a case is open.',
          details: {
            'caseId': a['caseId'],
            'caseNumber': c?['caseNumber'],
            'disputeId': c?['disputeId'],
          },
        );
      case 'CONFIRMED':
        return _error(
          409,
          'ALREADY_CONFIRMED',
          'You confirmed this payment earlier. If that was a mistake, block '
              'the instrument from the Block screen and raise a dispute.',
        );
      case 'INSTRUMENT_BLOCKED':
        return _error(
          409,
          'INSTRUMENT_BLOCKED',
          'This payment was declined because the instrument is already '
              'blocked. No action is needed.',
        );
    }

    final t = now;
    final txn = _db.transactions[a['txnId']]!;
    final instrument = _db.instruments[a['instrumentId']]!;
    final label = _instrumentLabel(instrument['id']! as String);
    final wasBlocked = instrument['blocked'] == true;
    if (!wasBlocked) _doBlock(instrument, 'SUSPICIOUS');

    final dispute = _newDispute(
      txn: txn,
      reason: DisputeReason.unauthorised,
      answers: const {},
      status: 'SUBMITTED',
    );
    final c = _openCase(
      dispute: dispute,
      txn: txn,
      firstEntries: [
        _entry(
          t,
          'CUSTOMER',
          'You reported this payment as not made by you',
          'From the alert for ${a['merchant']}',
        ),
        _entry(
          t,
          'SYSTEM',
          wasBlocked ? '$label was already blocked' : '$label blocked',
        ),
      ],
    );

    a['status'] = 'DENIED';
    a['caseId'] = c['id'];
    a['actionedAt'] = iso(t);
    _emitAlert(a);

    return MockResponse(200, {
      'alert': _alertJson(a),
      'instrument': instrument,
      'dispute': dispute,
      'case': _caseJson(c),
    });
  }

  MockResponse _openStream(MockRequest req) {
    final lastId = int.tryParse(req.header('last-event-id') ?? '');
    late final _SseConnection connection;
    final controller = StreamController<Uint8List>(
      onListen: () {
        _connections.add(connection);
        // Replay what the client missed while it was disconnected.
        if (lastId != null) {
          for (final e in _events.where((e) => e.id > lastId)) {
            connection.sendEvent(e.id, 'alert', e.data);
          }
        }
        connection.startHeartbeat(heartbeat);
        _syncAutoTimer();
      },
      onCancel: () => connection.close(),
    );
    connection = _SseConnection(
      controller,
      onClosed: () {
        _connections.remove(connection);
        _syncAutoTimer();
      },
    );
    return MockResponse.stream(controller.stream);
  }

  void _emitAlert(Map<String, Object?> alert) {
    final id = ++_eventId;
    final data = _alertJson(alert);
    _events.add((id: id, data: data));
    if (_events.length > 200) _events.removeAt(0);
    for (final c in [..._connections]) {
      c.sendEvent(id, 'alert', data);
    }
  }

  void _syncAutoTimer() {
    final shouldRun = _autoAlerts && _connections.isNotEmpty;
    if (!shouldRun) {
      _firstAutoTimer?.cancel();
      _firstAutoTimer = null;
      _autoTimer?.cancel();
      _autoTimer = null;
      return;
    }
    if (_firstAutoTimer != null || _autoTimer != null) return;
    _firstAutoTimer = Timer(firstAutoAlertAfter, () {
      _firstAutoTimer = null;
      simulateSuspiciousPayment();
      _autoTimer = Timer.periodic(
        autoAlertEvery,
        (_) => simulateSuspiciousPayment(),
      );
    });
  }

  static const _templates = [
    (
      merchant: 'Crypto Xchange',
      category: 'crypto',
      amountPaise: 2450000,
      city: 'Singapore',
      country: 'SG',
    ),
    (
      merchant: 'Electro World',
      category: 'electronics',
      amountPaise: 499900,
      city: 'Dubai',
      country: 'AE',
    ),
    (
      merchant: 'GiftCard Hub',
      category: 'gift cards',
      amountPaise: 999900,
      city: 'Lagos',
      country: 'NG',
    ),
    (
      merchant: 'LuxeBags',
      category: 'fashion',
      amountPaise: 3820000,
      city: 'Paris',
      country: 'FR',
    ),
    (
      merchant: 'QuickPay Wallet',
      category: 'wallet top-up',
      amountPaise: 1500000,
      city: 'Mumbai',
      country: 'IN',
    ),
  ];

  /// The fraud engine flags a new payment. Returns the alert id, or null
  /// when there is no suitable instrument.
  ///
  /// With [onBlockedInstrument] the payment is tried on a blocked card and
  /// declined, so the alert says "Blocked — no action needed".
  String? simulateSuspiciousPayment({bool onBlockedInstrument = false}) {
    final payable =
        _db.instruments.values.where((i) => i['type'] != 'NETBANKING').toList();
    final pool =
        payable
            .where((i) => (i['blocked'] == true) == onBlockedInstrument)
            .toList();
    if (pool.isEmpty) return null;
    final instrument = pool[_random.nextInt(pool.length)];
    final blocked = instrument['blocked'] == true;
    final template = _templates[_templateIndex++ % _templates.length];

    final assessment = FraudScorer.assess(
      PaymentCandidate(
        merchant: template.merchant,
        category: template.category,
        amountPaise: template.amountPaise,
        city: template.city,
        country: template.country,
        instrumentLabel: instrument['label']! as String,
        knownMerchant: _db.transactions.values.any(
          (t) => t['merchant'] == template.merchant,
        ),
      ),
      CustomerProfile(
        homeCity: _db.customer['homeCity']! as String,
        homeCountry: _db.customer['homeCountry']! as String,
        averageSpendPaise: _db.customer['averageSpendPaise']! as int,
      ),
    );
    if (!assessment.raisesAlert && !blocked) return null;

    final txnId = _db.newId('txn');
    _db.transactions[txnId] = {
      'id': txnId,
      'instrumentId': instrument['id'],
      'merchant': template.merchant,
      'category': template.category,
      'amountPaise': template.amountPaise,
      'location': '${template.city}, ${template.country}',
      'at': iso(now),
      'status': blocked ? 'DECLINED' : 'SUCCESS',
    };

    final alertId = _db.newId('alt');
    _db.alertSeq++;
    final alert = <String, Object?>{
      'id': alertId,
      'seq': _db.alertSeq,
      'txnId': txnId,
      'instrumentId': instrument['id'],
      'merchant': template.merchant,
      'amountPaise': template.amountPaise,
      'location': '${template.city}, ${template.country}',
      'at': iso(now),
      'riskReason':
          blocked
              ? 'Declined: this was tried on your blocked '
                  '${(instrument['label']! as String).toLowerCase()}. '
                  '${assessment.summary}'
              : assessment.summary,
      'riskLevel': assessment.level == 'LOW' ? 'MEDIUM' : assessment.level,
      'status': blocked ? 'INSTRUMENT_BLOCKED' : 'PENDING',
      'caseId': null,
      'actionedAt': null,
    };
    _db.alerts[alertId] = alert;
    _emitAlert(alert);
    return alertId;
  }

  // -------------------------------------------------------------------------
  // Instruments and transactions
  // -------------------------------------------------------------------------

  static const _blockReasons = {'LOST', 'STOLEN', 'SUSPICIOUS', 'TEMPORARY'};

  MockResponse _block(String id, String? reason) {
    final i = _db.instruments[id];
    if (i == null) return _notFound('instrument');
    if (reason == null || !_blockReasons.contains(reason)) {
      return _error(
        422,
        'INVALID_REASON',
        'Choose why you are blocking it.',
        details: {'reason': 'Choose a reason'},
      );
    }
    if (i['blocked'] == true) {
      return _error(
        409,
        'ALREADY_BLOCKED',
        '${_instrumentLabel(id)} is already blocked.',
        details: {'instrument': i},
      );
    }
    _doBlock(i, reason);
    return MockResponse(200, i);
  }

  void _doBlock(Map<String, Object?> instrument, String reason) {
    instrument['blocked'] = true;
    instrument['blockedAt'] = iso(now);
    instrument['blockReason'] = reason;
    blockActions++;
  }

  MockResponse _unblock(String id) {
    final i = _db.instruments[id];
    if (i == null) return _notFound('instrument');
    if (i['blocked'] != true) return MockResponse(200, i);
    if (i['blockReason'] == 'LOST' || i['blockReason'] == 'STOLEN') {
      return _error(
        409,
        'CANNOT_UNBLOCK',
        'An instrument reported lost or stolen can\'t be unblocked. Please '
            'ask for a replacement at your branch.',
      );
    }
    i['blocked'] = false;
    i['blockedAt'] = null;
    i['blockReason'] = null;
    return MockResponse(200, i);
  }

  MockResponse _listTransactions() {
    final items =
        _db.transactions.values.toList()
          ..sort((a, b) => _time(b, 'at').compareTo(_time(a, 'at')));
    return MockResponse(200, {
      'items': [
        for (final t in items)
          {
            ...t,
            'instrumentLabel': _instrumentLabel(t['instrumentId']! as String),
            'caseId': _caseIdForTxn(t['id']! as String),
          },
      ],
    });
  }

  String? _caseIdForTxn(String txnId) {
    for (final d in _db.disputes.values) {
      if (d['txnId'] == txnId && d['status'] == 'SUBMITTED') {
        return d['caseId'] as String?;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // Disputes
  // -------------------------------------------------------------------------

  DisputeContext _ctx(Map<String, Object?> txn) => DisputeContext(
    txnAmountPaise: txn['amountPaise']! as int,
    txnAt: _time(txn, 'at').toLocal(),
    today: now,
  );

  static Map<String, String> _answers(Object? raw) =>
      raw is Map
          ? raw.map((k, v) => MapEntry(k.toString(), v?.toString() ?? ''))
          : const {};

  Map<String, Object?> _newDispute({
    required Map<String, Object?> txn,
    required DisputeReason reason,
    required Map<String, String> answers,
    required String status,
  }) {
    final id = _db.newId('dsp');
    final dispute = <String, Object?>{
      'id': id,
      'txnId': txn['id'],
      'reason': reason.api,
      'answers': answers,
      'evidence': <Map<String, Object?>>[],
      'status': status,
      'disputedAmountPaise': DisputeRules.disputedAmountPaise(
        reason,
        txn['amountPaise']! as int,
        answers,
      ),
      'caseId': null,
      'createdAt': iso(now),
    };
    _db.disputes[id] = dispute;
    return dispute;
  }

  /// Shared checks for create and update. Returns an error, or null.
  MockResponse? _checkDispute(
    Map<String, Object?>? txn,
    DisputeReason? reason,
    Map<String, String> answers,
  ) {
    if (txn == null) {
      return _error(422, 'TXN_NOT_FOUND', 'We could not find that payment.');
    }
    if (reason == null) {
      return _error(
        422,
        'INVALID_REASON',
        'Choose what went wrong.',
        details: {'reason': 'Choose a reason'},
      );
    }
    final txnAt = _time(txn, 'at');
    if (!DisputeRules.isWithinWindow(txnAt, now)) {
      final age = DisputeRules.ageInDays(txnAt, now);
      return _error(
        422,
        'OUTSIDE_DISPUTE_WINDOW',
        'Disputes can be raised within ${DisputeRules.windowDays} days of a '
            'payment. This one is $age days old. Please call us on '
            '1800-123-4567 and we will help.',
      );
    }
    if (txn['status'] == 'DECLINED') {
      return _error(
        422,
        'NOTHING_TO_DISPUTE',
        'This payment was declined, so no money left your account.',
      );
    }
    final errors = DisputeRules.validate(reason, answers, _ctx(txn));
    if (errors.isNotEmpty) {
      return _error(
        422,
        'INVALID_ANSWERS',
        'Please check your answers.',
        details: errors,
      );
    }
    return null;
  }

  MockResponse _createDispute(Map<String, Object?> body) {
    final txn = _db.transactions[body['txnId']];
    final reason = DisputeReason.fromApi(body['reason'] as String?);
    final answers = _answers(body['answers']);
    final problem = _checkDispute(txn, reason, answers);
    if (problem != null) return problem;

    final existing = _caseIdForTxn(txn!['id']! as String);
    if (existing != null) {
      return _error(
        409,
        'DISPUTE_EXISTS',
        'There is already a case for this payment.',
        details: {'caseId': existing},
      );
    }
    final dispute = _newDispute(
      txn: txn,
      reason: reason!,
      answers: DisputeRules.cleanAnswers(reason, answers),
      status: 'DRAFT',
    );
    return MockResponse(201, dispute);
  }

  MockResponse _updateDispute(String id, Map<String, Object?> body) {
    final d = _db.disputes[id];
    if (d == null) return _notFound('dispute');
    if (d['status'] != 'DRAFT') {
      return _error(
        409,
        'ALREADY_SUBMITTED',
        'This dispute was already submitted.',
        details: {'caseId': d['caseId']},
      );
    }
    final txn = _db.transactions[d['txnId']];
    final reason = DisputeReason.fromApi(body['reason'] as String?);
    final answers = _answers(body['answers']);
    final problem = _checkDispute(txn, reason, answers);
    if (problem != null) return problem;

    final clean = DisputeRules.cleanAnswers(reason!, answers);
    d['reason'] = reason.api;
    d['answers'] = clean;
    d['disputedAmountPaise'] = DisputeRules.disputedAmountPaise(
      reason,
      txn!['amountPaise']! as int,
      clean,
    );
    return MockResponse(200, d);
  }

  Future<MockResponse> _uploadEvidence(String id, MockRequest req) async {
    final d = _db.disputes[id];
    if (d == null) return _notFound('dispute');
    final evidence = d['evidence']! as List<Map<String, Object?>>;
    final name = Uri.decodeComponent(req.header('x-file-name') ?? 'file');
    final mime = (req.header('content-type') ?? '').split(';').first.trim();
    final size = int.tryParse(req.header('content-length') ?? '') ?? 0;

    if (evidence.length >= EvidenceRules.maxFiles) {
      return _error(
        422,
        'TOO_MANY_FILES',
        'You can add up to ${EvidenceRules.maxFiles} files to a dispute.',
      );
    }
    if (!EvidenceRules.allowedMimeTypes.contains(mime)) {
      return _error(
        422,
        'UNSUPPORTED_FILE',
        'Only photos (JPG, PNG) and PDF files can be added.',
      );
    }
    // Rejected from the header, before reading the body, like a real server.
    if (size > EvidenceRules.maxBytes) {
      return _error(413, 'FILE_TOO_LARGE', '$name is larger than 5 MB.');
    }

    final received = await _receive(req, size);
    final file = <String, Object?>{
      'id': _db.newId('evd'),
      'name': name,
      'sizeBytes': received,
      'mimeType': mime,
      'uploadedAt': iso(now),
    };
    evidence.add(file);

    final caseId = d['caseId'] as String?;
    if (caseId != null) {
      _timelineOf(
        _db.cases[caseId]!,
      ).add(_entry(now, 'CUSTOMER', 'Evidence added', name));
    }
    return MockResponse(201, file);
  }

  /// Reads the upload like a slow mobile network. Chaos can cut the
  /// connection at 90% to demo "retry that file only".
  Future<int> _receive(MockRequest req, int expected) async {
    final body = req.body;
    if (body == null) return 0;
    final failAt90 = chaos.failNextUploadAt90;
    var received = 0;
    var sincePause = 0;
    await for (final chunk in body) {
      received += chunk.length;
      sincePause += chunk.length;
      if (failAt90 && expected > 0 && received >= expected * 0.9) {
        chaos.failNextUploadAt90 = false;
        throw const MockNetworkDown('The connection dropped during upload.');
      }
      if (sincePause >= 64 * 1024 && uploadDelayPer64Kb > Duration.zero) {
        sincePause = 0;
        await Future<void>.delayed(uploadDelayPer64Kb);
      }
    }
    return received;
  }

  MockResponse _submitDispute(String id) {
    final d = _db.disputes[id];
    if (d == null) return _notFound('dispute');
    if (d['status'] == 'SUBMITTED') {
      return _error(
        409,
        'ALREADY_SUBMITTED',
        'This dispute was already submitted.',
        details: {'caseId': d['caseId']},
      );
    }
    final txn = _db.transactions[d['txnId']]!;
    final reason = DisputeReason.fromApi(d['reason'] as String?)!;
    final problem = _checkDispute(txn, reason, _answers(d['answers']));
    if (problem != null) return problem;

    final existing = _caseIdForTxn(txn['id']! as String);
    if (existing != null) {
      return _error(
        409,
        'DISPUTE_EXISTS',
        'There is already a case for this payment.',
        details: {'caseId': existing},
      );
    }
    final evidence = d['evidence']! as List<Map<String, Object?>>;
    if (DisputeRules.evidenceRuleFor(reason) == EvidenceRule.required &&
        evidence.isEmpty) {
      return _error(
        422,
        'EVIDENCE_REQUIRED',
        'Please add at least one file as evidence for this kind of dispute.',
        details: {'evidence': 'Add at least one file'},
      );
    }

    d['status'] = 'SUBMITTED';
    final t = now;
    final c = _openCase(
      dispute: d,
      txn: txn,
      firstEntries: [
        _entry(t, 'CUSTOMER', 'You raised a dispute: ${_reasonTitle(reason)}'),
        if (evidence.isNotEmpty)
          _entry(
            t,
            'CUSTOMER',
            'Evidence added',
            evidence.map((e) => e['name']).join(', '),
          ),
      ],
    );
    return MockResponse(201, {'dispute': d, 'case': _caseJson(c)});
  }

  static String _reasonTitle(DisputeReason reason) => switch (reason) {
    DisputeReason.unauthorised => 'payment not made by you',
    DisputeReason.notReceived => 'item not received',
    DisputeReason.duplicate => 'charged twice',
    DisputeReason.wrongAmount => 'wrong amount charged',
  };

  // -------------------------------------------------------------------------
  // Cases and messages
  // -------------------------------------------------------------------------

  static const _conditions = [
    'The credit is provisional. It may be reversed if the investigation '
        'finds the payment was genuine.',
    'Please keep this account open while the case is in progress.',
    'A final decision will be made within 90 days.',
  ];

  Map<String, Object?> _openCase({
    required Map<String, Object?> dispute,
    required Map<String, Object?> txn,
    required List<Map<String, Object?>> firstEntries,
  }) {
    final t = now;
    final id = _db.newId('case');
    final instrumentType = _db.instruments[txn['instrumentId']]?['type'];
    final entries = [...firstEntries];
    var chargebackPending = false;

    // External systems are unreliable: the card network may be down. The
    // case still opens; the chargeback is raised later (partial result).
    if (instrumentType == 'CARD') {
      if (chaos.cardNetworkDown) {
        chargebackPending = true;
        entries.add(
          _entry(
            t,
            'NETWORK',
            'Card network not responding',
            'We will raise the chargeback automatically when it is back. '
                'Your case is safe.',
          ),
        );
      } else {
        entries.add(
          _entry(
            t,
            'NETWORK',
            'Chargeback raised with the card network',
            'Reference CBK-${_digits(5)}',
          ),
        );
      }
    } else if (instrumentType == 'UPI') {
      entries.add(
        _entry(
          t,
          'NETWORK',
          'Complaint registered with the UPI dispute system',
          'Reference UDR-${_digits(6)}',
        ),
      );
    }

    final c = <String, Object?>{
      'id': id,
      'caseNumber':
          'FS-${t.year}-${(_db.caseNumber++).toString().padLeft(6, '0')}',
      'disputeId': dispute['id'],
      'txnId': txn['id'],
      'merchant': txn['merchant'],
      'reason': dispute['reason'],
      'txnAmountPaise': txn['amountPaise'],
      'disputedAmountPaise': dispute['disputedAmountPaise'],
      'status': 'OPEN',
      'timeline': entries,
      'createdAt': iso(t),
      'slaDueAt': iso(t.add(const Duration(days: 10))),
      'provisionalCreditPaise': null,
      'provisionalCreditAt': null,
      'creditNote': null,
      'creditConditions': const <String>[],
      'autoProgress': true,
      'chargebackPending': chargebackPending,
    };
    _db.cases[id] = c;
    _db.messages[id] = [];
    dispute['caseId'] = id;
    return c;
  }

  List<Map<String, Object?>> _timelineOf(Map<String, Object?> c) =>
      c['timeline']! as List<Map<String, Object?>>;

  /// Moves new cases along based on their age. No timers needed, so it is
  /// deterministic in tests (they control the clock).
  void _progress(Map<String, Object?> c) {
    if (c['autoProgress'] != true) return;
    final created = _time(c, 'createdAt');
    final age = now.difference(created);
    final timeline = _timelineOf(c);

    if (c['chargebackPending'] == true && !chaos.cardNetworkDown) {
      c['chargebackPending'] = false;
      timeline.add(
        _entry(
          now,
          'NETWORK',
          'Chargeback raised with the card network',
          'Reference CBK-${_digits(5)}',
        ),
      );
    }
    if (c['status'] == 'OPEN' && age >= reviewAfter) {
      c['status'] = 'IN_REVIEW';
      final at = created.add(reviewAfter);
      timeline.add(_entry(at, 'BANK', 'Assigned to the disputes team'));
      _db.messages[c['id']]!.add({
        'id': _db.newId('msg'),
        'from': 'BANK',
        'text':
            'Hi ${(_db.customer['name']! as String).split(' ').first}, I\'m '
            'Arjun from the disputes team. I\'m looking into your case and '
            'will update you here.',
        'at': iso(at),
        'attachmentName': null,
      });
    }
    if (c['status'] == 'IN_REVIEW' &&
        c['provisionalCreditPaise'] == null &&
        age >= creditAfter) {
      final disputed = c['disputedAmountPaise']! as int;
      final credit = min(disputed, creditCapPaise);
      final at = created.add(creditAfter);
      c['status'] = 'CREDITED';
      c['provisionalCreditPaise'] = credit;
      c['provisionalCreditAt'] = iso(at);
      c['creditNote'] =
          credit < disputed
              ? 'Provisional credit is capped at ${Money.format(creditCapPaise)} '
                  'while the investigation is open.'
              : null;
      c['creditConditions'] = _conditions;
      timeline.add(
        _entry(
          at,
          'BANK',
          'Provisional credit of ${Money.format(credit)} given',
        ),
      );
    }
  }

  Map<String, Object?> _caseJson(Map<String, Object?> c) {
    final dispute = _db.disputes[c['disputeId']];
    final timeline = [..._timelineOf(c)]
      ..sort((a, b) => _time(a, 'at').compareTo(_time(b, 'at')));
    return {
      for (final e in c.entries)
        if (e.key != 'autoProgress' && e.key != 'chargebackPending')
          e.key: e.value,
      'timeline': timeline,
      'evidence': dispute?['evidence'] ?? const [],
      'messageCount': _db.messages[c['id']]?.length ?? 0,
    };
  }

  MockResponse _listCases() {
    final items = _db.cases.values.toList();
    for (final c in items) {
      _progress(c);
    }
    items.sort(
      (a, b) => _time(b, 'createdAt').compareTo(_time(a, 'createdAt')),
    );
    return MockResponse(200, {
      'items': [for (final c in items) _caseJson(c)],
    });
  }

  MockResponse _getCase(String id) {
    final c = _db.cases[id];
    if (c == null) return _notFound('case');
    _progress(c);
    return MockResponse(200, _caseJson(c));
  }

  MockResponse _listMessages(String caseId, MockRequest req) {
    final c = _db.cases[caseId];
    if (c == null) return _notFound('case');
    _progress(c);
    final q = req.uri.queryParameters;
    final limit = (int.tryParse(q['limit'] ?? '') ?? 15).clamp(1, 50);
    final offset = int.tryParse(q['cursor'] ?? '') ?? 0;
    final newestFirst = [..._db.messages[caseId]!]
      ..sort((a, b) => _time(b, 'at').compareTo(_time(a, 'at')));
    final page = newestFirst.skip(offset).take(limit).toList();
    final end = offset + page.length;
    return MockResponse(200, {
      'items': page,
      'nextCursor': end < newestFirst.length ? '$end' : null,
    });
  }

  MockResponse _postMessage(String caseId, Map<String, Object?> body) {
    final c = _db.cases[caseId];
    if (c == null) return _notFound('case');
    final text = (body['text'] as String? ?? '').trim();
    if (text.isEmpty || text.length > 1000) {
      return _error(
        422,
        'INVALID_MESSAGE',
        text.isEmpty ? 'Type a message.' : 'Keep it under 1000 characters.',
        details: {'text': text.isEmpty ? 'Type a message' : 'Too long'},
      );
    }
    final t = now;
    final message = <String, Object?>{
      'id': _db.newId('msg'),
      'from': 'CUSTOMER',
      'text': text,
      'at': iso(t),
      'attachmentName': body['attachmentName'] as String?,
    };
    final thread = _db.messages[caseId]!..add(message);

    final met =
        c['provisionalCreditPaise'] != null ||
        c['status'] == 'RESOLVED' ||
        c['status'] == 'REJECTED';
    final breached = !met && _time(c, 'slaDueAt').isBefore(t);
    if (breached && c['escalated'] != true) {
      c['escalated'] = true;
      _timelineOf(c).add(
        _entry(
          t,
          'BANK',
          'Escalated to a senior disputes officer',
          'The decision is overdue, so your case now has priority.',
        ),
      );
    }
    thread.add({
      'id': _db.newId('msg'),
      'from': 'BANK',
      'text':
          breached
              ? 'We are sorry this is taking longer than promised. Your case has '
                  'been escalated to a senior disputes officer, who will reply '
                  'within 24 hours.'
              : 'Thanks, we have added this to your case. We usually reply '
                  'within 24 hours.',
      'at': iso(t.add(const Duration(seconds: 1))),
      'attachmentName': null,
    });
    return MockResponse(201, message);
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  Map<String, Object?> _entry(
    DateTime at,
    String actor,
    String title, [
    String? detail,
  ]) => {'at': iso(at), 'actor': actor, 'title': title, 'detail': detail};

  static DateTime _time(Map<String, Object?> m, String key) =>
      DateTime.parse(m[key]! as String);

  String _hex(int length) =>
      List.generate(
        length,
        (_) => _random.nextInt(16).toRadixString(16),
      ).join();

  String _digits(int length) =>
      List.generate(length, (_) => _random.nextInt(10)).join();

  MockResponse _error(
    int status,
    String code,
    String message, {
    Map<String, Object?>? details,
  }) => MockResponse(status, {
    'error': {
      'code': code,
      'message': message,
      'details': details ?? const <String, Object?>{},
      'traceId': 'trc-${(_traceSeq++).toString().padLeft(6, '0')}',
    },
  });

  MockResponse _notFound(String what) =>
      _error(404, 'NOT_FOUND', 'We could not find that $what.');
}

/// One open live connection (Server-Sent Events).
class _SseConnection {
  _SseConnection(this._controller, {required this.onClosed});

  final StreamController<Uint8List> _controller;
  final void Function() onClosed;
  Timer? _heartbeat;
  bool _closed = false;

  void startHeartbeat(Duration? every) {
    if (every == null) return;
    _heartbeat = Timer.periodic(every, (_) => _write(': ping\n\n'));
  }

  void sendEvent(int id, String type, Object? data) =>
      _write('id: $id\nevent: $type\ndata: ${jsonEncode(data)}\n\n');

  void _write(String text) {
    if (_closed || _controller.isClosed) return;
    _controller.add(Uint8List.fromList(utf8.encode(text)));
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _heartbeat?.cancel();
    onClosed();
    if (!_controller.isClosed) unawaited(_controller.close());
  }
}
