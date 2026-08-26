import 'package:workout_notes/models/run_activity.dart';

abstract final class RunCompletionPolicy {
  /// A few accidental seconds must not consume a planned session. Reaching
  /// either threshold is enough to treat the activity as intentional.
  static const int minimumDurationSeconds = 120;
  static const double minimumDistanceMeters = 200;

  static bool isTooShort(RunActivity activity) =>
      activity.durationSeconds < minimumDurationSeconds &&
      activity.distanceMeters < minimumDistanceMeters;

  static bool canCompletePlan(RunActivity activity) => !isTooShort(activity);
}
