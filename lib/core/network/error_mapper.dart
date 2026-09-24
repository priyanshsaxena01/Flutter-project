import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'package:fraud_shield/core/errors/bank_error.dart';

/// Converts a DioException into a BankError.
///
/// The server sends errors as:
///   { "error": { "code", "message", "details", "traceId" } }
BankError mapDioError(DioException e) {
  final type = e.type;
  if (type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout) {
    return const TimeoutError();
  }
  if (type == DioExceptionType.connectionError) return const NetworkError();
  if (type == DioExceptionType.cancel) {
    return const UnknownError('The request was cancelled.');
  }
  if (type == DioExceptionType.badCertificate) {
    return const UnknownError(
      'A secure connection to the bank could not be made.',
    );
  }

  final response = e.response;
  if (response == null) {
    // "unknown" with no response is almost always a socket problem.
    return const NetworkError();
  }

  final status = response.statusCode ?? 0;
  String? code;
  String? message;
  String? traceId;
  var details = const <String, Object?>{};

  final data = response.data;
  if (data is Map && data['error'] is Map) {
    final err = data['error'] as Map;
    code = err['code'] as String?;
    message = err['message'] as String?;
    traceId = err['traceId'] as String?;
    final rawDetails = err['details'];
    if (rawDetails is Map) {
      details = rawDetails.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
    }
  }

  if (kDebugMode && traceId != null) {
    // Observability: trace id in debug logs only. No tokens, no bodies.
    debugPrint('[api] error status=$status code=$code traceId=$traceId');
  }

  return switch (status) {
    400 || 422 => ValidationError(
      message ?? 'Please check the details and try again.',
      code: code,
      traceId: traceId,
      details: details,
    ),
    401 => UnauthorizedError(
      message ?? 'Your session has ended. Please sign in again.',
      code: code,
      traceId: traceId,
    ),
    403 => ForbiddenError(
      message ?? 'You are not allowed to do this.',
      code: code,
      traceId: traceId,
    ),
    404 => NotFoundError(
      message ?? 'We could not find what you were looking for.',
      code: code,
      traceId: traceId,
    ),
    409 => ConflictError(
      message ?? 'This changed while you were working. Please try again.',
      code: code,
      traceId: traceId,
      details: details,
    ),
    413 => PayloadTooLargeError(
      message ?? 'This file is too large.',
      code: code,
      traceId: traceId,
    ),
    423 => LockedError(
      message ?? 'Your access is temporarily locked.',
      code: code,
      traceId: traceId,
    ),
    >= 500 => ServerError(
      message ??
          'The bank could not complete this right now. Please try again.',
      code: code,
      traceId: traceId,
    ),
    _ => UnknownError(
      message ?? 'Something went wrong. Please try again.',
      code: code,
      traceId: traceId,
    ),
  };
}

/// Runs a network call and converts any DioException into a BankError.
Future<T> guardCall<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on DioException catch (e) {
    throw mapDioError(e);
  }
}
