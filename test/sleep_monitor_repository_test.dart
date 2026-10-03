import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'support/sleep_bedside_fixture.dart';
import 'support/test_db.dart';

void main() {
  late Database database;
  late SleepMonitorRepository repository;

  test(
    'quiet bedside night is saved once with a usable estimate without breathing',
    () async {
      final session = bedsideSession(minutes: 240);
      final spool = <String, dynamic>{
        'session': session.toMap(),
        'segments': [for (var i = 0; i < 480; i++) bedsideSegment(i).toMap()],
      };
      final imported = await repository.importNativeSpool(spool);
      expect(imported.estimatedSleepMinutes, greaterThan(210));
      expect(imported.estimatedSleepMinutes, lessThan(240));
      expect(imported.sleepOnsetAt, isNotNull);
      // The user is known awake when recording starts; silence becomes sleep
      // a few minutes later (the settling prior of the model).
      expect(imported.sleepLatencyMinutes, inInclusiveRange(4, 10));
      expect(imported.unknownMinutes, 0);
      expect(imported.awakeMinutes, inInclusiveRange(4, 10));
      expect(imported.restlessSleepMinutes, 0);
      expect(imported.snoreMinutes, 0);
      expect(imported.deepSleepMinutes, isNull);
      expect(imported.stageConfidence, isNull);
      expect(imported.sleepEntryId, isNotNull);
      expect(await repository.getUnestimatedSessions(), isEmpty);
      await repository.importNativeSpool(spool);
      expect((await database.query('sleep_monitor_sessions')).length, 1);
      expect(await database.query('sleep_entries'), hasLength(1));
    },
  );

  test('keeps the smart alarm result and the morning answer', () async {
    final session = bedsideSession(minutes: 240);
    final alarmAt = session.endedAt!.add(const Duration(minutes: 9));
    final imported = await repository.importNativeSpool({
      'session': {
        ...session.toMap(),
        'alarm_at': alarmAt.toIso8601String(),
        'end_reason': 'alarm',
        'smart_window_minutes': 30,
        'alarm_fired_at': session.endedAt!.toIso8601String(),
        'alarm_trigger': SleepMonitorSession.triggerStirring,
      },
      'segments': [for (var i = 0; i < 480; i++) bedsideSegment(i).toMap()],
    });
    expect(imported.smartWindowMinutes, 30);
    expect(imported.alarmTrigger, SleepMonitorSession.triggerStirring);
    expect(imported.smartWakeLeadMinutes, 9);

    await repository.setWakeFeeling(imported.id, 3);
    final stored = await repository.getSession(imported.id);
    expect(stored!.wakeFeeling, SleepMonitorSession.feelingRefreshed);
    expect(stored.alarmFiredAt, session.endedAt);
  });

  test(
    'bedside inference accepts short sessions and keeps aggregate source version',
    () async {
      final imported = await repository.importNativeSpool({
        'session': bedsideSession(minutes: 60).toMap(),
        'segments': [
          for (var i = 0; i < 120; i++)
            bedsideSegment(i, periodic: true).toMap(),
        ],
      });
      expect(imported.estimatedSleepMinutes, greaterThan(45));
      expect(imported.stageAlgorithmVersion, 'sleep-wake-bedside-v6');
      expect(imported.finalWakeAt, isNull);
      expect(imported.deepSleepMinutes, isNull);
      expect(imported.sleepEntryId, isNotNull);
    },
  );

  test(
    'missing or invalid capture still leaves the night incomplete',
    () async {
      for (final invalid in [false, true]) {
        final imported = await repository.importNativeSpool({
          'session': bedsideSession(minutes: 240).toMap(),
          'segments': [
            for (var i = 0; i < (invalid ? 480 : 40); i++)
              bedsideSegment(i, invalid: invalid).toMap(),
          ],
        });
        expect(imported.estimatedSleepMinutes, isNull);
        expect(imported.sleepEntryId, isNull);
        expect(await repository.getUnestimatedSessions(), hasLength(1));
        expect(await database.query('sleep_entries'), isEmpty);
      }
    },
  );

  test(
    'recorded quantized bedside audio produces an entry instead of incomplete alert',
    () async {
      final spool = <String, dynamic>{
        'session': bedsideSession(minutes: 425).toMap(),
        'segments': quantizedBedsideSegments().map((s) => s.toMap()).toList(),
      };
      final result = await repository.importNativeSpool(spool);
      expect(result.estimatedSleepMinutes, greaterThan(0));
      expect(result.estimatedSleepMinutes, lessThan(425));
      expect(result.unknownMinutes, lessThan(85));
      expect(result.sleepEntryId, isNotNull);
      expect(await repository.getUnestimatedSessions(), isEmpty);
      await repository.importNativeSpool(spool);
      expect(await database.query('sleep_entries'), hasLength(1));
    },
  );

  test(
    'archive repairs an existing incomplete night once and keeps alarm metadata',
    () async {
      final oldSession = bedsideSession(minutes: 425).copyWith(
        stageAlgorithmVersion: 'sleep-wake-bedside-v2',
        unknownMinutes: 386,
      );
      await database.insert('sleep_monitor_sessions', oldSession.toMap());
      final archive = <String, dynamic>{
        'session': oldSession.toMap(),
        'segments': quantizedBedsideSegments().map((s) => s.toMap()).toList(),
      };
      final dismissedAt = oldSession.endedAt!.add(const Duration(minutes: 15));
      await repository.markAlarmDismissed(
        oldSession.id,
        'barcode',
        dismissedAt,
      );
      final result = await repository.reprocessDiagnostic(archive);
      expect(result!.estimatedSleepMinutes, greaterThan(0));
      expect(result.stageAlgorithmVersion, 'sleep-wake-bedside-v6');
      expect(result.alarmDismissedAt, dismissedAt);
      expect(await repository.reprocessDiagnostic(archive), isNull);
      expect(await database.query('sleep_entries'), hasLength(1));
      await repository.deleteSession(oldSession.id);
      expect(await repository.reprocessDiagnostic(archive), isNull);
      expect(await repository.getSession(oldSession.id), isNull);
    },
  );

  test(
    'reanalysis transaction cannot recreate a concurrently deleted session',
    () async {
      await expectLater(
        repository.importNativeSpool({
          'session': bedsideSession().toMap(),
          'segments': [for (var i = 0; i < 120; i++) bedsideSegment(i).toMap()],
        }, expectedStageVersion: 'sleep-wake-bedside-v2'),
        throwsStateError,
      );
      expect(await database.query('sleep_monitor_sessions'), isEmpty);
      expect(await database.query('sleep_entries'), isEmpty);
    },
  );

  test(
    'archive recovery preserves a manual entry added after the failed night',
    () async {
      final old = bedsideSession(
        minutes: 425,
      ).copyWith(stageAlgorithmVersion: 'sleep-wake-bedside-v2');
      await database.insert('sleep_monitor_sessions', old.toMap());
      await database.insert('sleep_entries', {
        'id': 'manual',
        'date': '2026-09-02',
        'sleep_minutes': 360,
        'actual_sleep_minutes': 355,
        'source': 'manual',
        'comment': 'My correction',
        'created_at': bedsideStart.toIso8601String(),
      });
      final before = await database.query('sleep_entries');
      final repaired = await repository.reprocessDiagnostic({
        'session': old.toMap(),
        'segments': quantizedBedsideSegments().map((s) => s.toMap()).toList(),
      });
      expect(repaired!.sleepEntryId, 'manual');
      expect(await database.query('sleep_entries'), before);
    },
  );

  test(
    'v3 incomplete night is reprocessed from its archive and saved once',
    () async {
      final old = bedsideSession(minutes: 369).copyWith(
        stageAlgorithmVersion: 'sleep-wake-bedside-v3',
        unknownMinutes: 114,
        sleepingMinutes: 228,
      );
      await database.insert('sleep_monitor_sessions', old.toMap());
      final archive = <String, dynamic>{
        'session': old.toMap(),
        'segments': quantizedBedsideSegments(
          fileName: 'sleep_ambiguous_bedside.json',
        ).map((s) => s.toMap()).toList(),
      };
      final repaired = await repository.reprocessDiagnostic(archive);
      expect(repaired!.stageAlgorithmVersion, 'sleep-wake-bedside-v6');
      expect(repaired.estimatedSleepMinutes, isNotNull);
      expect(repaired.unknownMinutes, lessThan(369 * 0.2));
      expect(await repository.getUnestimatedSessions(), isEmpty);
      expect(await repository.reprocessDiagnostic(archive), isNull);
      expect(await database.query('sleep_entries'), hasLength(1));
    },
  );

  group('night timeline', () {
    Map<String, dynamic> quietNight() => {
      'session': bedsideSession(minutes: 240).toMap(),
      'segments': [for (var i = 0; i < 480; i++) bedsideSegment(i).toMap()],
    };

    test('import stores the minute-by-minute night for the chart', () async {
      final imported = await repository.importNativeSpool(quietNight());
      final stored = (await repository.getSession(imported.id))!;
      final timeline = stored.timeline!;
      expect(timeline.length, 240);
      expect(timeline.stages.first, SleepStageType.awake);
      expect(timeline.stages.last, SleepStageType.sleeping);
      expect(stored.stageTimeline!.length, lessThan(2000));
    });

    Future<SleepMonitorSession> olderNight({required int entryEstimate}) async {
      final imported = await repository.importNativeSpool(quietNight());
      await database.update(
        'sleep_monitor_sessions',
        {
          'stage_algorithm_version': 'sleep-wake-bedside-v5',
          'stage_timeline': null,
          'estimated_sleep_minutes': 180,
          'restless_sleep_minutes': null,
        },
        where: 'id = ?',
        whereArgs: [imported.id],
      );
      await database.update(
        'sleep_entries',
        {
          'estimated_sleep_minutes': entryEstimate,
          'sleep_minutes': entryEstimate,
        },
        where: 'id = ?',
        whereArgs: [imported.sleepEntryId],
      );
      return (await repository.getSession(imported.id))!;
    }

    test('an older night is re-staged once from its archive', () async {
      final old = await olderNight(entryEstimate: 180);
      expect(
        (await repository.getSessionsNeedingAnalysisRefresh()).map((s) => s.id),
        [old.id],
      );
      final refreshed = await repository.refreshAnalysis(quietNight());
      expect(
        refreshed!.stageAlgorithmVersion,
        SleepWakeEngine.algorithmVersion,
      );
      final stored = (await repository.getSession(old.id))!;
      expect(stored.timeline, isNotNull);
      expect(stored.restlessSleepMinutes, 0);
      expect(stored.estimatedSleepMinutes, greaterThan(220));
      // The entry still carried this session's estimate, so it follows.
      final entry = (await repository.getSleepEntry(old.sleepEntryId!))!;
      expect(entry.estimatedSleepMinutes, stored.estimatedSleepMinutes);
      expect(entry.sleepMinutes, stored.estimatedSleepMinutes);
      expect(await repository.getSessionsNeedingAnalysisRefresh(), isEmpty);
      expect(await repository.refreshAnalysis(quietNight()), isNull);
    });

    test('re-staging never overwrites an entry that changed since', () async {
      final old = await olderNight(entryEstimate: 150);
      expect(await repository.refreshAnalysis(quietNight()), isNotNull);
      final entry = (await repository.getSleepEntry(old.sleepEntryId!))!;
      expect(entry.estimatedSleepMinutes, 150);
      expect(entry.sleepMinutes, 150);
    });
  });

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await installTestDb();
    repository = SleepMonitorRepository();
  });

  tearDown(uninstallTestDb);

  test('serializes monitor models and calculates aggregate metrics', () {
    final segment = SleepMonitorSegment(
      id: 'seg-1',
      sessionId: 'session-1',
      startedAt: DateTime.utc(2026, 7, 26, 22),
      durationSeconds: 30,
      audioRmsDbfs: -50,
      audioPeakDbfs: -20,
      noiseScore: 4,
      classification: 'quiet',
      validFraction: 1,
      noiseBurstCount: 0,
    );
    final session = SleepMonitorSession(
      id: 'session-1',
      sleepEntryId: null,
      status: SleepMonitorSession.completed,
      startedAt: segment.startedAt,
      endedAt: segment.startedAt.add(const Duration(seconds: 60)),
      alarmAt: segment.startedAt.add(const Duration(hours: 8)),
      utcOffsetStartMinutes: -180,
      utcOffsetEndMinutes: -180,
      sensorMode: 'audio',
      algorithmVersion: SleepMonitorSession.defaultAlgorithmVersion,
      timeInBedMinutes: 1,
      quietMinutes: 1,
      noisyMinutes: 0,
      estimatedSleepMinutes: null,
      noiseEventCount: 0,
      signalQualityScore: 1,
      endReason: SleepMonitorSession.endUser,
      createdAt: segment.startedAt,
    );
    expect(
      SleepMonitorSegment.fromMap(segment.toMap()).classification,
      'quiet',
    );
    final restored = SleepMonitorSession.fromMap(session.toMap());
    expect(restored.id, 'session-1');
    expect(restored.alarmAt, session.alarmAt);
  });

  test(
    'imports idempotently and computes quiet/noisy periods and events',
    () async {
      final start = DateTime.utc(2026, 7, 26, 22);
      final spool = _spool(start, status: SleepMonitorSession.completed);
      final first = await repository.importNativeSpool(spool);
      final second = await repository.importNativeSpool(spool);

      expect(first.id, second.id);
      expect(await database.query('sleep_monitor_sessions'), hasLength(1));
      expect(first.quietMinutes, 1);
      expect(first.noisyMinutes, 1);
      expect(first.noiseEventCount, 2);
      expect(
        (await database.query('sleep_entries')).single['source'],
        'monitored',
      );
      final entry = await SleepRepository().getLatest();
      expect(entry?.bedtimeMinutes, 19 * 60);
      expect(entry?.wakeTimeMinutes, 19 * 60 + 2);
    },
  );

  test('recovers unfinished spool using the last segment as end', () async {
    final start = DateTime.utc(2026, 7, 28, 22);
    final imported = await repository.importNativeSpool(
      _spool(start, status: SleepMonitorSession.running, segmentCount: 1),
    );
    expect(imported.status, SleepMonitorSession.interrupted);
    expect(imported.endReason, SleepMonitorSession.endProcessRecovered);
    expect(imported.endedAt, start.add(const Duration(seconds: 30)));
  });

  test('persists failed session without creating a sleep entry', () async {
    final imported = await repository.importNativeSpool(
      _spool(DateTime.utc(2026, 7, 28, 22), status: SleepMonitorSession.failed),
    );

    expect(imported.sleepEntryId, isNull);
    expect(await database.query('sleep_entries'), isEmpty);
    expect(await database.query('sleep_monitor_sessions'), hasLength(1));
  });

  test('does not create a sleep entry for a sub-minute test session', () async {
    final imported = await repository.importNativeSpool(
      _spool(
        DateTime.utc(2026, 7, 28, 22),
        status: SleepMonitorSession.completed,
        segmentCount: 1,
        durationSeconds: 30,
      ),
    );

    expect(imported.timeInBedMinutes, 1);
    expect(imported.sleepEntryId, isNull);
    expect(await database.query('sleep_entries'), isEmpty);
  });

  test('uses the recorded UTC offset to select the sleep date', () async {
    final start = DateTime.utc(2026, 7, 27, 1);
    await repository.importNativeSpool(
      _spool(start, status: SleepMonitorSession.completed),
    );

    final entry = await SleepRepository().getByDate(DateTime(2026, 7, 26));
    expect(entry, isNotNull);
  });

  test('does not stage retired audio-features-v2 nights', () async {
    final imported = await repository.importNativeSpool(
      _featureSpool(DateTime.utc(2026, 8, 2, 22)),
    );

    expect(
      imported.analysisStatus,
      SleepMonitorSession.analysisLegacyUnavailable,
    );
    expect(imported.stageAlgorithmVersion, isNull);
    expect(imported.sleepingMinutes, isNull);
    expect(imported.deepSleepMinutes, isNull);
  });

  test('keeps legacy noise nights as legacy_unavailable', () async {
    final imported = await repository.importNativeSpool(
      _spool(
        DateTime.utc(2026, 8, 2, 22),
        status: SleepMonitorSession.completed,
        segmentCount: 8,
        durationMinutes: 4,
      ),
    );

    expect(
      imported.analysisStatus,
      SleepMonitorSession.analysisLegacyUnavailable,
    );
  });

  test('deleting a sleep entry cascades its sessions', () async {
    final imported = await repository.importNativeSpool(
      _spool(
        DateTime.utc(2026, 7, 29, 22),
        status: SleepMonitorSession.completed,
      ),
    );
    final entryId = imported.sleepEntryId!;
    await SleepRepository().delete(entryId);
    expect(await database.query('sleep_monitor_sessions'), isEmpty);
  });
}

/// A 4-hour night carrying spectral + motion features from the retired
/// audio-features-v2 recorder.
Map<String, dynamic> _featureSpool(DateTime start) {
  const hours = 4;
  const segmentCount = hours * 2 * 60;
  final segments = List.generate(segmentCount, (index) {
    final offsetSeconds = index * 30;
    final awake =
        offsetSeconds < 4 * 60 || offsetSeconds >= (hours * 3600 - 4 * 60);
    return {
      'id': 'feature-segment-$index',
      'session_id': 'feature-session',
      'started_at': start
          .add(Duration(seconds: offsetSeconds))
          .toIso8601String(),
      'duration_seconds': 30,
      'audio_rms_dbfs': awake ? -25 : -40,
      'audio_peak_dbfs': awake ? -10 : -25,
      'noise_score': awake ? 14 : 2,
      'classification': awake ? 'noise' : 'quiet',
      'valid_fraction': 1.0,
      'noise_burst_count': awake ? 10 : 0,
      'spectral_band_energy_0': 20.0,
      'spectral_band_energy_1': 30.0,
      'spectral_band_energy_2': 40.0,
      'spectral_band_energy_3': awake ? 120.0 : 5.0,
      'spectral_band_energy_4': awake ? 80.0 : 2.0,
      'spectral_flatness': awake ? 0.7 : 0.3,
      'spectral_centroid_hz': 1200.0,
      'breathing_regularity': awake ? 0.1 : 0.4,
      'breathing_rate_hz': 0.25,
      'motion_active_seconds': awake ? 15.0 : 0.5,
      'motion_mean_deviation_g': 0.02,
      'motion_max_deviation_g': 0.05,
    };
  });
  final end = start.add(const Duration(hours: hours));
  return {
    'session': {
      'id': 'feature-session',
      'sleep_entry_id': null,
      'status': SleepMonitorSession.completed,
      'started_at': start.toIso8601String(),
      'ended_at': end.toIso8601String(),
      'alarm_at': null,
      'utc_offset_start_minutes': 0,
      'utc_offset_end_minutes': 0,
      'sensor_mode': 'audio',
      'algorithm_version': 'audio-features-v2',
      'time_in_bed_minutes': hours * 60,
      'quiet_minutes': hours * 60 - 8,
      'noisy_minutes': 8,
      'estimated_sleep_minutes': null,
      'noise_event_count': 0,
      'signal_quality_score': 1.0,
      'end_reason': 'user',
      'created_at': start.toIso8601String(),
    },
    'segments': segments,
  };
}

Map<String, dynamic> _spool(
  DateTime start, {
  required String status,
  int segmentCount = 4,
  int durationMinutes = 2,
  int? durationSeconds,
}) {
  final duration = Duration(seconds: durationSeconds ?? durationMinutes * 60);
  final end = start.add(duration);
  final segments = List.generate(segmentCount, (index) {
    final noise = index == 1 || index == segmentCount - 1;
    return {
      'id': 'segment-$index',
      'session_id': 'session-1',
      'started_at': start.add(Duration(seconds: index * 30)).toIso8601String(),
      'duration_seconds': 30,
      'audio_rms_dbfs': noise ? -20 : -50,
      'audio_peak_dbfs': noise ? -8 : -30,
      'noise_score': noise ? 12 : 2,
      'classification': noise ? 'noise' : 'quiet',
      'valid_fraction': 1.0,
      'noise_burst_count': noise ? 2 : 0,
    };
  });
  return {
    'session': {
      'id': 'session-1',
      'sleep_entry_id': null,
      'status': status,
      'started_at': start.toIso8601String(),
      'ended_at': status == SleepMonitorSession.running
          ? null
          : end.toIso8601String(),
      'alarm_at': start.add(const Duration(hours: 8)).toIso8601String(),
      'utc_offset_start_minutes': -180,
      'utc_offset_end_minutes': -180,
      'sensor_mode': 'audio',
      'algorithm_version': SleepMonitorSession.defaultAlgorithmVersion,
      'time_in_bed_minutes': (duration.inSeconds / 60).ceil(),
      'quiet_minutes': 1,
      'noisy_minutes': 1,
      'estimated_sleep_minutes': null,
      'noise_event_count': 2,
      'signal_quality_score': 1.0,
      'end_reason': status == SleepMonitorSession.running ? null : 'user',
      'created_at': start.toIso8601String(),
    },
    'segments': segments,
  };
}
