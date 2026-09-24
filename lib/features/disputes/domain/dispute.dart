/// The four reasons a customer can dispute a transaction (F4).
enum DisputeReason {
  unauthorised(
    'UNAUTHORISED',
    'I didn\'t make this payment',
    'Someone used my card or UPI without permission',
  ),
  notReceived(
    'NOT_RECEIVED',
    'I paid but didn\'t receive it',
    'The product or service never arrived',
  ),
  duplicate(
    'DUPLICATE',
    'I was charged twice',
    'The same purchase was charged more than once',
  ),
  wrongAmount(
    'WRONG_AMOUNT',
    'I was charged the wrong amount',
    'The amount is different from what I agreed to pay',
  );

  const DisputeReason(this.api, this.label, this.description);

  final String api;
  final String label;
  final String description;

  static DisputeReason? fromApi(String? value) {
    for (final r in DisputeReason.values) {
      if (r.api == value) return r;
    }
    return null;
  }
}

class EvidenceFile {
  const EvidenceFile({
    required this.id,
    required this.name,
    required this.sizeBytes,
    required this.mimeType,
    required this.uploadedAt,
  });

  factory EvidenceFile.fromJson(Map<String, Object?> json) {
    return EvidenceFile(
      id: json['id']! as String,
      name: json['name']! as String,
      sizeBytes: (json['sizeBytes']! as num).toInt(),
      mimeType: json['mimeType'] as String? ?? '',
      uploadedAt: DateTime.parse(json['uploadedAt']! as String).toLocal(),
    );
  }

  final String id;
  final String name;
  final int sizeBytes;
  final String mimeType;
  final DateTime uploadedAt;
}

enum DisputeStatus {
  draft('DRAFT'),
  submitted('SUBMITTED');

  const DisputeStatus(this.api);

  final String api;

  static DisputeStatus fromApi(String? value) =>
      value == 'SUBMITTED' ? DisputeStatus.submitted : DisputeStatus.draft;
}

class Dispute {
  const Dispute({
    required this.id,
    required this.txnId,
    required this.reason,
    required this.answers,
    required this.evidence,
    required this.status,
    required this.disputedAmountPaise,
    this.caseId,
  });

  factory Dispute.fromJson(Map<String, Object?> json) {
    final rawAnswers = json['answers'];
    final rawEvidence = json['evidence'];
    return Dispute(
      id: json['id']! as String,
      txnId: json['txnId']! as String,
      reason:
          DisputeReason.fromApi(json['reason'] as String?) ??
          DisputeReason.unauthorised,
      answers:
          rawAnswers is Map
              ? rawAnswers.map((k, v) => MapEntry(k.toString(), v.toString()))
              : const {},
      evidence:
          rawEvidence is List
              ? [
                for (final e in rawEvidence)
                  if (e is Map<String, Object?>) EvidenceFile.fromJson(e),
              ]
              : const [],
      status: DisputeStatus.fromApi(json['status'] as String?),
      disputedAmountPaise: (json['disputedAmountPaise'] as num?)?.toInt() ?? 0,
      caseId: json['caseId'] as String?,
    );
  }

  final String id;
  final String txnId;
  final DisputeReason reason;
  final Map<String, String> answers;
  final List<EvidenceFile> evidence;
  final DisputeStatus status;
  final int disputedAmountPaise;
  final String? caseId;
}
