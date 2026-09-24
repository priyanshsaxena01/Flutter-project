/// In-memory tables of the pretend bank. Records are JSON-shaped maps,
/// exactly what a real server would store and send.
class MockDb {
  Map<String, Object?> customer = const {};
  final instruments = <String, Map<String, Object?>>{};
  final transactions = <String, Map<String, Object?>>{};
  final alerts = <String, Map<String, Object?>>{};
  final disputes = <String, Map<String, Object?>>{};
  final cases = <String, Map<String, Object?>>{};
  final messages = <String, List<Map<String, Object?>>>{};
  final devices = <String, Map<String, Object?>>{};
  final logins = <Map<String, Object?>>[];

  /// Append-only action log (Auditability NFR). Nothing ever edits it.
  final audit = <Map<String, Object?>>[];

  int alertSeq = 0;
  int caseNumber = 500;
  int _nextId = 5000;

  String newId(String prefix) => '${prefix}_${_nextId++}';
}

String iso(DateTime d) => d.toUtc().toIso8601String();

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Demo data, relative to [now], so the demo always looks recent.
///
/// Designed to show every state: two alerts waiting, one blocked card,
/// a case with partial provisional credit, one in its last 2 days (amber),
/// one past its SLA (red), one resolved, and a transaction too old to
/// dispute.
void seedDemoData(MockDb db, DateTime now) {
  DateTime ago({int days = 0, int hours = 0, int minutes = 0}) =>
      now.subtract(Duration(days: days, hours: hours, minutes: minutes));

  db.customer = {
    'id': 'TEST_CUSTOM',
    'name': 'Priyansh Saxena',
    'pin': '0123456789',
    'homeCity': 'Pune',
    'homeCountry': 'IN',
    'averageSpendPaise': 180000,
  };

  void instrument(
    String id,
    String type,
    String label,
    String masked, {
    DateTime? blockedAt,
    String? reason,
  }) {
    db.instruments[id] = {
      'id': id,
      'type': type,
      'label': label,
      'masked': masked,
      'blocked': blockedAt != null,
      'blockedAt': blockedAt == null ? null : iso(blockedAt),
      'blockReason': reason,
    };
  }

  instrument(
    'ins_debit',
    'CARD',
    'Debit card',
    '•• 4821',
    blockedAt: ago(days: 4, hours: 2),
    reason: 'SUSPICIOUS',
  );
  instrument('ins_credit', 'CARD', 'Credit card', '•• 7710');
  instrument('ins_upi', 'UPI', 'UPI', 'pri***@fsbank');
  instrument('ins_netbanking', 'NETBANKING', 'Net banking', 'User ID ••STOM');

  void txn(
    String id,
    String instrumentId,
    String merchant,
    String category,
    int amountPaise,
    String location,
    DateTime at,
  ) {
    db.transactions[id] = {
      'id': id,
      'instrumentId': instrumentId,
      'merchant': merchant,
      'category': category,
      'amountPaise': amountPaise,
      'location': location,
      'at': iso(at),
      'status': 'SUCCESS',
    };
  }

  txn(
    'txn_3001',
    'ins_credit',
    'BigBasket',
    'groceries',
    184500,
    'Pune, IN',
    ago(days: 1),
  );
  txn(
    'txn_3002',
    'ins_upi',
    'Chai Point',
    'food',
    12000,
    'Pune, IN',
    ago(days: 1, hours: 3),
  );
  txn(
    'txn_3003',
    'ins_credit',
    'Electro World',
    'electronics',
    499900,
    'Dubai, AE',
    ago(minutes: 35),
  );
  txn(
    'txn_3004',
    'ins_upi',
    'QuickPay Wallet',
    'wallet top-up',
    1500000,
    'Mumbai, IN',
    ago(hours: 3),
  );
  txn(
    'txn_3005',
    'ins_credit',
    'Amazon',
    'shopping',
    234900,
    'Pune, IN',
    ago(days: 2),
  );
  txn(
    'txn_3006',
    'ins_credit',
    'StyleHub Fashion',
    'shopping',
    234900,
    'Online',
    ago(days: 25),
  );
  txn(
    'txn_3007',
    'ins_debit',
    'QuickKart Online',
    'shopping',
    1250000,
    'Online',
    ago(days: 4, hours: 3),
  );
  txn(
    'txn_3008',
    'ins_upi',
    'Metro Cafe',
    'food',
    64000,
    'Pune, IN',
    ago(days: 13, hours: 1),
  );
  txn(
    'txn_3009',
    'ins_upi',
    'Metro Cafe',
    'food',
    64000,
    'Pune, IN',
    ago(days: 13, hours: 1, minutes: 2),
  );
  txn(
    'txn_3010',
    'ins_credit',
    'CityCabs',
    'travel',
    118000,
    'Pune, IN',
    ago(days: 40),
  );
  txn(
    'txn_3011',
    'ins_debit',
    'Swiggy',
    'food',
    45600,
    'Pune, IN',
    ago(days: 5),
  );
  txn(
    'txn_3012',
    'ins_credit',
    'TravelNest Hotels',
    'travel',
    890000,
    'Goa, IN',
    ago(days: 120),
  );
  txn(
    'txn_3013',
    'ins_debit',
    'Decathlon',
    'sports',
    329900,
    'Pune, IN',
    ago(days: 20),
  );
  txn(
    'txn_3014',
    'ins_upi',
    'MSEDCL Electricity',
    'bills',
    156000,
    'Pune, IN',
    ago(days: 25),
  );

  void alert(
    String id,
    String txnId,
    String level,
    String reason,
    String status, {
    String? caseId,
    DateTime? actionedAt,
  }) {
    final t = db.transactions[txnId]!;
    db.alertSeq++;
    db.alerts[id] = {
      'id': id,
      'seq': db.alertSeq,
      'txnId': txnId,
      'instrumentId': t['instrumentId'],
      'merchant': t['merchant'],
      'amountPaise': t['amountPaise'],
      'location': t['location'],
      'at': t['at'],
      'riskReason': reason,
      'riskLevel': level,
      'status': status,
      'caseId': caseId,
      'actionedAt': actionedAt == null ? null : iso(actionedAt),
    };
  }

  alert(
    'alt_1001',
    'txn_3005',
    'MEDIUM',
    '₹2,349 is higher than your usual online spend.',
    'CONFIRMED',
    actionedAt: ago(days: 2, minutes: -5),
  );
  alert(
    'alt_1002',
    'txn_3007',
    'HIGH',
    'First payment to QuickKart Online. ₹12,500 is 6x your usual spend.',
    'DENIED',
    caseId: 'case_481',
    actionedAt: ago(days: 4, hours: 2),
  );
  alert(
    'alt_1003',
    'txn_3004',
    'MEDIUM',
    'High-risk merchant type: wallet top-up. ₹15,000 is 8x your usual spend.',
    'PENDING',
  );
  alert(
    'alt_1004',
    'txn_3003',
    'HIGH',
    'Unusual location: Dubai, AE. Your credit card is normally used in Pune.',
    'PENDING',
  );

  Map<String, Object?> entry(
    DateTime at,
    String actor,
    String title, [
    String? detail,
  ]) => {'at': iso(at), 'actor': actor, 'title': title, 'detail': detail};

  Map<String, Object?> file(
    String id,
    String name,
    int size,
    String mime,
    DateTime at,
  ) => {
    'id': id,
    'name': name,
    'sizeBytes': size,
    'mimeType': mime,
    'uploadedAt': iso(at),
  };

  void disputeCase({
    required String id,
    required String number,
    required String txnId,
    required String reason,
    required Map<String, String> answers,
    required int disputedPaise,
    required DateTime createdAt,
    required String status,
    required List<Map<String, Object?>> timeline,
    List<Map<String, Object?>> evidence = const [],
    int? creditPaise,
    DateTime? creditAt,
    String? creditNote,
    List<String> conditions = const [],
  }) {
    final t = db.transactions[txnId]!;
    final disputeId = id.replaceFirst('case_', 'dsp_');
    db.disputes[disputeId] = {
      'id': disputeId,
      'txnId': txnId,
      'reason': reason,
      'answers': answers,
      // Growable copies: evidence can be added to a case later.
      'evidence': [...evidence],
      'status': 'SUBMITTED',
      'disputedAmountPaise': disputedPaise,
      'caseId': id,
      'createdAt': iso(createdAt),
    };
    db.cases[id] = {
      'id': id,
      'caseNumber': number,
      'disputeId': disputeId,
      'txnId': txnId,
      'merchant': t['merchant'],
      'reason': reason,
      'txnAmountPaise': t['amountPaise'],
      'disputedAmountPaise': disputedPaise,
      'status': status,
      'timeline': [...timeline],
      'createdAt': iso(createdAt),
      'slaDueAt': iso(createdAt.add(const Duration(days: 10))),
      'provisionalCreditPaise': creditPaise,
      'provisionalCreditAt': creditAt == null ? null : iso(creditAt),
      'creditNote': creditNote,
      'creditConditions': conditions,
      'autoProgress': false,
      'chargebackPending': false,
    };
  }

  const standardConditions = [
    'The credit is provisional. It may be reversed if the investigation '
        'finds the payment was genuine.',
    'Please keep this account open while the case is in progress.',
    'A final decision will be made within 90 days.',
  ];

  // Case 1: unauthorised, partial provisional credit (shows the difference).
  final c1 = ago(days: 4, hours: 2);
  disputeCase(
    id: 'case_481',
    number: 'FS-${now.year}-000481',
    txnId: 'txn_3007',
    reason: 'UNAUTHORISED',
    answers: {'instrumentWithYou': 'yes', 'sharedOtp': 'no'},
    disputedPaise: 1250000,
    createdAt: c1,
    status: 'CREDITED',
    timeline: [
      entry(
        c1,
        'CUSTOMER',
        'You reported this payment as not made by you',
        'From the alert for QuickKart Online',
      ),
      entry(c1, 'SYSTEM', 'Debit card •• 4821 blocked'),
      entry(
        c1.add(const Duration(minutes: 5)),
        'NETWORK',
        'Chargeback raised with the card network',
        'Reference CBK-88213',
      ),
      entry(ago(days: 3), 'BANK', 'Assigned to the disputes team'),
      entry(
        ago(days: 1),
        'BANK',
        'Provisional credit of ₹10,000.00 given',
        'Credited to your savings account',
      ),
    ],
    creditPaise: 1000000,
    creditAt: ago(days: 1),
    creditNote:
        'Provisional credit is capped at ₹10,000 while the '
        'investigation is open. The rest follows if the claim succeeds.',
    conditions: standardConditions,
  );

  // Case 2: not received, in its last 2 days (amber), long message thread.
  final c2 = ago(days: 8, hours: 12);
  disputeCase(
    id: 'case_462',
    number: 'FS-${now.year}-000462',
    txnId: 'txn_3006',
    reason: 'NOT_RECEIVED',
    answers: {
      'itemDescription': 'Blue denim jacket, size M',
      'expectedBy': isoDay(ago(days: 18)),
      'contactedMerchant': 'yes',
      'merchantResponse': 'They stopped replying after promising a refund.',
    },
    disputedPaise: 234900,
    createdAt: c2,
    status: 'IN_REVIEW',
    evidence: [
      file('evd_1', 'order_confirmation.png', 1258291, 'image/png', c2),
      file('evd_2', 'chat_with_seller.jpg', 2202009, 'image/jpeg', c2),
    ],
    timeline: [
      entry(c2, 'CUSTOMER', 'You raised a dispute: item not received'),
      entry(
        c2,
        'CUSTOMER',
        'Evidence added',
        'order_confirmation.png, chat_with_seller.jpg',
      ),
      entry(
        c2.add(const Duration(minutes: 3)),
        'NETWORK',
        'Chargeback raised with the card network',
        'Reference CBK-87544',
      ),
      entry(ago(days: 7), 'BANK', 'Assigned to the disputes team'),
      entry(
        ago(days: 5),
        'BANK',
        'Merchant asked for proof of delivery',
        'The merchant has 7 days to respond.',
      ),
    ],
  );

  // Case 3: duplicate UPI charge, SLA breached (red + escalation path).
  final c3 = ago(days: 13);
  disputeCase(
    id: 'case_437',
    number: 'FS-${now.year}-000437',
    txnId: 'txn_3008',
    reason: 'DUPLICATE',
    answers: {
      'sameOrder': 'yes',
      'originalDate': isoDay(ago(days: 13, hours: 1)),
    },
    disputedPaise: 64000,
    createdAt: c3,
    status: 'IN_REVIEW',
    timeline: [
      entry(c3, 'CUSTOMER', 'You raised a dispute: charged twice'),
      entry(
        c3.add(const Duration(minutes: 2)),
        'NETWORK',
        'Complaint registered with the UPI dispute system',
        'Reference UDR-551902',
      ),
      entry(
        ago(days: 9),
        'BANK',
        'Waiting for the merchant\'s bank to respond',
      ),
    ],
  );

  // Case 4: wrong amount, resolved; credit matches the disputed amount.
  final c4 = ago(days: 39);
  disputeCase(
    id: 'case_402',
    number: 'FS-${now.year}-000402',
    txnId: 'txn_3010',
    reason: 'WRONG_AMOUNT',
    answers: {'agreedAmount': '980', 'billAvailable': 'yes'},
    disputedPaise: 20000,
    createdAt: c4,
    status: 'RESOLVED',
    evidence: [file('evd_3', 'cab_receipt.pdf', 245760, 'application/pdf', c4)],
    timeline: [
      entry(c4, 'CUSTOMER', 'You raised a dispute: wrong amount charged'),
      entry(c4, 'CUSTOMER', 'Evidence added', 'cab_receipt.pdf'),
      entry(ago(days: 35), 'BANK', 'Provisional credit of ₹200.00 given'),
      entry(
        ago(days: 30),
        'BANK',
        'Resolved in your favour',
        'The merchant agreed the fare was ₹980. The ₹200.00 credit is now permanent.',
      ),
    ],
    creditPaise: 20000,
    creditAt: ago(days: 35),
    creditNote: 'This credit is now permanent.',
  );

  // Messages. Case 2 has a long thread to show paging.
  const thread = [
    (
      'BANK',
      'Hi Priyansh, I\'m Arjun from the disputes team. I\'ll be handling your case.',
    ),
    (
      'CUSTOMER',
      'Thanks Arjun. The jacket never arrived and the seller stopped replying.',
    ),
    (
      'BANK',
      'Understood. Could you confirm the delivery address on the order?',
    ),
    ('CUSTOMER', 'It\'s my home address in Pune, the same as on my account.'),
    (
      'BANK',
      'Thanks. We have asked the merchant\'s bank for proof of delivery.',
    ),
    ('CUSTOMER', 'How long does that usually take?'),
    ('BANK', 'The merchant has 7 days to respond. We\'ll update you here.'),
    ('CUSTOMER', 'Okay. The tracking page still says "in transit".'),
    (
      'BANK',
      'That helps. Please add a screenshot of the tracking page if you can.',
    ),
    ('CUSTOMER', 'I\'ve added the chat with the seller to the case.'),
    ('BANK', 'Got it, thank you. It\'s attached to the case now.'),
    ('CUSTOMER', 'Will I get the money back before the festival sale ends?'),
    (
      'BANK',
      'We aim to decide on provisional credit within 10 days of opening the case.',
    ),
    ('CUSTOMER', 'Thanks. Is there anything else you need from me?'),
    ('BANK', 'Not right now. We\'re waiting on the merchant\'s reply.'),
    ('CUSTOMER', 'The seller\'s website is down now too.'),
    ('BANK', 'Noted. That strengthens your case; I\'ve added it to the file.'),
    ('CUSTOMER', 'Should I file a police complaint as well?'),
    ('BANK', 'It isn\'t required for this dispute, but you may if you wish.'),
    ('CUSTOMER', 'Okay, I\'ll wait for your update.'),
    ('BANK', 'The merchant\'s deadline to respond passes tomorrow.'),
    ('CUSTOMER', 'Thank you for keeping me posted.'),
    ('BANK', 'You\'re welcome. We\'ll message you as soon as we decide.'),
    ('CUSTOMER', 'Great, thanks Arjun.'),
  ];
  var msgAt = c2.add(const Duration(hours: 2));
  var n = 0;
  db.messages['case_462'] = [
    for (final (from, text) in thread)
      {
        'id': 'msg_462_${n++}',
        'from': from,
        'text': text,
        'at': iso(msgAt = msgAt.add(const Duration(hours: 7))),
        'attachmentName':
            text.contains('added the chat') ? 'chat_with_seller.jpg' : null,
      },
  ];
  db.messages['case_481'] = [
    {
      'id': 'msg_481_1',
      'from': 'BANK',
      'text':
          'We have given you ₹10,000.00 as provisional credit while we investigate.',
      'at': iso(ago(days: 1)),
      'attachmentName': null,
    },
  ];
  db.messages['case_437'] = [
    {
      'id': 'msg_437_1',
      'from': 'BANK',
      'text':
          'We are still waiting for the merchant\'s bank. Sorry for the delay.',
      'at': iso(ago(days: 4)),
      'attachmentName': null,
    },
  ];
  db.messages['case_402'] = [];

  db.devices['dev_pixel'] = {
    'id': 'dev_pixel',
    'name': 'Pixel 7 · FraudShield app',
    'location': 'Pune, IN',
    'lastSeen': iso(ago(hours: 2)),
  };
  db.devices['dev_ipad'] = {
    'id': 'dev_ipad',
    'name': 'iPad Air · FraudShield app',
    'location': 'Mumbai, IN',
    'lastSeen': iso(ago(days: 6)),
  };

  db.logins.addAll([
    {
      'at': iso(ago(days: 6)),
      'deviceName': 'iPad Air · FraudShield app',
      'location': 'Mumbai, IN',
      'success': true,
    },
    {
      'at': iso(ago(days: 3, minutes: 1)),
      'deviceName': 'Windows PC · browser',
      'location': 'Lagos, NG',
      'success': false,
    },
    {
      'at': iso(ago(days: 3)),
      'deviceName': 'Windows PC · browser',
      'location': 'Lagos, NG',
      'success': false,
    },
    {
      'at': iso(ago(days: 1)),
      'deviceName': 'Pixel 7 · FraudShield app',
      'location': 'Pune, IN',
      'success': true,
    },
    {
      'at': iso(ago(hours: 2)),
      'deviceName': 'Pixel 7 · FraudShield app',
      'location': 'Pune, IN',
      'success': true,
    },
  ]);
}
