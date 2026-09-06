import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import '../tool/replay_sleep.dart';
import 'support/sleep_bedside_fixture.dart';

void main() {
  test(
    'unlabelled time is not assumed asleep; missing labels produce null metrics',
    () {
      final result = evaluateLabels([], bedsideStart, []);
      expect(result['balanced_recall'], isNull);
      expect(result['accuracy_on_classified_seconds'], isNull);
    },
  );
  test(
    'unknown and missing predictions reduce coverage without becoming false sleep',
    () {
      final cursor = SleepWakeCursor(sessionId: 'bedside');
      final epochs = [cursor.unknown(bedsideStart, 30)];
      final result = evaluateLabels(epochs, bedsideStart, [
        {
          'start_seconds': 0,
          'end_seconds': 600,
          'state': 'awake',
          'source': 'controlled_awake',
        },
      ]);
      expect(result['unknown_seconds'], 600);
      expect(result['false_sleep_seconds'], 0);
      expect(result['labelled_coverage'], 0);
      expect(result['awake_recall_including_abstentions'], 0);
      expect(result['accuracy_on_classified_seconds'], isNull);
    },
  );
  test(
    'evaluates full wake intervals including the end of a night by duration',
    () {
      final cursor = SleepWakeCursor(sessionId: 'bedside');
      cursor.add(bedsideSegment(0, activity: true));
      final awake = cursor.add(bedsideSegment(1, activity: true)).epoch;
      expect(awake.stage, SleepStageType.awake);
      final result = evaluateLabels(
        [awake],
        bedsideStart,
        [
          {
            'start_seconds': 30,
            'end_seconds': 60,
            'state': 'awake',
            'source': 'observed',
          },
        ],
      );
      expect(result['awake_recall_including_abstentions'], 1);
      expect(result['accuracy_on_classified_seconds'], 1);
    },
  );
  test('rejects overlapping reference labels', () {
    expect(
      () => evaluateLabels([], bedsideStart, [
        {
          'start_seconds': 0,
          'end_seconds': 60,
          'state': 'awake',
          'source': 'observed',
        },
        {
          'start_seconds': 30,
          'end_seconds': 90,
          'state': 'asleep',
          'source': 'psg',
        },
      ]),
      throwsFormatException,
    );
  });
}
