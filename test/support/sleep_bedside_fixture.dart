import 'dart:convert';
import 'dart:io';

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';

final bedsideStart = DateTime.utc(2026, 9, 1, 22);

List<SleepMonitorSegment> quantizedBedsideSegments({
  String fileName = 'sleep_quantized_bedside.json',
}) => bedsideSegmentsFromTable(
  jsonDecode(File('test/fixtures/$fileName').readAsStringSync())
      as Map<String, dynamic>,
);

/// Segments of a `{columns, rows}` table whose first column is the offset in
/// seconds from [bedsideStart] (the format of the recorded fixtures).
List<SleepMonitorSegment> bedsideSegmentsFromTable(Map<String, dynamic> table) {
  final columns = (table['columns'] as List).cast<String>();
  return [
    for (final (index, row)
        in (table['rows'] as List).cast<List<Object?>>().indexed)
      SleepMonitorSegment.fromMap({
        for (var i = 1; i < columns.length; i++) columns[i]: row[i],
        'id': 'recorded-$index',
        'session_id': 'bedside',
        'started_at': bedsideStart
            .add(Duration(seconds: row[0] as int))
            .toIso8601String(),
      }),
  ];
}

/// A loud sound next to the phone for the whole window, at a constant level:
/// a person or a device, the aggregates cannot tell which.
SleepMonitorSegment sustainedBedsideActivity(int index) =>
    SleepMonitorSegment.fromMap({
      ...bedsideSegment(index, activity: true).toMap(),
      'noise_active_seconds': 30.0,
      'audio_level_stddev_db': 5.0,
    });

SleepMonitorSession bedsideSession({
  int minutes = 60,
  String reason = 'user',
}) => SleepMonitorSession(
  id: 'bedside',
  sleepEntryId: null,
  status: SleepMonitorSession.completed,
  startedAt: bedsideStart,
  endedAt: bedsideStart.add(Duration(minutes: minutes)),
  utcOffsetStartMinutes: 0,
  utcOffsetEndMinutes: 0,
  sensorMode: 'audio_bedside',
  algorithmVersion: 'audio-features-v3',
  timeInBedMinutes: minutes,
  quietMinutes: null,
  noisyMinutes: null,
  estimatedSleepMinutes: null,
  noiseEventCount: 0,
  signalQualityScore: null,
  endReason: reason,
  createdAt: bedsideStart,
);

/// A quiet window; with [activity], a loud sound of a person next to the
/// phone: every band 30 dB above the quiet level for ten seconds.
SleepMonitorSegment bedsideSegment(
  int index, {
  bool periodic = false,
  bool activity = false,
  bool invalid = false,
  double? motion,
  int seconds = 30,
}) => SleepMonitorSegment(
  id: 's$index',
  sessionId: 'bedside',
  startedAt: bedsideStart.add(Duration(seconds: index * 30)),
  durationSeconds: seconds,
  audioRmsDbfs: -35,
  audioPeakDbfs: -20,
  noiseScore: activity ? 15 : 1,
  classification: invalid
      ? 'invalid'
      : activity
      ? 'noise'
      : 'quiet',
  validFraction: invalid ? 0 : 1,
  noiseBurstCount: 0,
  spectralBandEnergy0: activity ? 10000 : 10,
  spectralBandEnergy1: activity ? 20000 : 20,
  spectralBandEnergy2: activity ? 5000 : 5,
  spectralBandEnergy3: activity ? 1000 : 1,
  spectralBandEnergy4: activity ? 1000 : 1,
  spectralFlatness: periodic ? 0.3 : 0.8,
  breathingRegularity: periodic ? 0.7 : 0,
  breathingRateHz: periodic ? 0.25 : 0,
  noiseActiveSeconds: activity ? 10 : 0,
  audioSampleRate: 16000,
  audioSampleCount: 16000 * seconds,
  audioCalibrated: true,
  digitalSilenceFraction: 0,
  motionActiveSeconds: motion,
);
