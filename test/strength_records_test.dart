import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';

StrengthSetSample _set(
  String workout,
  DateTime date,
  String exercise,
  double weight,
  int reps,
) => StrengthSetSample(
  workoutId: workout,
  date: date,
  exerciseId: exercise,
  exerciseName: exercise,
  exerciseLocaleKey: null,
  categoryId: 'chest',
  weight: weight,
  reps: reps,
);

void main() {
  group('strengthE1rm', () {
    test('uses Epley and ignores very high reps', () {
      expect(strengthE1rm(100, 1), 100);
      expect(strengthE1rm(100, 5), closeTo(116.67, 0.01));
      expect(strengthE1rm(50, 20), isNull);
      expect(strengthE1rm(0, 5), isNull);
    });
  });

  group('StrengthRecordsCalculator', () {
    final d1 = DateTime(2026, 9, 1);
    final d2 = DateTime(2026, 9, 8);
    final d3 = DateTime(2026, 9, 15);

    test('best e1RM is the maximum over all sets, not the heaviest set', () {
      final records = StrengthRecordsCalculator.records([
        _set('w1', d1, 'bench', 100, 1),
        _set('w1', d1, 'bench', 90, 8),
      ]);
      final bench = records.single;
      expect(bench.maxWeight, 100);
      // 90 × (1 + 8/30) = 114 > 100.
      expect(bench.bestE1rm, closeTo(114, 0.01));
      expect(bench.bestE1rmReps, 8);
      expect(bench.sessionCount, 1);
    });

    test('first session is a baseline; later improvements are events', () {
      final events = StrengthRecordsCalculator.events([
        _set('w1', d1, 'squat', 100, 5),
        _set('w2', d2, 'squat', 100, 5),
        _set('w3', d3, 'squat', 105, 5),
        _set('w3', d3, 'squat', 102.5, 6),
      ]);
      expect(events.map((e) => e.workoutId).toSet(), {'w3'});
      final e1rm = events.firstWhere((e) => e.kind == StrengthRecordKind.e1rm);
      expect(e1rm.value, closeTo(123, 0.01)); // 102.5 × 1.2
      expect(e1rm.previous, closeTo(116.67, 0.01));
      final weight = events.firstWhere(
        (e) => e.kind == StrengthRecordKind.weight,
      );
      expect(weight.value, 105);
      expect(weight.previous, 100);
    });

    test('best session volume sums the sets of one workout', () {
      final record = StrengthRecordsCalculator.records([
        _set('w1', d1, 'row', 50, 10),
        _set('w1', d1, 'row', 50, 10),
        _set('w2', d2, 'row', 60, 8),
      ]).single;
      expect(record.bestSessionVolume, 1000);
      expect(record.bestSessionVolumeDate, d1);
    });
  });
}
