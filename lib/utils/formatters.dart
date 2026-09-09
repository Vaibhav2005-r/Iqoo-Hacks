import 'package:intl/intl.dart';

/// Formatting helpers shared across screens.
class Fmt {
  const Fmt._();

  /// Indian digit grouping (1,00,000 not 100,000) — getting this wrong is the
  /// fastest way to look foreign to the user this is built for.
  static final _rupees = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 0,
  );

  static final _rupeesPrecise = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹',
    decimalDigits: 2,
  );

  static final _dayMonth = DateFormat('d MMM');
  static final _dayMonthYear = DateFormat('d MMM yyyy');
  static final _time = DateFormat('h:mm a');

  /// Whole rupees unless there are real paise to show.
  static String money(double amount) {
    final hasPaise = (amount * 100).round() % 100 != 0;
    return hasPaise ? _rupeesPrecise.format(amount) : _rupees.format(amount);
  }

  /// Absolute value formatted, for use next to an explicit +/- or a label.
  static String moneyAbs(double amount) => money(amount.abs());

  static String date(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year ? _dayMonth.format(dt) : _dayMonthYear.format(dt);
  }

  static String fullDate(DateTime dt) => _dayMonthYear.format(dt);

  static String time(DateTime dt) => _time.format(dt);

  /// "Today", "Yesterday", then a date — how a shopkeeper thinks about entries.
  static String relativeDay(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(that).inDays;

    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '$diff days ago';
    return date(dt);
  }

  static String duration(Duration d) {
    if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
}
