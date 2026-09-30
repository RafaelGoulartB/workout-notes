import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/utils/strength_workout_records.dart';

StrengthSetSample _sample(
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
  final d1 = DateTime(2026, 9, 1);
  final d2 = DateTime(2026, 9, 8);
  final d3 = DateTime(2026, 9, 15);

  group('StrengthWorkoutFormat', () {
    setUp(() => Intl.defaultLocale = 'pt_BR');
    tearDown(() => Intl.defaultLocale = null);

    test('weight trims useless decimals', () {
      expect(StrengthWorkoutFormat.weight(80), '80');
      expect(StrengthWorkoutFormat.weight(82.5), '82,5');
      expect(StrengthWorkoutFormat.weight(82.25), '82,25');
      expect(StrengthWorkoutFormat.setLabel(82.5, 5), '82,5 kg × 5');
    });

    test('volume switches to tonnes above 1000 kg', () {
      expect(StrengthWorkoutFormat.volume(820), '820 kg');
      expect(StrengthWorkoutFormat.volume(62600), '62,6 t');
      expect(StrengthWorkoutFormat.volume(0), '0 kg');
    });

    test('signed deltas', () {
      expect(StrengthWorkoutFormat.signedVolume(1200), '+1,2 t');
      expect(StrengthWorkoutFormat.signedVolume(-300), '-300 kg');
      expect(StrengthWorkoutFormat.signedVolume(0.1), '0 kg');
      expect(StrengthWorkoutFormat.signedInt(2), '+2');
      expect(StrengthWorkoutFormat.signedInt(-1), '-1');
      expect(StrengthWorkoutFormat.signedDuration(300), '+5min');
      expect(StrengthWorkoutFormat.signedDuration(-3900), '-1h 05min');
      expect(StrengthWorkoutFormat.signedDuration(10), '0min');
    });
  });

  group('StrengthWorkoutRecords.sessionEvents', () {
    final history = [
      _sample('w1', d1, 'bench', 100, 5),
      _sample('w2', d2, 'bench', 100, 5),
    ];

    test('reports records of an unsaved session against history', () {
      final events = StrengthWorkoutRecords.sessionEvents(
        history: history,
        session: [_sample('now', d3, 'bench', 105, 5)],
        workoutId: 'now',
      );
      expect(events.map((e) => e.kind).toSet(), {
        StrengthRecordKind.e1rm,
        StrengthRecordKind.weight,
      });
      expect(events.every((e) => e.workoutId == 'now'), isTrue);
    });

    test('no record when the session does not beat history', () {
      final events = StrengthWorkoutRecords.sessionEvents(
        history: history,
        session: [_sample('now', d3, 'bench', 95, 5)],
        workoutId: 'now',
      );
      expect(events, isEmpty);
    });

    test('first session of an exercise is a baseline', () {
      final events = StrengthWorkoutRecords.sessionEvents(
        history: history,
        session: [_sample('now', d3, 'squat', 140, 5)],
        workoutId: 'now',
      );
      expect(events, isEmpty);
    });

    test('ignores an earlier copy of the same workout in history', () {
      final events = StrengthWorkoutRecords.sessionEvents(
        history: [...history, _sample('now', d2, 'bench', 200, 1)],
        session: [_sample('now', d3, 'bench', 105, 5)],
        workoutId: 'now',
      );
      expect(events, isNotEmpty);
    });
  });

  group('StrengthWorkoutRecords.volumeRecords', () {
    test('needs a previous session and a strictly larger volume', () {
      final history = [
        _sample('w1', d1, 'row', 50, 10),
        _sample('w1', d1, 'row', 50, 10),
        _sample('w2', d2, 'row', 40, 10),
      ];
      final records = StrengthWorkoutRecords.volumeRecords(
        history: history,
        session: [
          _sample('now', d3, 'row', 55, 10),
          _sample('now', d3, 'row', 55, 10),
          _sample('now', d3, 'squat', 100, 5),
        ],
        workoutId: 'now',
      );
      expect(records.keys, ['row']);
      expect(records['row']!.volume, 1100);
      expect(records['row']!.previous, 1000);

      expect(
        StrengthWorkoutRecords.volumeRecords(
          history: history,
          session: [_sample('now', d3, 'row', 50, 10)],
          workoutId: 'now',
        ),
        isEmpty,
      );
    });
  });

  group('StrengthWorkoutRecords.markSets', () {
    test('marks the set that produced the event, never warm-ups', () {
      final events = StrengthWorkoutRecords.sessionEvents(
        history: [
          _sample('w1', d1, 'bench', 100, 5),
          _sample('w2', d2, 'bench', 100, 5),
        ],
        session: [_sample('now', d3, 'bench', 105, 5)],
        workoutId: 'now',
      );
      final marks = StrengthWorkoutRecords.markSets(
        events: events,
        exerciseId: 'bench',
        sets: const [
          StrengthMarkableSet(id: 'a', weight: 105, reps: 5, isWarmup: true),
          StrengthMarkableSet(id: 'b', weight: 100, reps: 5),
          StrengthMarkableSet(id: 'c', weight: 105, reps: 5),
          StrengthMarkableSet(id: 'd', weight: 105, reps: 5),
        ],
      );
      expect(marks.keys, ['c']);
      expect(marks['c'], {StrengthRecordKind.e1rm, StrengthRecordKind.weight});
    });
  });

  test('exerciseCountByWorkout counts distinct exercises', () {
    final events = StrengthRecordsCalculator.events([
      _sample('w1', d1, 'bench', 100, 5),
      _sample('w1', d1, 'row', 80, 5),
      _sample('w2', d2, 'bench', 105, 5),
      _sample('w2', d2, 'row', 85, 5),
    ]);
    final counts = StrengthWorkoutRecords.exerciseCountByWorkout(events);
    // Four events (e1rm + weight for each exercise), two exercises.
    expect(counts, {'w2': 2});
  });
}
