import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/network/api_client.dart';
import 'package:fraud_shield/core/network/error_mapper.dart';
import 'package:fraud_shield/core/network/json.dart';

class LoginResult {
  const LoginResult({
    required this.token,
    required this.customerName,
    required this.customerId,
  });

  final String token;
  final String customerName;
  final String customerId;
}

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  Future<LoginResult> login({required String customerId, required String pin}) {
    return guardCall(() async {
      final res = await _dio.post<Map<String, Object?>>(
        '/auth/login',
        data: {'customerId': customerId.trim().toUpperCase(), 'pin': pin},
      );
      final data = asJson(res.data);
      final customer = asJson(data['customer']);
      return LoginResult(
        token: data['token']! as String,
        customerName: customer['name'] as String? ?? '',
        customerId: customer['id'] as String? ?? customerId,
      );
    });
  }

  /// Best effort: the local session is cleared even if this fails.
  Future<void> logout() async {
    try {
      await _dio.post<void>('/auth/logout');
    } on DioException {
      // Offline logout still signs out locally.
    }
  }
}

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(dioProvider)),
);
