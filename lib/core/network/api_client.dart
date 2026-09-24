import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fraud_shield/core/config/api_config.dart';
import 'package:fraud_shield/core/security/device_identity.dart';
import 'package:fraud_shield/features/auth/state/session_provider.dart';
import 'package:fraud_shield/mock_server/mock_bank_server.dart';
import 'package:fraud_shield/mock_server/mock_http_adapter.dart';

/// The single Dio instance used by every repository.
/// Widgets never import Dio: only repositories use this provider.
final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(apiConfigProvider);
  final device = ref.watch(deviceIdentityProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      // Timeouts matter for a real network. The in-app mock answers
      // quickly, and leaving them off keeps tests free of stray timers.
      connectTimeout: config.useMock ? null : const Duration(seconds: 10),
      receiveTimeout: config.useMock ? null : const Duration(seconds: 30),
      contentType: Headers.jsonContentType,
      responseType: ResponseType.json,
    ),
  );

  if (config.useMock) {
    // Answer requests from the in-app bank server instead of the internet.
    dio.httpClientAdapter = MockHttpAdapter(ref.watch(mockBankServerProvider));
  }

  dio.interceptors.addAll([
    AuditInterceptor(device),
    AuthInterceptor(
      tokenReader: () => ref.read(sessionProvider).token,
      onUnauthorized: () => ref.read(sessionProvider.notifier).expire(),
    ),
    if (kDebugMode) SafeLogInterceptor(),
  ]);
  return dio;
});

/// Auditability NFR: every call carries the device id and a client
/// timestamp, so the server can keep an immutable action log.
class AuditInterceptor extends Interceptor {
  AuditInterceptor(this.device);

  final DeviceIdentity device;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['X-Device-Id'] = device.id;
    options.headers['X-Device-Name'] = device.name;
    options.headers['X-Client-Timestamp'] =
        DateTime.now().toUtc().toIso8601String();
    handler.next(options);
  }
}

/// Adds the bearer token, and signs the user out on a 401.
class AuthInterceptor extends Interceptor {
  AuthInterceptor({required this.tokenReader, required this.onUnauthorized});

  final String? Function() tokenReader;
  final void Function() onUnauthorized;

  bool _isLogin(RequestOptions options) => options.path == '/auth/login';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = tokenReader();
    if (token != null && !_isLogin(options)) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // A 401 on login just means "wrong PIN"; anywhere else it means the
    // session is dead. Clearing the session makes the router guard send
    // the user to /login, with no navigation code needed here (B3).
    if (err.response?.statusCode == 401 && !_isLogin(err.requestOptions)) {
      onUnauthorized();
    }
    handler.next(err);
  }
}

/// Debug-only logging that never prints headers or bodies,
/// so tokens, PINs and card numbers never reach the logs.
class SafeLogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    debugPrint('[api] -> ${options.method} ${options.path}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    debugPrint(
      '[api] <- ${response.statusCode} ${response.requestOptions.path}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    debugPrint(
      '[api] xx ${err.response?.statusCode ?? err.type.name} '
      '${err.requestOptions.path}',
    );
    handler.next(err);
  }
}
