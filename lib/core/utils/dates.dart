/// Date helpers. The API sends ISO-8601 UTC; models convert to local time
/// once, and screens only format.
class Dates {
  const Dates._();

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  /// "24 Sep 2026"
  static String date(DateTime d) {
    final l = d.toLocal();
    return '${l.day} ${_months[l.month - 1]} ${l.year}';
  }

  /// "9:05 PM"
  static String time(DateTime d) {
    final l = d.toLocal();
    final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m ${l.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "24 Sep 2026, 9:05 PM"
  static String dateTime(DateTime d) => '${date(d)}, ${time(d)}';

  /// "just now", "5 min ago", "3 h ago", "yesterday", "24 Sep 2026".
  static String timeAgo(DateTime d, DateTime now) {
    final diff = now.difference(d);
    if (diff.inSeconds < 45) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes.clamp(1, 59)} min ago';
    if (diff.inHours < 24) return '${diff.inHours} h ago';
    if (diff.inHours < 48) return 'yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return date(d);
  }

  /// "2026-09-24", used for date answers in the dispute form.
  static String isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Parses "2026-09-24". Returns null when invalid.
  static DateTime? parseIsoDate(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final d = DateTime(
      int.parse(m.group(1)!),
      int.parse(m.group(2)!),
      int.parse(m.group(3)!),
    );
    // Reject rollovers such as 2026-02-31.
    if (Dates.isoDate(d) != s) return null;
    return d;
  }

  /// Strips the time, in local time.
  static DateTime dayOf(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day);
  }
}
