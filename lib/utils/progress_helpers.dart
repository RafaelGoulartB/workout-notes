import 'package:intl/intl.dart';

/// Shared helper functions used across progress chart widgets.

double niceInterval(double range) {
  if (range <= 0) return 1;
  final rough = range / 5;
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
  if (temp <= 1) {
    temp = 1;
  } else if (temp <= 2) {
    temp = 2;
  } else if (temp <= 5) {
    temp = 5;
  } else {
    temp = 10;
  }
  final result = temp * magnitude;
  return result < 0.5 ? 0.5 : result;
}

String formatVolume(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
  return v.toStringAsFixed(0);
}

String monthLabel(String isoMonth) {
  try {
    return DateFormat('MMM', Intl.defaultLocale)
        .format(DateTime.parse(isoMonth));
  } catch (_) {
    return isoMonth.length >= 7 ? isoMonth.substring(5) : isoMonth;
  }
}

String weekLabel(DateTime date, String prefix) {
  final week = DateFormat('w', Intl.defaultLocale).format(date);
  return '$prefix$week';
}
