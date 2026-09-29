import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_week_analytics.dart';

/// Formatting shared by the gym hub widgets.
abstract final class StrengthHomeFormat {
  /// `850 kg` or `12,3 t`.
  static String volume(double kg) {
    final v = StrengthVolumeValue.of(kg);
    return '${RunFormatters.decimal(v.value, v.digits)} ${v.unit}';
  }

  static String duration(int seconds) =>
      RunFormatters.durationHoursMinutes(seconds);

  static String weight(double kg) {
    final digits = kg == kg.roundToDouble() ? 0 : 1;
    return '${RunFormatters.decimal(kg, digits)} kg';
  }

  /// Weekday, day and month (`ter., 29 set.`).
  static String dayLabel(BuildContext context, DateTime date) =>
      DateFormat.MMMEd(Localizations.localeOf(context).toString()).format(date);

  static String shortDate(BuildContext context, DateTime date) =>
      DateFormat.MMMd(Localizations.localeOf(context).toString()).format(date);

  /// Muscle group name in the app language.
  static String categoryName(
    AppLocalizations loc,
    StrengthCategoryInfo category,
  ) => ExerciseLocaleHelper.categoryName(loc, category.row);

  /// "10–20", "10+" or "up to 20" for a sets target; null when there is none.
  static String? setsRange(int? min, int? max) {
    if (min != null && max != null) return '$min–$max';
    if (min != null) return '$min+';
    if (max != null) return '≤$max';
    return null;
  }

  static Color color(int argb) => Color(argb);
}
