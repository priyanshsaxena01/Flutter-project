/// A card, UPI ID or net banking login that can be blocked (F3).
class Instrument {
  const Instrument({
    required this.id,
    required this.type,
    required this.label,
    required this.masked,
    required this.blocked,
    this.blockedAt,
    this.blockReason,
  });

  factory Instrument.fromJson(Map<String, Object?> json) {
    return Instrument(
      id: json['id']! as String,
      type: InstrumentType.fromApi(json['type'] as String?),
      label: json['label']! as String,
      masked: json['masked']! as String,
      blocked: json['blocked'] as bool? ?? false,
      blockedAt:
          json['blockedAt'] == null
              ? null
              : DateTime.parse(json['blockedAt']! as String).toLocal(),
      blockReason:
          json['blockReason'] == null
              ? null
              : BlockReason.fromApi(json['blockReason'] as String?),
    );
  }

  final String id;
  final InstrumentType type;

  /// "Debit card", "UPI", "Net banking"
  final String label;

  /// "•• 4821", "pri***@fsbank"
  final String masked;
  final bool blocked;
  final DateTime? blockedAt;
  final BlockReason? blockReason;

  String get displayName => '$label $masked';
}

enum InstrumentType {
  card('CARD'),
  upi('UPI'),
  netBanking('NETBANKING');

  const InstrumentType(this.api);

  final String api;

  static InstrumentType fromApi(String? value) => InstrumentType.values
      .firstWhere((t) => t.api == value, orElse: () => InstrumentType.card);
}

enum BlockReason {
  lost('LOST', 'Lost', 'I can\'t find it'),
  stolen('STOLEN', 'Stolen', 'Someone took it'),
  suspicious('SUSPICIOUS', 'Suspicious activity', 'Payments I didn\'t make'),
  temporary('TEMPORARY', 'Just for now', 'Pause it; I may unblock later');

  const BlockReason(this.api, this.label, this.description);

  final String api;
  final String label;
  final String description;

  /// Lost or stolen instruments are replaced, never unblocked.
  bool get canUnblock => this == suspicious || this == temporary;

  static BlockReason fromApi(String? value) => BlockReason.values.firstWhere(
    (r) => r.api == value,
    orElse: () => BlockReason.suspicious,
  );
}
