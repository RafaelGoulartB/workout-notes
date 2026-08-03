import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_inference.dart';
import 'package:workout_notes/models/sleep_monitor_diagnostics.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/sleep_diagnostic_export_service.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

void main() {
  late SleepMonitorSession session;
  late List<SleepMonitorSegment> segments;
  late SleepMonitorDiagnostics diagnostics;
  late SleepInferenceResult inference;
  late SleepEntry entry;

  setUp(() {
    final start = DateTime.utc(2026, 7, 26, 22);
    segments = [
      SleepMonitorSegment(
        id: 'segment-sensitive-id',
        sessionId: 'session-sensitive-id',
        startedAt: start.add(const Duration(seconds: 30)),
        durationSeconds: 30,
        audioRmsDbfs: -42,
        audioPeakDbfs: -18,
        noiseScore: 3,
        classification: 'quiet',
        validFraction: 1,
        noiseBurstCount: 0,
        spectralBandEnergy0: 20,
        spectralBandEnergy1: 30,
        spectralBandEnergy2: 40,
        spectralBandEnergy3: 5,
        spectralBandEnergy4: 2,
        spectralFlatness: 0.3,
        spectralCentroidHz: 1200,
        breathingRegularity: 0.4,
        breathingRateHz: 0.25,
        motionActiveSeconds: 0.5,
        motionMeanDeviationG: 0.02,
        motionMaxDeviationG: 0.05,
      ),
    ];
    session = SleepMonitorSession(
      id: 'session-sensitive-id',
      sleepEntryId: 'entry-sensitive-id',
      status: SleepMonitorSession.completed,
      startedAt: start,
      endedAt: start.add(const Duration(hours: 4)),
      utcOffsetStartMinutes: -180,
      utcOffsetEndMinutes: -180,
      sensorMode: 'audio',
      algorithmVersion: 'audio-noise-test',
      timeInBedMinutes: 240,
      quietMinutes: 200,
      noisyMinutes: 40,
      estimatedSleepMinutes: null,
      noiseEventCount: 1,
      signalQualityScore: 1,
      endReason: SleepMonitorSession.endUser,
      createdAt: start,
    );
    diagnostics = SleepMonitorDiagnostics.fromSession(session, segments);
    inference = SleepInferenceResult(
      status: SleepInferenceStatus.available,
      confidence: SleepInferenceConfidence.medium,
      sleepOnsetAt: start.add(const Duration(minutes: 30)),
      settlingStartedAt: start.add(const Duration(minutes: 5)),
      settlingEndedAt: start.add(const Duration(minutes: 30)),
      estimatedSleepSeconds: 3 * 60 * 60,
      events: [
        SleepInferenceEvent(
          type: SleepInferenceEventType.awakening,
          startedAt: start.add(const Duration(hours: 2)),
          endedAt: start.add(const Duration(hours: 2, minutes: 5)),
          activeSeconds: 180,
          peakNoiseScore: 22,
          confidence: SleepInferenceConfidence.medium,
          reason: 'sustained_activity_with_quiet_recovery',
        ),
      ],
      blockers: const [],
      parameters: const {'activity_start_score': 10},
    );
    entry = SleepEntry(
      id: 'entry-sensitive-id',
      date: DateTime(2026, 7, 26),
      sleepMinutes: 230,
      bedtimeMinutes: 22 * 60,
      wakeTimeMinutes: 2 * 60,
      comment: 'Personal sleep note',
      source: 'monitored',
      timeInBedMinutes: 240,
      createdAt: start,
    );
  });

  test(
    'technical payload excludes exact timestamps, IDs and personal note',
    () {
      final payload = SleepDiagnosticExportService.buildPayload(
        session: session,
        segments: segments,
        diagnostics: diagnostics,
        inference: inference,
        entry: entry,
        includePersonalData: false,
        generatedAt: DateTime.utc(2026, 7, 27),
        deviceInfo: {'device_model': 'Test Phone'},
      );

      expect(payload['privacy']['personal_data_included'], isFalse);
      expect(payload, isNot(contains('session_with_exact_timestamps')));
      expect(payload, isNot(contains('associated_sleep_entry')));
      final relative = payload['segments_relative'].single as Map;
      expect(relative['offset_seconds'], 30);
      expect(relative['spectral_flatness'], 0.3);
      expect(relative['breathing_regularity'], 0.4);
      expect(relative['motion_active_seconds'], 0.5);
      expect(payload['schema_version'], 4);
      expect(payload['sleep_inference']['sleep_onset_offset_seconds'], 30 * 60);
      expect(
        payload['sleep_stage_engine']['algorithm_version'],
        SleepStageEngine.algorithmVersion,
      );
      expect(payload['not_collected']['movement_or_accelerometer'], isFalse);
      expect(payload['not_collected']['raw_accelerometer_timeseries'], isTrue);
      expect(payload, isNot(contains('sleep_inference_with_exact_timestamps')));
      final encoded = jsonEncode(payload);
      expect(encoded, isNot(contains('Personal sleep note')));
      expect(encoded, isNot(contains('segment-sensitive-id')));
      expect(encoded, isNot(contains('2026-07-26T22:30:00.000Z')));
      expect(encoded, contains('Test Phone'));
    },
  );

  test(
    'personal payload includes every persisted monitoring field and note',
    () {
      final payload = SleepDiagnosticExportService.buildPayload(
        session: session,
        segments: segments,
        diagnostics: diagnostics,
        inference: inference,
        entry: entry,
        includePersonalData: true,
        generatedAt: DateTime.utc(2026, 7, 27),
      );

      expect(payload['privacy']['personal_data_included'], isTrue);
      expect(
        payload['session_with_exact_timestamps']['id'],
        'session-sensitive-id',
      );
      expect(
        payload['segments_with_exact_timestamps'].single['id'],
        'segment-sensitive-id',
      );
      expect(
        payload['associated_sleep_entry']['comment'],
        'Personal sleep note',
      );
      expect(payload['privacy']['contains_raw_audio'], isFalse);
      expect(
        payload['sleep_inference_with_exact_timestamps']['sleep_onset_at'],
        session.startedAt.add(const Duration(minutes: 30)).toIso8601String(),
      );
    },
  );

  test('writes valid JSON and invokes the share callback', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sleep-diagnostic-test-',
    );
    String? sharedPath;
    try {
      final service = SleepDiagnosticExportService(
        directoryProvider: () async => directory,
        shareFile: (file, text) async {
          sharedPath = file.path;
          expect(text, contains('Sleep monitoring diagnostic'));
        },
      );
      final path = await service.exportAndShare(
        session: session,
        segments: segments,
        diagnostics: diagnostics,
        inference: inference,
        entry: entry,
        includePersonalData: false,
      );

      expect(sharedPath, path);
      final decoded = jsonDecode(await File(path).readAsString());
      expect(decoded['schema'], 'workout_notes_sleep_diagnostic');
      expect(decoded['segments_relative'], hasLength(1));
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
