import 'package:workout_notes/models/run_activity.dart';

/// Calendar helpers shared by the running analytics.
abstract final class RunAnalyticsDates {
  static DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime monday(DateTime d) {
    final start = day(d);
    return start.subtract(Duration(days: start.weekday - DateTime.monday));
  }

  static bool completedRun(RunActivity a) => a.isCompleted && a.isRunning;
}
