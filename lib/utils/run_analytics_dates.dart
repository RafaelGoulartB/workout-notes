import 'package:workout_notes/models/run_activity.dart';

/// Calendar helpers shared by the running analytics.
abstract final class RunAnalyticsDates {
  static bool completedRun(RunActivity a) => a.isCompleted && a.isRunning;
}
