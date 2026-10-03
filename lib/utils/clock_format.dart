import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Time-of-day text that follows the app language and the system 12/24 h
/// setting (`MediaQuery.alwaysUse24HourFormat`). For stored keys keep using
/// `date_utils`; this is for display only.
class ClockFormat {
  const ClockFormat._();

  /// `15:05` in 24 h mode, `3:05 PM` (locale rules) otherwise.
  static DateFormat of(BuildContext context) => forSettings(
    use24Hour: MediaQuery.alwaysUse24HourFormatOf(context),
    locale: Localizations.maybeLocaleOf(context)?.toString(),
  );

  /// Same as [of] without a [BuildContext].
  static DateFormat forSettings({required bool use24Hour, String? locale}) {
    final name = locale ?? Intl.defaultLocale;
    return use24Hour ? DateFormat.Hm(name) : DateFormat.jm(name);
  }

  /// Formats [time] with [of].
  static String format(BuildContext context, DateTime time) =>
      of(context).format(time);
}
