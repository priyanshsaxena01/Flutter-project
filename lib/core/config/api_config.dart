import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Environment settings, passed with --dart-define (requirement B9).
///
///   flutter run
///       -> ENV=dev, uses the bank server built into the app (no setup)
///   flutter run --dart-define=ENV=staging --dart-define=API_BASE_URL=https://staging.example.com
///       -> talks to a real server with the same API contract
///
/// No screen ever hard-codes a URL; they all go through repositories.
class ApiConfig {
  const ApiConfig({required this.env, required this.baseUrl});

  factory ApiConfig.fromEnvironment() {
    const env = String.fromEnvironment('ENV', defaultValue: 'dev');
    const url = String.fromEnvironment('API_BASE_URL', defaultValue: '');
    return ApiConfig(env: env, baseUrl: url.isEmpty ? mockBaseUrl : url);
  }

  /// A fake address. Requests to it are answered by the in-app mock server.
  static const mockBaseUrl = 'https://mock.fraudshield.local';

  final String env;
  final String baseUrl;

  bool get useMock => baseUrl == mockBaseUrl;
}

final apiConfigProvider = Provider<ApiConfig>(
  (ref) => ApiConfig.fromEnvironment(),
);
