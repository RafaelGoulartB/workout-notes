import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

void main() {
  late Database database;
  late SleepMonitorRepository repository;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE sleep_entries (
              id TEXT PRIMARY KEY,
              date TEXT NOT NULL UNIQUE,
              sleep_minutes INTEGER NOT NULL,
              actual_sleep_minutes INTEGER,
              bedtime_minutes INTEGER,
              wake_time_minutes INTEGER,
              comment TEXT,
              source TEXT NOT NULL DEFAULT 'monitored',
              time_in_bed_minutes INTEGER,
              estimated_sleep_minutes INTEGER,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE sleep_monitor_sessions (
              id TEXT PRIMARY KEY,
              sleep_entry_id TEXT,
              status TEXT NOT NULL,
              started_at TEXT NOT NULL,
              ended_at TEXT,
              alarm_at TEXT,
              monitor_mode TEXT,
              mission_type TEXT,
              alarm_dismiss_method TEXT,
              alarm_dismissed_at TEXT,
              utc_offset_start_minutes INTEGER NOT NULL,
              utc_offset_end_minutes INTEGER,
              sensor_mode TEXT NOT NULL DEFAULT 'audio',
              algorithm_version TEXT NOT NULL,
              time_in_bed_minutes INTEGER,
              quiet_minutes INTEGER,
              noisy_minutes INTEGER,
              estimated_sleep_minutes INTEGER,
              noise_event_count INTEGER NOT NULL DEFAULT 0,
              signal_quality_score REAL,
              end_reason TEXT,
              analysis_status TEXT NOT NULL DEFAULT 'legacy_unavailable',
              sleep_onset_at TEXT,
              final_wake_at TEXT,
              sleep_latency_minutes INTEGER,
              awake_minutes INTEGER,
              sleeping_minutes INTEGER,
              deep_sleep_minutes INTEGER,
              unknown_minutes INTEGER,
              awakening_count INTEGER,
              sleep_efficiency REAL,
              stage_confidence REAL,
              stage_algorithm_version TEXT,
              created_at TEXT NOT NULL,
              FOREIGN KEY (sleep_entry_id) REFERENCES sleep_entries(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE sleep_monitor_segments (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              started_at TEXT NOT NULL,
              duration_seconds INTEGER NOT NULL,
              audio_rms_dbfs REAL,
              audio_peak_dbfs REAL,
              noise_score REAL,
              classification TEXT NOT NULL,
              valid_fraction REAL NOT NULL,
              noise_burst_count INTEGER NOT NULL DEFAULT 0,
              spectral_band_energy_0 REAL,
              spectral_band_energy_1 REAL,
              spectral_band_energy_2 REAL,
              spectral_band_energy_3 REAL,
              spectral_band_energy_4 REAL,
              spectral_flatness REAL,
              spectral_centroid_hz REAL,
              breathing_regularity REAL,
              breathing_rate_hz REAL,
              motion_active_seconds REAL,
              motion_mean_deviation_g REAL,
              motion_max_deviation_g REAL,
              FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('''
            CREATE TABLE sleep_stage_epochs (
              id TEXT PRIMARY KEY,
              session_id TEXT NOT NULL,
              started_at TEXT NOT NULL,
              duration_seconds INTEGER NOT NULL,
              stage TEXT NOT NULL,
              confidence REAL NOT NULL,
              awake_probability REAL NOT NULL,
              sleeping_probability REAL NOT NULL,
              deep_probability REAL NOT NULL,
              algorithm_version TEXT NOT NULL,
              source TEXT NOT NULL DEFAULT 'acoustic_model',
              FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE,
              UNIQUE (session_id, started_at)
            )
          ''');
        },
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = SleepMonitorRepository();
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

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

  test('counts current and legacy emergency dismissals only', () async {
    final start = DateTime.utc(2026, 8, 1, 22);
    final methods = <String>[
      SleepMonitorSession.dismissEmergency500Taps,
      SleepMonitorSession.dismissEmergency1000Taps,
      SleepMonitorSession.dismissEmergency100Taps,
      SleepMonitorSession.dismissBarcode,
      SleepMonitorSession.dismissButton,
    ];

    for (var index = 0; index < methods.length; index++) {
      await database.insert('sleep_monitor_sessions', {
        'id': 'emergency-session-$index',
        'status': SleepMonitorSession.completed,
        'started_at': start.toIso8601String(),
        'utc_offset_start_minutes': -180,
        'sensor_mode': 'audio',
        'algorithm_version': SleepMonitorSession.defaultAlgorithmVersion,
        'alarm_dismiss_method': methods[index],
        'created_at': start.toIso8601String(),
      });
    }

    expect(await repository.getEmergencyDismissalCount(), 3);
  });

  test(
    'imports idempotently and computes quiet/noisy periods and events',
    () async {
      final start = DateTime.utc(2026, 7, 26, 22);
      final spool = _spool(start, status: SleepMonitorSession.completed);
      final first = await repository.importNativeSpool(spool);
      final second = await repository.importNativeSpool(spool);

      expect(first.id, second.id);
      expect(await repository.getSessions(), hasLength(1));
      expect(await repository.getSegments(first.id), isEmpty);
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
    expect(await repository.getSessions(), hasLength(1));
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

  test(
    'imports validated model stages and derives the nightly summary',
    () async {
      final start = DateTime.utc(2026, 8, 1, 22);
      final spool = _spool(
        start,
        status: SleepMonitorSession.completed,
        segmentCount: 24,
        durationMinutes: 12,
      );
      final sessionMap = spool['session'] as Map<String, dynamic>;
      sessionMap['algorithm_version'] = 'audio-features-v2';
      spool['stage_epochs'] = List.generate(24, (index) {
        final stage = index < 4
            ? SleepStageType.awake
            : index < 20
            ? SleepStageType.sleeping
            : SleepStageType.deep;
        return {
          'id': 'stage-$index',
          'session_id': 'session-1',
          'started_at': start
              .add(Duration(seconds: index * 30))
              .toIso8601String(),
          'duration_seconds': 30,
          'stage': stage.name,
          'confidence': 0.85,
          'awake_probability': stage == SleepStageType.awake ? 0.9 : 0.05,
          'sleeping_probability': stage == SleepStageType.sleeping ? 0.9 : 0.05,
          'deep_probability': stage == SleepStageType.deep ? 0.9 : 0.05,
          'algorithm_version': 'acoustic-staging-test',
          'source': 'acoustic_model',
        };
      });

      final imported = await repository.importNativeSpool(spool);
      final stages = await repository.getStageEpochs(imported.id);
      final summary = await repository.getNightSummary(imported.sleepEntryId!);

      expect(imported.analysisStatus, SleepMonitorSession.analysisAvailable);
      expect(stages, isEmpty);
      expect(summary, isNotNull);
      expect(
        summary!.session?.sleepOnsetAt,
        start.add(const Duration(minutes: 2)),
      );
      expect(summary.session?.sleepingMinutes, 8);
      expect(summary.session?.deepSleepMinutes, 2);
      expect(summary.entry.estimatedSleepMinutes, 10);
      expect(summary.entry.sleepMinutes, 10);
    },
  );

  test('runs the heuristic engine for feature nights and persists aggregates', () async {
    final start = DateTime.utc(2026, 8, 2, 22);
    final imported = await repository.importNativeSpool(_featureSpool(start));
    final stages = await repository.getStageEpochs(imported.id);

    expect(imported.analysisStatus, SleepMonitorSession.analysisAvailable);
    expect(imported.stageAlgorithmVersion, SleepStageEngine.algorithmVersion);
    expect(stages, isEmpty);
    final summary = await repository.getNightSummary(imported.sleepEntryId!);
    expect(summary, isNotNull);
    expect(summary!.session?.sleepingMinutes, isNotNull);
    expect(summary.session?.deepSleepMinutes, isNotNull);
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

    expect(imported.analysisStatus, SleepMonitorSession.analysisLegacyUnavailable);
    expect(await repository.getStageEpochs(imported.id), isEmpty);
  });

  test(
    'legacy repair replaces the full monitored window with inference',
    () async {
      final start = DateTime.utc(2026, 8, 1, 2, 49);
      const monitoredMinutes = 431;
      const segmentSeconds = 30;
      const entryId = 'legacy-entry-01-08';
      await database.insert('sleep_entries', {
        'id': entryId,
        'date': '2026-08-01',
        'sleep_minutes': monitoredMinutes,
        'actual_sleep_minutes': null,
        'bedtime_minutes': 2 * 60 + 49,
        'wake_time_minutes': 10 * 60,
        'comment': null,
        'source': 'monitored',
        'time_in_bed_minutes': monitoredMinutes,
        'estimated_sleep_minutes': null,
        'created_at': start.toIso8601String(),
      });
      await database.insert(
        'sleep_monitor_sessions',
        SleepMonitorSession(
          id: 'legacy-01-08',
          sleepEntryId: entryId,
          status: SleepMonitorSession.completed,
          startedAt: start,
          endedAt: start.add(const Duration(minutes: monitoredMinutes)),
          utcOffsetStartMinutes: -180,
          utcOffsetEndMinutes: -180,
          sensorMode: 'audio',
          algorithmVersion: SleepMonitorSession.defaultAlgorithmVersion,
          timeInBedMinutes: monitoredMinutes,
          quietMinutes: monitoredMinutes - 25,
          noisyMinutes: 25,
          estimatedSleepMinutes: null,
          noiseEventCount: 1,
          signalQualityScore: 1,
          endReason: SleepMonitorSession.endUser,
          createdAt: start,
        ).toMap(),
      );
      final segments = List.generate(monitoredMinutes * 2, (index) {
        final offsetSeconds = index * segmentSeconds;
        final noisy = offsetSeconds >= 5 * 60 && offsetSeconds < 30 * 60;
        return SleepMonitorSegment(
          id: 'legacy-segment-$index',
          sessionId: 'legacy-01-08',
          startedAt: start.add(Duration(seconds: offsetSeconds)),
          durationSeconds: segmentSeconds,
          audioRmsDbfs: noisy ? -20 : -50,
          audioPeakDbfs: noisy ? -8 : -30,
          noiseScore: noisy ? 20 : 2,
          classification: noisy ? 'noise' : 'quiet',
          validFraction: 1,
          noiseBurstCount: noisy ? 1 : 0,
        ).toMap();
      });
      final batch = database.batch();
      for (final segment in segments) {
        batch.insert('sleep_monitor_segments', segment);
      }
      await batch.commit(noResult: true);

      await repository.repairSleepEntriesFromSessions();

      final repaired = await SleepRepository().getByDate(DateTime(2026, 8, 1));
      expect(repaired?.sleepMinutes, inInclusiveRange(399, 402));
      expect(repaired?.estimatedSleepMinutes, repaired?.sleepMinutes);
      final repairedSession = await repository.getSession('legacy-01-08');
      expect(
        repairedSession?.analysisStatus,
        SleepMonitorSession.analysisLegacyUnavailable,
      );
    },
  );

  test('deleting a sleep entry cascades sessions and segments', () async {
    final imported = await repository.importNativeSpool(
      _spool(
        DateTime.utc(2026, 7, 29, 22),
        status: SleepMonitorSession.completed,
      ),
    );
    final entryId = imported.sleepEntryId!;
    await SleepRepository().delete(entryId);
    expect(await database.query('sleep_monitor_sessions'), isEmpty);
    expect(await database.query('sleep_monitor_segments'), isEmpty);
  });
}

/// A 4-hour night carrying v28 spectral + motion features (audio-features-v2)
/// with no native stage epochs, so the heuristic engine must run on import.
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
      'started_at': start.add(Duration(seconds: offsetSeconds)).toIso8601String(),
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
