import 'dart:math';

/// Exponential backoff with jitter for reconnecting the live stream:
/// 1 s, 2 s, 4 s, 8 s ... capped at 30 s, each spread by ±20% so many
/// phones do not reconnect at the same instant.
class Backoff {
  const Backoff({
    this.initial = const Duration(seconds: 1),
    this.max = const Duration(seconds: 30),
    this.jitter = 0.2,
  });

  final Duration initial;
  final Duration max;

  /// 0.2 means ±20%.
  final double jitter;

  /// [attempt] starts at 1. [random] is in 0..1 (0.5 = no jitter).
  Duration delayFor(int attempt, {double random = 0.5}) {
    final exponent = (attempt - 1).clamp(0, 20);
    final base = min(
      initial.inMilliseconds * pow(2, exponent),
      max.inMilliseconds.toDouble(),
    );
    final factor = 1 + jitter * (random * 2 - 1);
    return Duration(milliseconds: (base * factor).round());
  }
}
