/// Converts dates to and from the calendar-only format persisted by SQLite.
abstract final class AppDateCodec {
  static String toStorageDate(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  static DateTime fromStorageDate(String value) => DateTime.parse(value);
}
