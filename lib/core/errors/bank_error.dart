/// The one and only error type that leaves the data layer.
///
/// Repositories convert every DioException into one of these, so screens
/// never see HTTP details, stack traces or raw status codes (B7).
sealed class BankError implements Exception {
  const BankError(
    this.message, {
    this.code,
    this.traceId,
    this.details = const {},
  });

  /// Plain-language text that is safe to show on screen.
  final String message;

  /// Machine code from the server, for example "ALREADY_BLOCKED".
  final String? code;

  /// Server trace id. Only printed in debug logs, never shown to users.
  final String? traceId;

  /// Extra data from the server, for example field errors or a case id.
  final Map<String, Object?> details;

  @override
  String toString() => '$runtimeType(${code ?? '-'}): $message';
}

/// No connection at all.
final class NetworkError extends BankError {
  const NetworkError()
    : super('You appear to be offline. Check your connection and try again.');
}

/// The server took too long to answer.
final class TimeoutError extends BankError {
  const TimeoutError()
    : super('The bank is taking too long to respond. Please try again.');
}

/// 401: the session is no longer valid, or login details are wrong.
final class UnauthorizedError extends BankError {
  const UnauthorizedError(super.message, {super.code, super.traceId});
}

/// 403: signed in, but not allowed to do this.
final class ForbiddenError extends BankError {
  const ForbiddenError(super.message, {super.code, super.traceId});
}

/// 400 / 422: the request had invalid data.
final class ValidationError extends BankError {
  const ValidationError(
    super.message, {
    super.code,
    super.traceId,
    super.details,
  });

  /// Field id -> message, when the server named the fields.
  Map<String, String> get fieldErrors => {
    for (final e in details.entries)
      if (e.value is String) e.key: e.value! as String,
  };
}

/// 404.
final class NotFoundError extends BankError {
  const NotFoundError(super.message, {super.code, super.traceId});
}

/// 409: conflicts such as "already blocked" or "this is your current device".
final class ConflictError extends BankError {
  const ConflictError(
    super.message, {
    super.code,
    super.traceId,
    super.details,
  });
}

/// 413: a file is too large.
final class PayloadTooLargeError extends BankError {
  const PayloadTooLargeError(super.message, {super.code, super.traceId});
}

/// 423: account locked after too many wrong PINs.
final class LockedError extends BankError {
  const LockedError(super.message, {super.code, super.traceId});
}

/// 5xx.
final class ServerError extends BankError {
  const ServerError(super.message, {super.code, super.traceId});
}

/// Anything we could not classify.
final class UnknownError extends BankError {
  const UnknownError(super.message, {super.code, super.traceId});
}

/// Turns any error into text that is safe to put on screen.
String friendlyMessage(Object error) {
  if (error is BankError) return error.message;
  return 'Something went wrong. Please try again.';
}
