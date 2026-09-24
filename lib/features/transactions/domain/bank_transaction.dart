/// A card or UPI payment the customer can dispute.
class BankTransaction {
  const BankTransaction({
    required this.id,
    required this.instrumentId,
    required this.instrumentLabel,
    required this.merchant,
    required this.amountPaise,
    required this.at,
    required this.location,
    required this.declined,
    this.caseId,
  });

  factory BankTransaction.fromJson(Map<String, Object?> json) {
    return BankTransaction(
      id: json['id']! as String,
      instrumentId: json['instrumentId']! as String,
      instrumentLabel: json['instrumentLabel'] as String? ?? '',
      merchant: json['merchant']! as String,
      amountPaise: (json['amountPaise']! as num).toInt(),
      at: DateTime.parse(json['at']! as String).toLocal(),
      location: json['location'] as String? ?? '',
      declined: json['status'] == 'DECLINED',
      caseId: json['caseId'] as String?,
    );
  }

  final String id;
  final String instrumentId;
  final String instrumentLabel;
  final String merchant;
  final int amountPaise;
  final DateTime at;
  final String location;

  /// Declined payments moved no money and cannot be disputed.
  final bool declined;

  /// Set when a dispute case already exists for this transaction.
  final String? caseId;
}
