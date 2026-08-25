import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/utils/run_completion_policy.dart';

RunActivity activity({required int seconds, required double meters}) {
  final now = DateTime.utc(2026, 8, 25);
  return RunActivity(
    id: 'run',
    startedAt: now,
    endedAt: now.add(Duration(seconds: seconds)),
    durationSeconds: seconds,
    movingTimeSeconds: seconds,
    distanceMeters: meters,
    avgPaceSecPerKm: null,
    maxPaceSecPerKm: null,
    calories: null,
    title: null,
    notes: null,
    status: 'completed',
    polylineSummary: null,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  test('a few accidental seconds cannot complete a planned workout', () {
    final short = activity(seconds: 12, meters: 18);

    expect(RunCompletionPolicy.isTooShort(short), isTrue);
    expect(RunCompletionPolicy.canCompletePlan(short), isFalse);
  });

  test('reaching either meaningful threshold allows plan completion', () {
    expect(
      RunCompletionPolicy.canCompletePlan(activity(seconds: 120, meters: 50)),
      isTrue,
    );
    expect(
      RunCompletionPolicy.canCompletePlan(activity(seconds: 30, meters: 200)),
      isTrue,
    );
  });
}
