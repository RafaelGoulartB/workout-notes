import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/sleep_entry.dart';
import '../models/sleep_monitor_diagnostics.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';

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
    required SleepEntry? entry,
    required bool includePersonalData,
    Map<String, dynamic>? deviceInfo,
  }) async {
    final generatedAt = DateTime.now().toUtc();
    final payload = buildPayload(
      session: session,
      segments: segments,
      diagnostics: diagnostics,
      entry: entry,
      includePersonalData: includePersonalData,
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
    required SleepEntry? entry,
    required bool includePersonalData,
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
      };
    }).toList();

    return {
      'schema': 'workout_notes_sleep_diagnostic',
      'schema_version': 1,
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
      },
      'diagnostics': {
        'session_duration_seconds': diagnostics.sessionDurationSeconds,
        'captured_duration_seconds': diagnostics.capturedDurationSeconds,
        'segment_count': diagnostics.segmentCount,
        'quiet_seconds': diagnostics.quietSeconds,
        'noisy_seconds': diagnostics.noisySeconds,
        'invalid_seconds': diagnostics.invalidSeconds,
        'timeline_coverage': diagnostics.timelineCoverage,
        'signal_coverage': diagnostics.signalCoverage,
        'average_noise_score': diagnostics.averageNoiseScore,
        'peak_noise_score': diagnostics.peakNoiseScore,
      },
      'segments_relative': relativeSegments,
      if (includePersonalData) ...{
        'session_with_exact_timestamps': session.toMap(),
        'segments_with_exact_timestamps': segments
            .map((segment) => segment.toMap())
            .toList(),
        'associated_sleep_entry': entry?.toMap(),
      },
      'not_collected': {
        'raw_audio': true,
        'movement_or_accelerometer': true,
        'heart_rate': true,
        'battery_start_and_end': true,
      },
    };
  }

  static Future<void> _shareWithSheet(XFile file, String text) async {
    await Share.shareXFiles([file], text: text);
  }
}
