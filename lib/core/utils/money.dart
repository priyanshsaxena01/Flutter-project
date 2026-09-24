/// Money is always an int number of paise (M1). Never a double.
class Money {
  const Money._();

  /// 499900 -> "₹4,999.00" with Indian digit grouping (₹1,23,456.00).
  static String format(int paise, {bool showPaise = true}) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = abs ~/ 100;
    final rest = abs % 100;
    final grouped = _indianGrouping(rupees);
    final text =
        showPaise
            ? '₹$grouped.${rest.toString().padLeft(2, '0')}'
            : '₹$grouped';
    return negative ? '-$text' : text;
  }

  /// "₹4,999" for whole rupees, "₹4,999.50" otherwise.
  static String compact(int paise) =>
      paise % 100 == 0 ? format(paise, showPaise: false) : format(paise);

  static String _indianGrouping(int n) {
    final s = n.toString();
    if (s.length <= 3) return s;
    final last3 = s.substring(s.length - 3);
    var rest = s.substring(0, s.length - 3);
    final parts = <String>[];
    while (rest.length > 2) {
      parts.insert(0, rest.substring(rest.length - 2));
      rest = rest.substring(0, rest.length - 2);
    }
    if (rest.isNotEmpty) parts.insert(0, rest);
    return '${parts.join(',')},$last3';
  }

  /// Parses "1,234.50", "₹1234" or "1234" into paise.
  /// Returns null when the text is not a valid amount.
  static int? parseRupees(String input) {
    final cleaned = input.replaceAll(',', '').replaceAll('₹', '').trim();
    if (cleaned.isEmpty) return null;
    final match = RegExp(r'^(\d{1,9})(?:\.(\d{1,2}))?$').firstMatch(cleaned);
    if (match == null) return null;
    final rupees = int.parse(match.group(1)!);
    final fraction = match.group(2);
    final paise = fraction == null ? 0 : int.parse(fraction.padRight(2, '0'));
    return rupees * 100 + paise;
  }
}
