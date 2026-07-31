import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_inference.dart';
import 'package:workout_notes/models/sleep_monitor_diagnostics.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/workout/sleep_monitor_screen.dart';

Widget _localized(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: child,
);

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test(
    'diagnostics accepts a four-hour session with complete valid coverage',
    () {
      final start = DateTime.utc(2026, 7, 26, 22);
      final segments = List.generate(
        4,
        (index) => SleepMonitorSegment(
          id: '$index',
          sessionId: 'session',
          startedAt: start.add(Duration(hours: index)),
          durationSeconds: 3600,
          audioRmsDbfs: -40,
          audioPeakDbfs: -20,
          noiseScore: index.isEven ? 2 : 12,
          classification: index.isEven ? 'quiet' : 'noise',
          validFraction: 1,
          noiseBurstCount: index.isEven ? 0 : 1,
        ),
      );
      final session = SleepMonitorSession(
        id: 'session',
        sleepEntryId: 'entry',
        status: SleepMonitorSession.completed,
        startedAt: start,
        endedAt: start.add(const Duration(hours: 4)),
        utcOffsetStartMinutes: -180,
        utcOffsetEndMinutes: -180,
        sensorMode: 'audio',
        algorithmVersion: 'test',
        timeInBedMinutes: 240,
        quietMinutes: 120,
        noisyMinutes: 120,
        estimatedSleepMinutes: null,
        noiseEventCount: 2,
        signalQualityScore: 1,
        endReason: SleepMonitorSession.endUser,
        createdAt: start,
      );

      final diagnostics = SleepMonitorDiagnostics.fromSession(
        session,
        segments,
      );
      expect(diagnostics.timelineCoverage, 1);
      expect(diagnostics.signalCoverage, 1);
      expect(diagnostics.averageNoiseScore, 7);
      expect(diagnostics.isAcceptableForNextPhase, isTrue);
    },
  );

  test('diagnostics rejects a completed night without segments', () {
    final start = DateTime.utc(2026, 7, 26, 22);
    final session = SleepMonitorSession(
      id: 'empty',
      sleepEntryId: null,
      status: SleepMonitorSession.completed,
      startedAt: start,
      endedAt: start.add(const Duration(hours: 8)),
      utcOffsetStartMinutes: -180,
      utcOffsetEndMinutes: -180,
      sensorMode: 'audio',
      algorithmVersion: 'test',
      timeInBedMinutes: 480,
      quietMinutes: 0,
      noisyMinutes: 0,
      estimatedSleepMinutes: null,
      noiseEventCount: 0,
      signalQualityScore: 0,
      endReason: SleepMonitorSession.endUser,
      createdAt: start,
    );

    final diagnostics = SleepMonitorDiagnostics.fromSession(session, const []);
    expect(diagnostics.hasData, isFalse);
    expect(diagnostics.isAcceptableForNextPhase, isFalse);
  });

  test('active elapsed time keeps advancing after the last native event', () {
    final now = DateTime.now();
    final state = SleepMonitorState(
      supported: true,
      microphoneGranted: true,
      status: SleepMonitorState.running,
      sessionId: 'session',
      startedAt: now.subtract(const Duration(minutes: 10)),
      updatedAt: now.subtract(const Duration(minutes: 5)),
      latestSegment: null,
      currentNoiseScore: null,
      errorCode: null,
      errorMessage: null,
    );

    expect(state.elapsed, greaterThanOrEqualTo(const Duration(minutes: 9)));
  });

  testWidgets('monitor screen explains Android-only support off Android', (
    tester,
  ) async {
    await tester.pumpWidget(_localized(const SleepMonitorScreen()));
    await tester.pump();

    if (defaultTargetPlatform != TargetPlatform.android) {
      expect(
        find.text('Monitoring is available only on Android.'),
        findsOneWidget,
      );
      expect(find.text('Monitor sleep'), findsOneWidget);
      expect(find.text('Start monitoring'), findsNothing);
    }
  });

  testWidgets('result timeline renders quiet, noise and invalid segments', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 26, 22);
    final session = _session(start, const Duration(seconds: 90));
    await tester.pumpWidget(
      _localized(
        Scaffold(
          body: SleepMonitorTimeline(
            session: session,
            inference: _emptyInference(),
            segments: [
              SleepMonitorSegment(
                id: '1',
                sessionId: 's',
                startedAt: start,
                durationSeconds: 30,
                audioRmsDbfs: -50,
                audioPeakDbfs: -30,
                noiseScore: 1,
                classification: 'quiet',
                validFraction: 1,
                noiseBurstCount: 0,
              ),
              SleepMonitorSegment(
                id: '2',
                sessionId: 's',
                startedAt: start.add(const Duration(seconds: 30)),
                durationSeconds: 30,
                audioRmsDbfs: -20,
                audioPeakDbfs: -8,
                noiseScore: 15,
                classification: 'noise',
                validFraction: 1,
                noiseBurstCount: 1,
              ),
              SleepMonitorSegment(
                id: '3',
                sessionId: 's',
                startedAt: start.add(const Duration(seconds: 60)),
                durationSeconds: 30,
                audioRmsDbfs: null,
                audioPeakDbfs: null,
                noiseScore: null,
                classification: 'invalid',
                validFraction: 0,
                noiseBurstCount: 0,
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      find.bySemanticsLabel('Sleep monitoring timeline with 3 segments'),
      findsOneWidget,
    );
  });

  testWidgets('noise chart renders captured scores', (tester) async {
    final start = DateTime.utc(2026, 7, 26, 22);
    final segments = List.generate(
      4,
      (index) => SleepMonitorSegment(
        id: '$index',
        sessionId: 's',
        startedAt: start.add(Duration(minutes: index * 30)),
        durationSeconds: 30,
        audioRmsDbfs: -40,
        audioPeakDbfs: -20,
        noiseScore: index * 4,
        classification: index < 3 ? 'quiet' : 'noise',
        validFraction: 1,
        noiseBurstCount: 0,
      ),
    );
    final session = _session(start, const Duration(hours: 2));

    await tester.pumpWidget(
      _localized(
        Scaffold(
          body: SleepNoiseChart(
            segments: segments,
            session: session,
            inference: _emptyInference(),
            emptyTitle: 'No data',
            noiseScoreLabel: 'Noise score',
            thresholdLabel: 'Threshold',
          ),
        ),
      ),
    );

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('Threshold: 10'), findsOneWidget);
  });

  testWidgets('result screen shows inferred onset with low confidence', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 29, 5);
    final session = _session(start, const Duration(hours: 4));
    final segments = List.generate(480, (index) {
      final score = index < 10 ? 16.0 : 2.0;
      return SleepMonitorSegment(
        id: '$index',
        sessionId: session.id,
        startedAt: start.add(Duration(seconds: index * 30)),
        durationSeconds: 30,
        audioRmsDbfs: -82 + score,
        audioPeakDbfs: -62 + score,
        noiseScore: score,
        classification: score >= 10 ? 'noise' : 'quiet',
        validFraction: 1,
        noiseBurstCount: score >= 10 ? 10 : 0,
      );
    });
    final database = (await tester.runAsync(
      () => _resultDatabase(session, segments),
    ))!;
    DatabaseHelper.overrideDatabase = database;
    addTearDown(() async {
      DatabaseHelper.overrideDatabase = null;
      await database.close();
    });

    await tester.pumpWidget(
      _localized(SleepMonitorResultScreen(sessionId: session.id)),
    );
    await _pumpUntilLoaded(tester);

    expect(find.text('Night analysis'), findsOneWidget);
    expect(find.text('Fell asleep'), findsWidgets);
    expect(find.textContaining('low'), findsOneWidget);
    expect(find.text('Estimated sleep'), findsOneWidget);
  });

  testWidgets('result screen explains insufficient digital-silence data', (
    tester,
  ) async {
    final start = DateTime.utc(2026, 7, 29, 5);
    final session = _session(start, const Duration(hours: 4));
    final segments = List.generate(
      4,
      (index) => SleepMonitorSegment(
        id: '$index',
        sessionId: session.id,
        startedAt: start.add(Duration(hours: index)),
        durationSeconds: 3600,
        audioRmsDbfs: -120,
        audioPeakDbfs: -120,
        noiseScore: 0,
        classification: 'quiet',
        validFraction: 1,
        noiseBurstCount: 0,
      ),
    );
    final database = (await tester.runAsync(
      () => _resultDatabase(session, segments),
    ))!;
    DatabaseHelper.overrideDatabase = database;
    addTearDown(() async {
      DatabaseHelper.overrideDatabase = null;
      await database.close();
    });

    await tester.pumpWidget(
      _localized(SleepMonitorResultScreen(sessionId: session.id)),
    );
    await _pumpUntilLoaded(tester);

    expect(
      find.text(
        'More than 20% of the period contains digital microphone silence.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        "This night's data is not sufficient to calculate sleep onset and awakenings safely.",
      ),
      findsOneWidget,
    );
  });
}

Future<void> _pumpUntilLoaded(WidgetTester tester) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
    if (find.byType(CircularProgressIndicator).evaluate().isEmpty) return;
  }
  fail('Sleep result screen did not finish loading');
}

Future<Database> _resultDatabase(
  SleepMonitorSession session,
  List<SleepMonitorSegment> segments,
) async {
  final database = await databaseFactory.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE sleep_monitor_sessions (
            id TEXT PRIMARY KEY,
            sleep_entry_id TEXT,
            status TEXT NOT NULL,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            alarm_at TEXT,
            utc_offset_start_minutes INTEGER NOT NULL,
            utc_offset_end_minutes INTEGER,
            sensor_mode TEXT NOT NULL,
            algorithm_version TEXT NOT NULL,
            time_in_bed_minutes INTEGER,
            quiet_minutes INTEGER,
            noisy_minutes INTEGER,
            estimated_sleep_minutes INTEGER,
            noise_event_count INTEGER NOT NULL,
            signal_quality_score REAL,
            end_reason TEXT,
            created_at TEXT NOT NULL
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
            noise_burst_count INTEGER NOT NULL
          )
        ''');
      },
    ),
  );
  await database.insert('sleep_monitor_sessions', session.toMap());
  final batch = database.batch();
  for (final segment in segments) {
    batch.insert('sleep_monitor_segments', segment.toMap());
  }
  await batch.commit(noResult: true);
  return database;
}

SleepMonitorSession _session(DateTime start, Duration duration) {
  return SleepMonitorSession(
    id: 's',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: start,
    endedAt: start.add(duration),
    utcOffsetStartMinutes: -180,
    utcOffsetEndMinutes: -180,
    sensorMode: 'audio',
    algorithmVersion: 'test',
    timeInBedMinutes: duration.inMinutes,
    quietMinutes: null,
    noisyMinutes: null,
    estimatedSleepMinutes: null,
    noiseEventCount: 0,
    signalQualityScore: 1,
    endReason: SleepMonitorSession.endUser,
    createdAt: start,
  );
}

SleepInferenceResult _emptyInference() {
  return const SleepInferenceResult(
    status: SleepInferenceStatus.available,
    confidence: SleepInferenceConfidence.low,
    sleepOnsetAt: null,
    settlingStartedAt: null,
    settlingEndedAt: null,
    estimatedSleepSeconds: null,
    events: [],
    blockers: [],
    parameters: {},
  );
}
