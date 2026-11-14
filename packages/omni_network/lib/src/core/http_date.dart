final _date = RegExp(
  r'^\w{3}, (\d{2}) (\w{3}) (\d{4}) (\d{2}):(\d{2}):(\d{2}) GMT$',
);
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Parses an IMF-fixdate (`Wed, 21 Oct 2015 07:28:00 GMT`), or `null`.
/// Internal.
DateTime? parseHttpDate(String value) {
  final m = _date.firstMatch(value.trim());
  if (m == null) return null;
  final month = _months.indexOf(m[2]!) + 1;
  if (month == 0) return null;
  return DateTime.utc(
    int.parse(m[3]!),
    month,
    int.parse(m[1]!),
    int.parse(m[4]!),
    int.parse(m[5]!),
    int.parse(m[6]!),
  );
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Formats [t] as an IMF-fixdate. Internal.
String formatHttpDate(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_days[u.weekday - 1]}, ${two(u.day)} ${_months[u.month - 1]} '
      '${u.year} ${two(u.hour)}:${two(u.minute)}:${two(u.second)} GMT';
}
