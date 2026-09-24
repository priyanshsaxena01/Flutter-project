import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:fraud_shield/mock_server/mock_bank_server.dart';

/// Plugs the in-app bank server into Dio.
///
/// Repositories, interceptors and error mapping run exactly as they would
/// against a real server; only the last hop (the socket) is replaced.
class MockHttpAdapter implements HttpClientAdapter {
  MockHttpAdapter(this.server);

  final MockBankServer server;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final request = MockRequest(
      method: options.method.toUpperCase(),
      uri: options.uri,
      headers: {
        for (final e in options.headers.entries)
          if (e.value != null) e.key.toLowerCase(): '${e.value}',
      },
      body: requestStream,
    );

    final MockResponse response;
    try {
      response = await server.handle(request);
    } on MockNetworkDown catch (e) {
      throw DioException.connectionError(
        requestOptions: options,
        reason: e.reason,
      );
    }

    final stream = response.stream;
    if (stream != null) {
      return ResponseBody(
        stream,
        response.status,
        headers: {
          Headers.contentTypeHeader: ['text/event-stream'],
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode(response.body),
      response.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class MockRequest {
  MockRequest({
    required this.method,
    required this.uri,
    required this.headers,
    this.body,
  });

  final String method;
  final Uri uri;

  /// Lower-case header names.
  final Map<String, String> headers;
  final Stream<Uint8List>? body;

  String get path => uri.path;

  List<String> get segments =>
      uri.pathSegments.where((s) => s.isNotEmpty).toList();

  String? header(String name) => headers[name.toLowerCase()];

  Future<Map<String, Object?>> readJson() async {
    final stream = body;
    if (stream == null) return const {};
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    if (bytes.isEmpty) return const {};
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, Object?> ? decoded : const {};
  }
}

class MockResponse {
  const MockResponse(this.status, this.body) : stream = null;

  const MockResponse.stream(Stream<Uint8List> this.stream)
    : status = 200,
      body = null;

  final int status;
  final Object? body;
  final Stream<Uint8List>? stream;

  bool get isSuccess => status >= 200 && status < 300;

  /// A deep copy, so a replay returns exactly the first answer.
  MockResponse snapshot() =>
      MockResponse(status, jsonDecode(jsonEncode(body)) as Object?);
}

/// Thrown by the server to simulate a dropped connection.
class MockNetworkDown implements Exception {
  const MockNetworkDown([this.reason = 'The network is unreachable.']);

  final String reason;
}
