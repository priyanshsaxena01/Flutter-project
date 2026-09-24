/// Small helpers for reading JSON at the border (M1: no dynamic leaks out).
Map<String, Object?> asJson(Object? value) =>
    value is Map<String, Object?> ? value : const {};

/// The "items" list of a { items, nextCursor } response.
List<Map<String, Object?>> itemsOf(Object? body, [String key = 'items']) {
  final list = asJson(body)[key];
  if (list is! List) return const [];
  return [
    for (final e in list)
      if (e is Map<String, Object?>) e,
  ];
}
