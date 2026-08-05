import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sleep_entry.dart';
import '../models/sleep_inference.dart';
import '../models/sleep_monitor_diagnostics.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';
import '../models/sleep_stage_epoch.dart';
import '../services/sleep_stage_engine.dart';

typedef DiagnosticDirectoryProvider = Future<Directory> Function();
typedef DiagnosticShareCallback =
    Future<void> Function(XFile file, String text);

/// Builds and shares a self-contained sleep-monitoring diagnostic.
///
/// Technical exports use relative segment times. Exact dates, local IDs and
/// the user's sleep note are included only after an explicit opt-in.
class SleepDiagnosticExportService {
  final DiagnosticDirectoryProvider _directoryProvider;
  final DiagnosticShareCallback _shareFile;

  SleepDiagnosticExportService({
    DiagnosticDirectoryProvider? directoryProvider,
    DiagnosticShareCallback? shareFile,
  }) : _directoryProvider = directoryProvider ?? getTemporaryDirectory,
       _shareFile = shareFile ?? _shareWithSheet;

  Future<String> exportAndShare({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
    required SleepMonitorDiagnostics diagnostics,
    required SleepInferenceResult inference,
    required SleepEntry? entry,
    required bool includePersonalData,
    List<SleepStageEpoch> stages = const [],
    Map<String, dynamic>? deviceInfo,
  }) async {
    final generatedAt = DateTime.now().toUtc();
    final payload = buildPayload(
      session: session,
      segments: segments,
      diagnostics: diagnostics,
      inference: inference,
      entry: entry,
      includePersonalData: includePersonalData,
      stages: stages,
      deviceInfo: deviceInfo,
      generatedAt: generatedAt,
    );
    final directory = await _directoryProvider();
    if (!await directory.exists()) await directory.create(recursive: true);
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(generatedAt);
    final file = File('${directory.path}/sleep_diagnostic_$timestamp.json');
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(payload),
      flush: true,
    );
    await _shareFile(
      XFile(file.path, mimeType: 'application/json'),
      'Workout Notes - Sleep monitoring diagnostic',
    );
    return file.path;
  }

  static Map<String, dynamic> buildPayload({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
    required SleepMonitorDiagnostics diagnostics,
    required SleepInferenceResult inference,
    required SleepEntry? entry,
    required bool includePersonalData,
    List<SleepStageEpoch> stages = const [],
    required DateTime generatedAt,
    Map<String, dynamic>? deviceInfo,
  }) {
    final relativeSegments = segments.indexed.map((indexed) {
      final (index, segment) = indexed;
      return {
        'index': index,
        'offset_seconds': segment.startedAt
            .difference(session.startedAt)
            .inSeconds,
        'duration_seconds': segment.durationSeconds,
        'audio_rms_dbfs': segment.audioRmsDbfs,
        'audio_peak_dbfs': segment.audioPeakDbfs,
        'noise_score': segment.noiseScore,
        'classification': segment.classification,
        'valid_fraction': segment.validFraction,
        'noise_burst_count': segment.noiseBurstCount,
        'spectral_band_energy_0': segment.spectralBandEnergy0,
        'spectral_band_energy_1': segment.spectralBandEnergy1,
        'spectral_band_energy_2': segment.spectralBandEnergy2,
        'spectral_band_energy_3': segment.spectralBandEnergy3,
        'spectral_band_energy_4': segment.spectralBandEnergy4,
        'spectral_flatness': segment.spectralFlatness,
        'spectral_centroid_hz': segment.spectralCentroidHz,
        'breathing_regularity': segment.breathingRegularity,
        'breathing_rate_hz': segment.breathingRateHz,
        'motion_active_seconds': segment.motionActiveSeconds,
        'motion_mean_deviation_g': segment.motionMeanDeviationG,
        'motion_max_deviation_g': segment.motionMaxDeviationG,
      };
    }).toList();
    final relativeStages = stages.indexed.map((indexed) {
      final (index, stage) = indexed;
      return {
        'index': index,
        'offset_seconds': stage.startedAt
            .difference(session.startedAt)
            .inSeconds,
        'duration_seconds': stage.durationSeconds,
        'stage': stage.stage.name,
        'confidence': stage.confidence,
        'awake_probability': stage.awakeProbability,
        'sleeping_probability': stage.sleepingProbability,
        'deep_probability': stage.deepProbability,
        'algorithm_version': stage.algorithmVersion,
        'source': stage.source,
      };
    }).toList();
    final relativeInference = {
      'algorithm_version': SleepInferenceResult.algorithmVersion,
      'status': inference.status.name,
      'confidence': inference.confidence.name,
      'blockers': inference.blockers,
      'parameters': inference.parameters,
      'sleep_onset_offset_seconds': inference.sleepOnsetAt
          ?.difference(session.startedAt)
          .inSeconds,
      'settling_start_offset_seconds': inference.settlingStartedAt
          ?.difference(session.startedAt)
          .inSeconds,
      'settling_duration_seconds': inference.settlingSeconds,
      'estimated_sleep_seconds': inference.estimatedSleepSeconds,
      'events': inference.events
          .map(
            (event) => {
              'type': event.type.name,
              'start_offset_seconds': event.startedAt
                  .difference(session.startedAt)
                  .inSeconds,
              'duration_seconds': event.durationSeconds,
              'active_seconds': event.activeSeconds,
              'peak_noise_score': event.peakNoiseScore,
              'confidence': event.confidence.name,
              'reason': event.reason,
            },
          )
          .toList(),
    };

    return {
      'schema': 'workout_notes_sleep_diagnostic',
      'schema_version': 5,
      'generated_at_utc': generatedAt.toUtc().toIso8601String(),
      'privacy': {
        'personal_data_included': includePersonalData,
        'contains_raw_audio': false,
        'raw_audio_reason':
            'The app processes PCM in memory and never stores audio samples.',
      },
      'runtime': {
        'app_name': 'Workout Notes',
        'app_version': '1.0.0+1',
        'dart_version': Platform.version,
        'operating_system': Platform.operatingSystem,
        'operating_system_version': Platform.operatingSystemVersion,
        'locale': Platform.localeName,
        'number_of_processors': Platform.numberOfProcessors,
        'android_device': ?deviceInfo,
      },
      'acceptance_criteria': {
        'minimum_duration_hours': 4,
        'minimum_timeline_coverage': 0.90,
        'minimum_signal_coverage': 0.80,
        'maximum_invalid_fraction': 0.20,
        'maximum_digital_silence_fraction': 0.20,
        'acceptable_for_next_phase': diagnostics.isAcceptableForNextPhase,
        'scope':
            'Technical capture quality only; not sleep or medical accuracy.',
      },
      'session_technical': {
        'status': session.status,
        'end_reason': session.endReason,
        'sensor_mode': session.sensorMode,
        'algorithm_version': session.algorithmVersion,
        'utc_offset_start_minutes': session.utcOffsetStartMinutes,
        'utc_offset_end_minutes': session.utcOffsetEndMinutes,
        'time_in_bed_minutes': session.timeInBedMinutes,
        'quiet_minutes': session.quietMinutes,
        'noisy_minutes': session.noisyMinutes,
        'estimated_sleep_minutes': session.estimatedSleepMinutes,
        'noise_event_count': session.noiseEventCount,
        'signal_quality_score': session.signalQualityScore,
        'analysis_status': session.analysisStatus,
        'sleep_onset_offset_seconds': session.sleepOnsetAt
            ?.difference(session.startedAt)
            .inSeconds,
        'final_wake_offset_seconds': session.finalWakeAt
            ?.difference(session.startedAt)
            .inSeconds,
        'sleep_latency_minutes': session.sleepLatencyMinutes,
        'awake_minutes': session.awakeMinutes,
        'sleeping_minutes': session.sleepingMinutes,
        'deep_sleep_minutes': session.deepSleepMinutes,
        'unknown_minutes': session.unknownMinutes,
        'awakening_count': session.awakeningCount,
        'sleep_efficiency': session.sleepEfficiency,
        'stage_confidence': session.stageConfidence,
        'stage_algorithm_version': session.stageAlgorithmVersion,
      },
      'diagnostics': {
        'session_duration_seconds': diagnostics.sessionDurationSeconds,
        'captured_duration_seconds': diagnostics.capturedDurationSeconds,
        'segment_count': diagnostics.segmentCount,
        'quiet_seconds': diagnostics.quietSeconds,
        'noisy_seconds': diagnostics.noisySeconds,
        'invalid_seconds': diagnostics.invalidSeconds,
        'digital_silence_seconds': diagnostics.digitalSilenceSeconds,
        'timeline_coverage': diagnostics.timelineCoverage,
        'signal_coverage': diagnostics.signalCoverage,
        'digital_silence_fraction': diagnostics.digitalSilenceFraction,
        'average_noise_score': diagnostics.averageNoiseScore,
        'peak_noise_score': diagnostics.peakNoiseScore,
        'inference_blockers': diagnostics.inferenceBlockers,
      },
      'sleep_inference': relativeInference,
      'sleep_stage_engine': {
        'algorithm_version': SleepStageEngine.algorithmVersion,
        'parameters': SleepStageEngine.parameters,
      },
      'sleep_window': {
        'window_discovered':
            session.analysisStatus == SleepMonitorSession.analysisAvailable &&
            session.sleepOnsetAt != null,
        'onset_offset_seconds': session.sleepOnsetAt
            ?.difference(session.startedAt)
            .inSeconds,
        'final_wake_offset_seconds': session.finalWakeAt
            ?.difference(session.startedAt)
            .inSeconds,
        'awake_minutes': session.awakeMinutes,
        'sleep_minutes':
            session.sleepingMinutes != null && session.deepSleepMinutes != null
                ? session.sleepingMinutes! + session.deepSleepMinutes!
                : null,
        'deep_minutes': session.deepSleepMinutes,
      },
      'sleep_stages_relative': relativeStages,
      'segments_relative': relativeSegments,
      if (includePersonalData) ...{
        'session_with_exact_timestamps': session.toMap(),
        'segments_with_exact_timestamps': segments
            .map((segment) => segment.toMap())
            .toList(),
        'sleep_stages_with_exact_timestamps': stages
            .map((stage) => stage.toMap())
            .toList(),
        'associated_sleep_entry': entry?.toMap(),
        'sleep_inference_with_exact_timestamps': {
          'sleep_onset_at': inference.sleepOnsetAt?.toIso8601String(),
          'settling_started_at': inference.settlingStartedAt?.toIso8601String(),
          'settling_ended_at': inference.settlingEndedAt?.toIso8601String(),
          'events': inference.events
              .map(
                (event) => {
                  'type': event.type.name,
                  'started_at': event.startedAt.toIso8601String(),
                  'ended_at': event.endedAt.toIso8601String(),
                },
              )
              .toList(),
        },
      },
      'not_collected': {
        'raw_audio': true,
        'persisted_spectrograms': true,
        'movement_or_accelerometer': false,
        'raw_accelerometer_timeseries': true,
        'heart_rate': true,
        'battery_start_and_end': true,
      },
    };
  }

  static Future<void> _shareWithSheet(XFile file, String text) async {
    await Share.shareXFiles([file], text: text);
  }
}
