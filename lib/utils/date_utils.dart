/// Calendar-day helpers shared by repositories and services.
///
/// All of them work on the wall-clock date of the given [DateTime] and are
/// safe across daylight-saving changes: days are added through the
/// `DateTime(year, month, day + n)` constructor instead of subtracting a
/// fixed 24-hour [Duration].
library;

/// Midnight (local) of [value]'s calendar day.
DateTime dayOf(DateTime value) => DateTime(value.year, value.month, value.day);

/// Whether [a] and [b] fall on the same calendar day (wall-clock fields).
bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

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

/// `yyyy-MM` of [value]'s month, used to group history by month.
String monthKey(DateTime value) => dateKey(value).substring(0, 7);

/// `yyyy-MM-dd` of [value]'s calendar day, the format stored in `date`
/// columns.
String dateKey(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}

/// Whole calendar days from [from] to [to] (negative when [to] is earlier),
/// ignoring the time of day. Unlike `to.difference(from).inDays` this stays
/// exact across a daylight-saving change, where a local day lasts 23 or 25
/// hours and the difference of two local midnights is not a multiple of 24 h.
int daysBetween(DateTime from, DateTime to) => DateTime.utc(
  to.year,
  to.month,
  to.day,
).difference(DateTime.utc(from.year, from.month, from.day)).inDays;
