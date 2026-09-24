/// A device signed in to the customer's account (F9).
class Device {
  const Device({
    required this.id,
    required this.name,
    required this.location,
    required this.lastSeen,
    required this.current,
  });

  factory Device.fromJson(Map<String, Object?> json) => Device(
    id: json['id']! as String,
    name: json['name']! as String,
    location: json['location'] as String? ?? '',
    lastSeen: DateTime.parse(json['lastSeen']! as String).toLocal(),
    current: json['current'] as bool? ?? false,
  );

  final String id;
  final String name;
  final String location;
  final DateTime lastSeen;

  /// The device making the request. It cannot remove itself.
  final bool current;
}

class LoginEvent {
  const LoginEvent({
    required this.at,
    required this.deviceName,
    required this.location,
    required this.success,
  });

  factory LoginEvent.fromJson(Map<String, Object?> json) => LoginEvent(
    at: DateTime.parse(json['at']! as String).toLocal(),
    deviceName: json['deviceName'] as String? ?? '',
    location: json['location'] as String? ?? '',
    success: json['success'] as bool? ?? false,
  );

  final DateTime at;
  final String deviceName;
  final String location;
  final bool success;
}

/// One line of the server's immutable action log (Auditability NFR).
class AuditEntry {
  const AuditEntry({
    required this.at,
    required this.action,
    required this.deviceId,
    this.clientAt,
    this.status,
  });

  factory AuditEntry.fromJson(Map<String, Object?> json) => AuditEntry(
    at: DateTime.parse(json['at']! as String).toLocal(),
    clientAt:
        json['clientAt'] == null
            ? null
            : DateTime.tryParse(json['clientAt']! as String)?.toLocal(),
    action: json['action'] as String? ?? '',
    deviceId: json['deviceId'] as String? ?? '',
    status: (json['status'] as num?)?.toInt(),
  );

  final DateTime at;
  final DateTime? clientAt;
  final String action;
  final String deviceId;
  final int? status;
}
