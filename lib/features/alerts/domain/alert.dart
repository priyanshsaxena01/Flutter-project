/// A transaction the bank's fraud engine flagged as unusual (F1).
class Alert {
  const Alert({
    required this.id,
    required this.seq,
    required this.txnId,
    required this.instrumentId,
    required this.instrumentLabel,
    required this.merchant,
    required this.amountPaise,
    required this.location,
    required this.at,
    required this.riskReason,
    required this.riskLevel,
    required this.status,
    this.caseId,
    this.actionedAt,
  });

  factory Alert.fromJson(Map<String, Object?> json) {
    return Alert(
      id: json['id']! as String,
      seq: (json['seq'] as num?)?.toInt() ?? 0,
      txnId: json['txnId']! as String,
      instrumentId: json['instrumentId']! as String,
      instrumentLabel: json['instrumentLabel'] as String? ?? '',
      merchant: json['merchant']! as String,
      amountPaise: (json['amountPaise']! as num).toInt(),
      location: json['location'] as String? ?? '',
      at: DateTime.parse(json['at']! as String).toLocal(),
      riskReason: json['riskReason'] as String? ?? '',
      riskLevel: RiskLevel.fromApi(json['riskLevel'] as String?),
      status: AlertStatus.fromApi(json['status'] as String?),
      caseId: json['caseId'] as String?,
      actionedAt:
          json['actionedAt'] == null
              ? null
              : DateTime.parse(json['actionedAt']! as String).toLocal(),
    );
  }

  final String id;

  /// Increasing number; the newest alert has the highest seq.
  final int seq;
  final String txnId;
  final String instrumentId;

  /// e.g. "Credit card •• 7710"
  final String instrumentLabel;
  final String merchant;
  final int amountPaise;
  final String location;
  final DateTime at;
  final String riskReason;
  final RiskLevel riskLevel;
  final AlertStatus status;
  final String? caseId;
  final DateTime? actionedAt;

  bool get needsAction => status == AlertStatus.pending;
}

enum AlertStatus {
  pending('PENDING'),
  confirmed('CONFIRMED'),
  denied('DENIED'),

  /// The payment was attempted on an instrument that was already blocked.
  instrumentBlocked('INSTRUMENT_BLOCKED');

  const AlertStatus(this.api);

  final String api;

  static AlertStatus fromApi(String? value) => AlertStatus.values.firstWhere(
    (s) => s.api == value,
    orElse: () => AlertStatus.pending,
  );
}

enum RiskLevel {
  high('HIGH', 'High risk'),
  medium('MEDIUM', 'Medium risk'),
  low('LOW', 'Low risk');

  const RiskLevel(this.api, this.label);

  final String api;
  final String label;

  static RiskLevel fromApi(String? value) => RiskLevel.values.firstWhere(
    (r) => r.api == value,
    orElse: () => RiskLevel.medium,
  );
}

/// What POST /alerts/{id}/deny returns: the card is blocked and a case is
/// open, in one call.
class DenyResult {
  const DenyResult({
    required this.alert,
    required this.instrumentLabel,
    required this.caseId,
    required this.caseNumber,
    required this.disputeId,
    this.alreadyDone = false,
  });

  final Alert alert;
  final String instrumentLabel;
  final String caseId;
  final String caseNumber;
  final String disputeId;

  /// true when the server said it had already been denied (409). The user
  /// sees the same outcome: blocked, case open.
  final bool alreadyDone;
}

/// Shared list rules, kept here so they are unit-tested.
class AlertRules {
  const AlertRules._();

  /// Newest first; keeps one copy per id (the stream can repeat an alert).
  static List<Alert> merge(List<Alert> current, Iterable<Alert> incoming) {
    final byId = {for (final a in current) a.id: a};
    for (final a in incoming) {
      byId[a.id] = a;
    }
    final list = byId.values.toList()..sort((a, b) => b.seq.compareTo(a.seq));
    return list;
  }

  /// Unread = needs the user's attention and was not opened yet.
  static int unreadCount(List<Alert> alerts, Set<String> readIds) =>
      alerts
          .where(
            (a) =>
                !readIds.contains(a.id) &&
                (a.status == AlertStatus.pending ||
                    a.status == AlertStatus.instrumentBlocked),
          )
          .length;
}
