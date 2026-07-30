import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';

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
              source TEXT NOT NULL DEFAULT 'manual',
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
              FOREIGN KEY (session_id) REFERENCES sleep_monitor_sessions(id) ON DELETE CASCADE
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
    expect(SleepMonitorSession.fromMap(session.toMap()).id, 'session-1');
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
      expect(await repository.getSegments(first.id), hasLength(4));
      expect(first.quietMinutes, 1);
      expect(first.noisyMinutes, 1);
      expect(first.noiseEventCount, 2);
      expect(
        (await database.query('sleep_entries')).single['source'],
        'monitored',
      );
    },
  );

  test(
    'merges with manual entry preserving its id, comment and actual sleep',
    () async {
      final sleepRepository = SleepRepository();
      await sleepRepository.add(
        date: DateTime(2026, 7, 27),
        sleepMinutes: 480,
        actualSleepMinutes: 420,
        comment: 'Manual note',
      );
      final manual = await sleepRepository.getByDate(DateTime(2026, 7, 27));
      final spool = _spool(
        DateTime.utc(2026, 7, 27, 22),
        status: SleepMonitorSession.completed,
        durationMinutes: 60,
      );
      await repository.importNativeSpool(spool);

      final merged = await sleepRepository.getByDate(DateTime(2026, 7, 27));
      expect(merged!.id, manual!.id);
      expect(merged.source, 'hybrid');
      expect(merged.sleepMinutes, 480);
      expect(merged.actualSleepMinutes, 420);
      expect(merged.comment, 'Manual note');
      expect(merged.timeInBedMinutes, 60);
    },
  );

  test('manual edit after monitoring preserves the linked session', () async {
    final sleepRepository = SleepRepository();
    final imported = await repository.importNativeSpool(
      _spool(
        DateTime.utc(2026, 7, 30, 22),
        status: SleepMonitorSession.completed,
      ),
    );
    final monitoredEntry = await sleepRepository.getByDate(
      DateTime(2026, 7, 30),
    );

    await sleepRepository.add(
      date: DateTime(2026, 7, 30),
      sleepMinutes: 450,
      actualSleepMinutes: 420,
      comment: 'Ajuste manual',
    );

    final merged = await sleepRepository.getByDate(DateTime(2026, 7, 30));
    final durableSession = await repository.getSession(imported.id);
    expect(merged!.id, monitoredEntry!.id);
    expect(merged.source, 'hybrid');
    expect(merged.timeInBedMinutes, 2);
    expect(durableSession, isNotNull);
    expect(durableSession!.sleepEntryId, merged.id);
  });

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
