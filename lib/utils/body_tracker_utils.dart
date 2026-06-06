import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Returns icon and label for a given time-of-day identifier.
(IconData, String) timeOfDayData(String tod, BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  switch (tod) {
    case 'morning':
      return (Icons.wb_sunny, loc.bodyTrackerMorning);
    case 'afternoon':
      return (Icons.wb_cloudy, loc.bodyTrackerAfternoon);
    case 'evening':
      return (Icons.nights_stay, loc.bodyTrackerEvening);
    case 'night':
      return (Icons.bedtime, loc.bodyTrackerNight);
    default:
      return (Icons.access_time, tod);
  }
}

/// Formats a date string (yyyy-MM-dd) to Brazilian Portuguese format.
String formatDate(String dateStr) {
  if (dateStr.isEmpty) return '';
  try {
    return DateFormat('d MMM yyyy', 'pt_BR').format(DateTime.parse(dateStr));
  } catch (_) {
    return dateStr;
  }
}

/// Computes a "nice" interval for chart grid lines based on the data range.
double niceInterval(double range) {
  if (range <= 0) return 1;
  final rough = range / 4;
  double magnitude = 1;
  double temp = rough;
  while (temp >= 10) {
    temp /= 10;
    magnitude *= 10;
  }
  while (temp < 1) {
    temp *= 10;
    magnitude /= 10;
  }
  if (temp <= 1) temp = 1;
  if (temp <= 2) temp = 2;
  if (temp <= 5) temp = 5;
  if (temp <= 10) temp = 10;
  final result = temp * magnitude;
  return result < 0.5 ? 0.5 : result;
}

/// Returns the localized display name for a measurement type ID.
String typeName(String typeId, BuildContext context) {
  final loc = AppLocalizations.of(context)!;
  switch (typeId) {
    case 'weight':
      return loc.bodyTrackerWeight;
    case 'bodyFat':
      return loc.bodyTrackerBodyFat;
    case 'waist':
      return loc.bodyTrackerWaist;
    case 'chest':
      return loc.bodyTrackerChest;
    case 'arm':
      return loc.bodyTrackerArm;
    case 'thigh':
      return loc.bodyTrackerThigh;
    case 'calf':
      return loc.bodyTrackerCalf;
    case 'hip':
      return loc.bodyTrackerHip;
    default:
      return typeId;
  }
}
