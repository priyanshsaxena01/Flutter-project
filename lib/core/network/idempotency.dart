import 'dart:math';

final _random = Random.secure();

/// A new Idempotency-Key (B6).
///
/// Create ONE key when a confirmation screen opens and reuse it for every
/// retry from that screen. The server returns the first answer for a
/// repeated key, so a double tap or a retry on a flaky network can never
/// block twice or open two cases.
String newIdempotencyKey() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return 'idem-${DateTime.now().millisecondsSinceEpoch}-$hex';
}
