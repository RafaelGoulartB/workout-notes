import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/strength_workout_summary.dart';
import 'package:workout_notes/screens/workout/workout_home_controller.dart';
import 'package:workout_notes/utils/date_utils.dart';

void main() {
  StrengthWorkoutStamp stamp(DateTime date) =>
      StrengthWorkoutStamp(date: date, durationSeconds: 3600);

  test('weekly sessions average over the last 12 calendar weeks', () {
    final monday = DateTime(2026, 3, 9);
    final stamps = [
      // Inside the window: this week and 11 weeks back (window start).
      stamp(monday),
      stamp(addDays(monday, 2)),
      stamp(addDays(monday, -7 * 11)),
      // Just before the window: ignored.
      stamp(addDays(monday, -(7 * 11 + 1))),
    ];
    expect(WorkoutHomeController.averageWeeklySessions(stamps, monday), 3 / 12);
    expect(WorkoutHomeController.averageWeeklySessions(const [], monday), 0);
  });
}
