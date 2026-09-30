import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/services/run_data_fields_store.dart';
import 'package:workout_notes/utils/run_data_field_values.dart';

RunTrackingState _state({
  double distance = 5230,
  int duration = 1650,
  int moving = 1600,
  double? pace = 300,
  RunSplit? partial,
  List<RunSplit> splits = const [],
  RunLap? lap,
  bool autoPaused = false,
}) => RunTrackingState(
  supported: true,
  locationGranted: true,
  status: RunTrackingState.recording,
  activityId: 'a',
  startedAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
  distanceMeters: distance,
  durationSeconds: duration,
  movingTimeSeconds: moving,
  currentPaceSecPerKm: pace,
  lat: 1,
  lng: 1,
  accuracyMeters: 5,
  trail: const [],
  splits: splits,
  currentSplit: partial,
  errorCode: null,
  errorMessage: null,
  autoPaused: autoPaused,
  currentLap: lap,
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    Intl.defaultLocale = 'en';
  });

  group('RunDataFieldLayout', () {
    test('keeps the 3..6 range and drops duplicates', () {
      expect(
        RunDataFieldLayout.sanitize([RunDataField.time]),
        hasLength(RunDataFieldLayout.minFields),
      );
      final many = RunDataFieldLayout.sanitize([
        ...RunDataField.values,
        RunDataField.time,
      ]);
      expect(many, hasLength(RunDataFieldLayout.maxFields));
      expect(many.toSet(), hasLength(many.length));
      expect(many.first, RunDataField.time);
    });

    test('tops a short list up without reordering the choices', () {
      final fields = RunDataFieldLayout.sanitize([
        RunDataField.avgPace,
        RunDataField.kmPace,
      ]);
      expect(fields.take(2), [RunDataField.avgPace, RunDataField.kmPace]);
      expect(fields, hasLength(3));
    });

    test('storage round-trips and ignores unknown values', () {
      final stored = RunDataFieldLayout.toStorage([
        RunDataField.lapTime,
        RunDataField.calories,
        RunDataField.clock,
        RunDataField.distance,
      ]);
      expect(RunDataFieldLayout.fromStorage(stored), [
        RunDataField.lapTime,
        RunDataField.calories,
        RunDataField.clock,
        RunDataField.distance,
      ]);
      expect(
        RunDataFieldLayout.fromStorage(['nope', 'time', 'pace', 'distance']),
        [RunDataField.time, RunDataField.pace, RunDataField.distance],
      );
      expect(RunDataFieldLayout.fromStorage(null), RunDataFieldLayout.defaults);
    });

    test('grid rows keep numbers large: 3, 2+2, 3+2, 3+3', () {
      expect(RunDataFieldLayout.rowsFor(3), [3]);
      expect(RunDataFieldLayout.rowsFor(4), [2, 2]);
      expect(RunDataFieldLayout.rowsFor(5), [3, 2]);
      expect(RunDataFieldLayout.rowsFor(6), [3, 3]);
    });

    test('indoor sessions use a fixed no-GPS layout', () {
      expect(RunDataFieldLayout.fixedFor(CardioActivityType.running), isNull);
      for (final type in [
        CardioActivityType.treadmill,
        CardioActivityType.stationaryBike,
      ]) {
        final fixed = RunDataFieldLayout.fixedFor(type)!;
        expect(fixed.any((field) => field.needsGps), isFalse);
      }
    });
  });

  group('RunDataFieldValues', () {
    final now = DateTime(2026, 1, 1, 7, 5);

    RunDataValue value(RunDataField field, RunTrackingState state) =>
        RunDataFieldValues.of(field, state: state, now: now);

    test('formats the core fields', () {
      final state = _state();
      expect(value(RunDataField.time, state), const RunDataValue('27:30'));
      expect(value(RunDataField.distance, state).unit, 'km');
      expect(value(RunDataField.distance, state).value, '5.23');
      expect(
        value(RunDataField.pace, state),
        const RunDataValue('05:00', '/km'),
      );
      // 1600 s over 5.23 km.
      expect(value(RunDataField.avgPace, state).value, '05:06');
    });

    test('pace is blank while auto-paused', () {
      expect(value(RunDataField.pace, _state(autoPaused: true)).value, '--:--');
    });

    test('km pace prefers the partial split, then the last full one', () {
      const full = RunSplit(
        km: 4,
        distanceMeters: 1000,
        durationSeconds: 290,
        paceSecPerKm: 290,
        isPartial: false,
      );
      const early = RunSplit(
        km: 5,
        distanceMeters: 10,
        durationSeconds: 3,
        paceSecPerKm: 600,
        isPartial: true,
      );
      const mid = RunSplit(
        km: 5,
        distanceMeters: 230,
        durationSeconds: 70,
        paceSecPerKm: 304,
        isPartial: true,
      );
      expect(
        value(
          RunDataField.kmPace,
          _state(splits: [full], partial: early),
        ).value,
        '04:50',
      );
      expect(
        value(RunDataField.kmPace, _state(splits: [full], partial: mid)).value,
        '05:04',
      );
    });

    test('lap fields follow the current lap', () {
      const lap = RunLap(
        index: 2,
        startDistanceMeters: 2000,
        distanceMeters: 640,
        durationSeconds: 195,
        paceSecPerKm: 305,
      );
      final state = _state(lap: lap);
      expect(value(RunDataField.lapTime, state).value, '03:15');
      expect(value(RunDataField.lapDistance, state).value, '0.64');
      expect(value(RunDataField.lapTime, _state()).value, '--:--');
    });

    test('calories use the same estimate as the saved activity', () {
      final outdoor = RunDataFieldValues.of(
        RunDataField.calories,
        state: _state(distance: 5000),
        now: now,
        bodyWeightKg: 80,
      );
      expect(outdoor, const RunDataValue('400', 'kcal'));
      // Treadmill without a distance falls back to a MET-by-time estimate.
      final treadmill = RunDataFieldValues.of(
        RunDataField.calories,
        state: _state(distance: 0, moving: 1800),
        now: now,
        activityType: CardioActivityType.treadmill,
        bodyWeightKg: 70,
      );
      expect(int.parse(treadmill.value), inInclusiveRange(250, 400));
    });

    test('clock shows the time of day', () {
      expect(value(RunDataField.clock, _state()).value, '07:05');
    });
  });

  group('RunDataFieldsStore', () {
    test('persists the chosen layout', () async {
      SharedPreferences.setMockInitialValues({});
      expect(
        await RunDataFieldsStore.instance.load(),
        RunDataFieldLayout.defaults,
      );
      await RunDataFieldsStore.instance.save([
        RunDataField.time,
        RunDataField.avgPace,
        RunDataField.lapTime,
        RunDataField.calories,
      ]);
      expect(await RunDataFieldsStore.instance.load(), [
        RunDataField.time,
        RunDataField.avgPace,
        RunDataField.lapTime,
        RunDataField.calories,
      ]);
    });
  });
}
