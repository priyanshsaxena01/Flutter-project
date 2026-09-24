import 'package:fraud_shield/features/disputes/domain/dispute.dart';

enum CaseStatus {
  open('OPEN', 'Case opened'),
  inReview('IN_REVIEW', 'Under review'),
  credited('CREDITED', 'Provisional credit given'),
  resolved('RESOLVED', 'Resolved in your favour'),
  rejected('REJECTED', 'Closed');

  const CaseStatus(this.api, this.label);

  final String api;
  final String label;

  bool get isClosed => this == resolved || this == rejected;

  static CaseStatus fromApi(String? value) => CaseStatus.values.firstWhere(
    (s) => s.api == value,
    orElse: () => CaseStatus.open,
  );
}

enum TimelineActor {
  customer('CUSTOMER'),
  bank('BANK'),
  system('SYSTEM'),
  network('NETWORK');

  const TimelineActor(this.api);

  final String api;

  static TimelineActor fromApi(String? value) => TimelineActor.values
      .firstWhere((a) => a.api == value, orElse: () => TimelineActor.system);
}

/// One step on the case's auditable trail.
class TimelineEntry {
  const TimelineEntry({
    required this.at,
    required this.title,
    required this.actor,
    this.detail,
  });

  factory TimelineEntry.fromJson(Map<String, Object?> json) => TimelineEntry(
    at: DateTime.parse(json['at']! as String).toLocal(),
    title: json['title']! as String,
    detail: json['detail'] as String?,
    actor: TimelineActor.fromApi(json['actor'] as String?),
  );

  final DateTime at;
  final String title;
  final String? detail;
  final TimelineActor actor;
}

/// A dispute case with its SLA and timeline (F6, F7).
class DisputeCase {
  const DisputeCase({
    required this.id,
    required this.caseNumber,
    required this.disputeId,
    required this.txnId,
    required this.merchant,
    required this.reason,
    required this.txnAmountPaise,
    required this.disputedAmountPaise,
    required this.status,
    required this.timeline,
    required this.createdAt,
    required this.slaDueAt,
    required this.evidence,
    required this.messageCount,
    this.provisionalCreditPaise,
    this.provisionalCreditAt,
    this.creditNote,
    this.creditConditions = const [],
  });

  factory DisputeCase.fromJson(Map<String, Object?> json) {
    final rawTimeline = json['timeline'];
    final rawEvidence = json['evidence'];
    final rawConditions = json['creditConditions'];
    return DisputeCase(
      id: json['id']! as String,
      caseNumber: json['caseNumber']! as String,
      disputeId: json['disputeId']! as String,
      txnId: json['txnId']! as String,
      merchant: json['merchant'] as String? ?? '',
      reason:
          DisputeReason.fromApi(json['reason'] as String?) ??
          DisputeReason.unauthorised,
      txnAmountPaise: (json['txnAmountPaise'] as num?)?.toInt() ?? 0,
      disputedAmountPaise: (json['disputedAmountPaise']! as num).toInt(),
      status: CaseStatus.fromApi(json['status'] as String?),
      timeline:
          rawTimeline is List
              ? [
                for (final t in rawTimeline)
                  if (t is Map<String, Object?>) TimelineEntry.fromJson(t),
              ]
              : const [],
      createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
      slaDueAt: DateTime.parse(json['slaDueAt']! as String).toLocal(),
      evidence:
          rawEvidence is List
              ? [
                for (final e in rawEvidence)
                  if (e is Map<String, Object?>) EvidenceFile.fromJson(e),
              ]
              : const [],
      messageCount: (json['messageCount'] as num?)?.toInt() ?? 0,
      provisionalCreditPaise: (json['provisionalCreditPaise'] as num?)?.toInt(),
      provisionalCreditAt:
          json['provisionalCreditAt'] == null
              ? null
              : DateTime.parse(
                json['provisionalCreditAt']! as String,
              ).toLocal(),
      creditNote: json['creditNote'] as String?,
      creditConditions:
          rawConditions is List
              ? [for (final c in rawConditions) c.toString()]
              : const [],
    );
  }

  final String id;

  /// Shown to the customer, e.g. "FS-2026-000481".
  final String caseNumber;
  final String disputeId;
  final String txnId;
  final String merchant;
  final DisputeReason reason;
  final int txnAmountPaise;
  final int disputedAmountPaise;
  final CaseStatus status;
  final List<TimelineEntry> timeline;
  final DateTime createdAt;

  /// Provisional credit decision due by this time.
  final DateTime slaDueAt;
  final List<EvidenceFile> evidence;
  final int messageCount;
  final int? provisionalCreditPaise;
  final DateTime? provisionalCreditAt;
  final String? creditNote;
  final List<String> creditConditions;

  bool get hasCredit => provisionalCreditPaise != null;

  /// The SLA is about the provisional credit decision; it is met once
  /// credit is given or the case is closed.
  bool get slaMet => hasCredit || status.isClosed;
}
