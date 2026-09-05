import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';

final bedsideStart = DateTime.utc(2026, 9, 1, 22);

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
  spectralBandEnergy0: 10,
  spectralBandEnergy1: 20,
  spectralBandEnergy2: 5,
  spectralBandEnergy3: activity ? 40 : 1,
  spectralBandEnergy4: 1,
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
