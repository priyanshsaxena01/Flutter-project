import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';
import 'package:fraud_shield/features/security/domain/security_models.dart';

/// Device management and login history (F9). Throws only BankError.
class SecurityRepository {
  SecurityRepository(this._dio);

  final Dio _dio;

  Future<List<Device>> devices() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/devices');
      return itemsOf(res.data).map(Device.fromJson).toList();
    });
  }

  /// 409 CURRENT if it is the device making the request.
  Future<void> signOutDevice(String id) {
    return guardCall(() async {
      await _dio.delete<Map<String, Object?>>('/devices/$id');
    });
  }

  Future<List<LoginEvent>> logins() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/security/logins');
      return itemsOf(res.data).map(LoginEvent.fromJson).toList();
    });
  }

  Future<List<AuditEntry>> auditLog() {
    return guardCall(() async {
      final res = await _dio.get<Map<String, Object?>>('/security/audit');
      return itemsOf(res.data).map(AuditEntry.fromJson).toList();
    });
  }
}

final securityRepositoryProvider = Provider<SecurityRepository>(
  (ref) => SecurityRepository(ref.watch(dioProvider)),
);
