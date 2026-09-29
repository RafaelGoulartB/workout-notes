/// Calendar-day helpers shared by repositories and services.
///
/// All of them work on the wall-clock date of the given [DateTime] and are
/// safe across daylight-saving changes: days are added through the
/// `DateTime(year, month, day + n)` constructor instead of subtracting a
/// fixed 24-hour [Duration].
library;

/// Midnight (local) of [value]'s calendar day.
DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// Midnight (local) of the day [days] after (or before, when negative) the
/// calendar day of [value].
DateTime addDays(DateTime value, int days) =>
    DateTime(value.year, value.month, value.day + days);

/// Midnight (local) of the Monday starting the ISO week that contains [value].
DateTime mondayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day - (value.weekday - 1));

/// Midnight (local) of the Sunday starting the week that contains [value]
/// (the nutrition / body-weight convention; `DateTime.sunday` is 7, so it wraps
/// to 0).
DateTime sundayOf(DateTime value) =>
    DateTime(value.year, value.month, value.day - value.weekday % 7);

/// `yyyy-MM-dd` of [value]'s calendar day, the format stored in `date`
/// columns.
String dateKey(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
