import 'dart:convert';
import 'dart:io';

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_summary.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_analysis_service.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';

/// Compares the app's estimated sleep stages against a manual sleep diary.
///
/// Usage:
///   dart run tool/validate_sleep_stages.dart `diagnostic.json` `diary.json`
///   dart run tool/validate_sleep_stages.dart --template
///
/// `diagnostic.json` is a sleep diagnostic exported by an older app version
/// (schema_version >= 4, previously produced by SleepDiagnosticExportService).
/// `diary.json` records what the sleeper actually experienced:
/// {
///   "session_start": "22:00",        // wall-clock HH:MM when recording began
///   "bedtime": "22:00",              // optional (defaults to session_start)
///   "sleep_onset": "23:05",
///   "final_wake": "06:40",
///   "awakenings": ["01:20", "03:10"],
///   "optional_epoch_labels": [       // optional; only reliable labels
///     {"offset_seconds": 7200, "stage": "deep", "duration_seconds": 1800}
///   ]
/// }
///
/// The primary comparison is sleep/wake agreement (what a manual diary can
/// validate). Deep-sleep agreement is reported only for windows the user
/// explicitly labeled.
///
/// Exit code 0 when the engine ran, 1 on usage/parse/legacy errors.
Future<void> main(List<String> args) async {
  if (args.length == 1 && args.first == '--template') {
    stdout.writeln(_template);
    return;
  }
  if (args.length == 2 && args.first == '--self') {
    await _selfCheck(args[1]);
    return;
  }
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/validate_sleep_stages.dart <diagnostic.json> <diary.json>',
    );
    stderr.writeln('       dart run tool/validate_sleep_stages.dart --template');
    exit(1);
  }

  final diagnostic = _readJson(args[0]);
  final diary = _readJson(args[1]);

  final segments = segmentsFromDiagnostic(diagnostic);
  if (!segments.any((segment) => segment.hasSpectralFeatures)) {
    stderr.writeln(
      'The diagnostic predates spectral features (schema_version < 4) or its '
      'segments carry no spectral data. Re-export after updating the app.',
    );
    exit(1);
  }

  final start = sessionStart(diary);
  final session = sessionFromDiagnostic(diagnostic, start);
  final sessionEnd = session.endedAt ?? session.startedAt;

  final engineResult = const SleepStageEngine().run(
    session: session,
    segments: segments,
  );
  if (!engineResult.ran) {
    stderr.writeln('Engine could not stage this night: ${engineResult.blockers}');
    exit(1);
  }

  final summary = const SleepStageAnalysisService().summarize(
    sessionStart: session.startedAt,
    sessionEnd: sessionEnd,
    epochs: engineResult.epochs,
  );
  final truth = DiaryTruth(diary);
  final report = validateAgainstDiary(engineResult.epochs, truth, start);

  stdout.writeln('=== Sleep stage validation ===');
  stdout.writeln('Engine:            ${SleepStageEngine.algorithmVersion}');
  stdout.writeln('Scored epochs:     ${engineResult.validEpochs}');
  stdout.writeln(
    'Unknown epochs:    ${engineResult.unknownEpochs} '
    '(coverage ${(engineResult.coverage * 100).toStringAsFixed(0)}%)',
  );
  stdout.writeln();
  stdout.writeln(report.sleepWakeBlock);
  if (truth.hasOptionalLabels) {
    stdout.writeln();
    stdout.writeln(report.threeStateBlock);
  }
  stdout.writeln();
  stdout.writeln(nightErrorsBlock(engineResult.epochs, session, summary, truth));
}

/// Re-stages a diagnostic without any manual diary, comparing the current
/// engine against the values the recording itself shipped (schema v5).
Future<void> _selfCheck(String path) async {
  final diagnostic = _readJson(path);
  final segments = segmentsFromDiagnostic(diagnostic);
  if (!segments.any((segment) => segment.hasSpectralFeatures)) {
    stderr.writeln(
      'The diagnostic predates spectral features (schema_version < 4).',
    );
    exit(1);
  }
  final start = sessionStart(diagnostic);
  final session = sessionFromDiagnostic(diagnostic, start);
  final sessionEnd = session.endedAt ?? session.startedAt;
  final technical = diagnostic['session_technical'] as Map<String, dynamic>?;
  final refOnset = (technical?['sleep_onset_offset_seconds'] as num?)?.toInt();
  final refWake = (technical?['final_wake_offset_seconds'] as num?)?.toInt();
  final refSleep = (technical?['sleeping_minutes'] as num?)?.toInt();
  final refDeep = (technical?['deep_sleep_minutes'] as num?)?.toInt();
  final refTotal = (technical?['estimated_sleep_minutes'] as num?)?.toInt();
  final refAwake = (technical?['awake_minutes'] as num?)?.toInt();

  final result = const SleepStageEngine().run(
    session: session,
    segments: segments,
  );
  if (!result.ran) {
    stderr.writeln('Engine could not stage this night: ${result.blockers}');
    exit(1);
  }
  final summary = const SleepStageAnalysisService().summarize(
    sessionStart: start,
    sessionEnd: sessionEnd,
    epochs: result.epochs,
  );

  stdout.writeln('=== Self-check (recorded vs current engine) ===');
  stdout.writeln('Engine:            ${SleepStageEngine.algorithmVersion}');
  stdout.writeln(
    'Window:            onset=${_offMin(result.window.onsetAt, start)} '
    'finalWake=${_offMin(result.window.finalWakeAt, start)} '
    'discovered=${result.window.discovered}',
  );
  stdout.writeln(
    'Sleep onset:       engine ${_minDelta(summary?.sleepOnsetAt, start)} '
    'vs recorded ${_minDeltaRef(refOnset)}',
  );
  stdout.writeln(
    'Final wake:        engine ${_minDelta(summary?.finalWakeAt, start)} '
    'vs recorded ${_minDeltaRef(refWake)}',
  );
  stdout.writeln(
    'Sleep minutes:     engine ${summary?.estimatedSleepMinutes} '
    'vs recorded $refTotal (sleeping $refSleep, deep $refDeep)',
  );
  stdout.writeln('Deep minutes:      engine ${summary?.deepSleepMinutes}');
  stdout.writeln('Awake minutes:     engine ${summary?.awakeMinutes} vs recorded $refAwake');
}

String _offMin(DateTime? value, DateTime start) {
  if (value == null) return '--';
  return '${value.difference(start).inMinutes}m';
}

String _minDelta(DateTime? value, DateTime start) {
  if (value == null) return '--';
  return '${value.difference(start).inMinutes} min';
}

String _minDeltaRef(int? offsetSeconds) {
  if (offsetSeconds == null) return '--';
  return '${offsetSeconds ~/ 60} min';
}

const String _template = '''
{
  "session_start": "22:00",
  "bedtime": "22:00",
  "sleep_onset": "23:05",
  "final_wake": "06:40",
  "awakenings": ["01:20", "03:10"],
  "optional_epoch_labels": [
    {"offset_seconds": 3600, "stage": "deep", "duration_seconds": 1800}
  ]
}
''';

Map<String, dynamic> _readJson(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('File not found: $path');
    exit(1);
  }
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

/// Builds the monitor segments recorded in a v4 diagnostic payload.
List<SleepMonitorSegment> segmentsFromDiagnostic(Map<String, dynamic> diagnostic) {
  final raw = diagnostic['segments_relative'] as List<dynamic>? ?? const [];
  final start = DateTime.utc(2026, 1, 1, 22);
  final segments = <SleepMonitorSegment>[];
  for (final (index, item) in raw.indexed) {
    final map = item as Map<String, dynamic>;
    final offset = (map['offset_seconds'] as num?)?.toInt() ?? index * 30;
    segments.add(
      SleepMonitorSegment(
        id: 'seg-$index',
        sessionId: 'harness-session',
        startedAt: start.add(Duration(seconds: offset)),
        durationSeconds: (map['duration_seconds'] as num?)?.toInt() ?? 30,
        audioRmsDbfs: (map['audio_rms_dbfs'] as num?)?.toDouble(),
        audioPeakDbfs: (map['audio_peak_dbfs'] as num?)?.toDouble(),
        noiseScore: (map['noise_score'] as num?)?.toDouble(),
        classification: map['classification'] as String? ?? 'quiet',
        validFraction: (map['valid_fraction'] as num?)?.toDouble() ?? 1.0,
        noiseBurstCount: (map['noise_burst_count'] as num?)?.toInt() ?? 0,
        spectralBandEnergy0: (map['spectral_band_energy_0'] as num?)?.toDouble(),
        spectralBandEnergy1: (map['spectral_band_energy_1'] as num?)?.toDouble(),
        spectralBandEnergy2: (map['spectral_band_energy_2'] as num?)?.toDouble(),
        spectralBandEnergy3: (map['spectral_band_energy_3'] as num?)?.toDouble(),
        spectralBandEnergy4: (map['spectral_band_energy_4'] as num?)?.toDouble(),
        spectralFlatness: (map['spectral_flatness'] as num?)?.toDouble(),
        spectralCentroidHz: (map['spectral_centroid_hz'] as num?)?.toDouble(),
        breathingRegularity: (map['breathing_regularity'] as num?)?.toDouble(),
        breathingRateHz: (map['breathing_rate_hz'] as num?)?.toDouble(),
        motionActiveSeconds: (map['motion_active_seconds'] as num?)?.toDouble(),
        motionMeanDeviationG: (map['motion_mean_deviation_g'] as num?)?.toDouble(),
        motionMaxDeviationG: (map['motion_max_deviation_g'] as num?)?.toDouble(),
      ),
    );
  }
  return segments;
}

DateTime sessionStart(Map<String, dynamic> diary) {
  final minutes = _parseClock(diary['session_start'] as String? ?? '22:00');
  return DateTime.utc(2026, 1, 1).add(Duration(minutes: minutes));
}

SleepMonitorSession sessionFromDiagnostic(
  Map<String, dynamic> diagnostic,
  DateTime start,
) {
  final technical = diagnostic['session_technical'] as Map<String, dynamic>?;
  final timeInBed =
      (technical?['time_in_bed_minutes'] as num?)?.toInt() ??
      const Duration(hours: 8).inMinutes;
  return SleepMonitorSession(
    id: 'harness-session',
    sleepEntryId: null,
    status: SleepMonitorSession.completed,
    startedAt: start,
    endedAt: start.add(Duration(minutes: timeInBed)),
    utcOffsetStartMinutes: 0,
    utcOffsetEndMinutes: 0,
    sensorMode: (technical?['sensor_mode'] as String?) ?? 'audio',
    algorithmVersion:
        (technical?['algorithm_version'] as String?) ?? 'audio-features-v2',
    timeInBedMinutes: timeInBed,
    quietMinutes: (technical?['quiet_minutes'] as num?)?.toInt(),
    noisyMinutes: (technical?['noisy_minutes'] as num?)?.toInt(),
    estimatedSleepMinutes: (technical?['estimated_sleep_minutes'] as num?)?.toInt(),
    noiseEventCount: (technical?['noise_event_count'] as num?)?.toInt() ?? 0,
    signalQualityScore: (technical?['signal_quality_score'] as num?)?.toDouble(),
    endReason: (technical?['end_reason'] as String?) ?? SleepMonitorSession.endUser,
    createdAt: start,
  );
}

int _parseClock(String value) {
  final parts = value.split(':');
  final hour = int.parse(parts[0]);
  final minute = parts.length > 1 ? int.parse(parts[1]) : 0;
  return hour * 60 + minute;
}

/// Ground truth derived from a manual diary, expressed as offsets (seconds)
/// from session start so it can be compared with engine epochs.
class DiaryTruth {
  final int onsetOffsetSeconds;
  final int finalWakeOffsetSeconds;
  final List<(int, int)> awakeningRanges;
  final List<(int, int, SleepStageType)> optionalLabels;
  final bool hasOptionalLabels;

  DiaryTruth(Map<String, dynamic> diary)
    : onsetOffsetSeconds = _deltaSeconds(
        _parseClock(diary['session_start'] as String? ?? '22:00'),
        _parseClock(diary['sleep_onset'] as String? ?? '23:05'),
      ),
      finalWakeOffsetSeconds = _deltaSeconds(
        _parseClock(diary['session_start'] as String? ?? '22:00'),
        _parseClock(diary['final_wake'] as String? ?? '06:40'),
      ),
      awakeningRanges = [
        for (final time in diary['awakenings'] as List<dynamic>? ?? const [])
          () {
            final startOffset = _deltaSeconds(
              _parseClock(diary['session_start'] as String? ?? '22:00'),
              _parseClock(time as String),
            );
            return (startOffset, startOffset + 60);
          }(),
      ],
      optionalLabels = [
        for (final item
            in diary['optional_epoch_labels'] as List<dynamic>? ?? const [])
          () {
            final map = item as Map<String, dynamic>;
            final offset = (map['offset_seconds'] as num).toInt();
            return (
              offset,
              offset + ((map['duration_seconds'] as num?)?.toInt() ?? 60),
              stageFromString(map['stage'] as String?),
            );
          }(),
      ],
      hasOptionalLabels =
          (diary['optional_epoch_labels'] as List<dynamic>? ?? const []).isNotEmpty;

  SleepStageType truthAt(int offsetSeconds) {
    for (final (from, to, stage) in optionalLabels) {
      if (offsetSeconds >= from && offsetSeconds < to) return stage;
    }
    for (final (from, to) in awakeningRanges) {
      if (offsetSeconds >= from && offsetSeconds < to) return SleepStageType.awake;
    }
    if (offsetSeconds < onsetOffsetSeconds) return SleepStageType.awake;
    if (offsetSeconds >= finalWakeOffsetSeconds) return SleepStageType.awake;
    return SleepStageType.sleeping;
  }

  int diaryAsleepSeconds() =>
      finalWakeOffsetSeconds -
      onsetOffsetSeconds -
      awakeningRanges.fold<int>(0, (sum, range) => sum + (range.$2 - range.$1));
}

SleepStageType stageFromString(String? value) => switch (value) {
  'awake' => SleepStageType.awake,
  'deep' => SleepStageType.deep,
  _ => SleepStageType.sleeping,
};

int _deltaSeconds(int startMinutes, int endMinutes) {
  var delta = endMinutes - startMinutes;
  if (delta < 0) delta += 24 * 60;
  return delta * 60;
}

class SleepStageValidationReport {
  final double accuracy;
  final double sensitivity;
  final double specificity;
  final double kappa;
  final String sleepWakeBlock;
  final String threeStateBlock;

  const SleepStageValidationReport({
    required this.accuracy,
    required this.sensitivity,
    required this.specificity,
    required this.kappa,
    required this.sleepWakeBlock,
    required this.threeStateBlock,
  });
}

/// Compares engine epochs with diary ground truth and reports sleep/wake
/// agreement plus a 3-state matrix over explicitly labeled windows.
SleepStageValidationReport validateAgainstDiary(
  List<SleepStageEpoch> epochs,
  DiaryTruth truth,
  DateTime sessionStart,
) {
  var tp = 0, tn = 0, fp = 0, fn = 0; // asleep = positive
  var included = 0;
  final matrix3 = <String, Map<String, int>>{};

  for (final epoch in epochs) {
    if (epoch.stage == SleepStageType.unknown) continue;
    final offset = epoch.startedAt.difference(sessionStart).inSeconds;
    if (offset >= truth.finalWakeOffsetSeconds) continue;
    final truthStage = truth.truthAt(offset);
    final engineAsleep =
        epoch.stage == SleepStageType.sleeping || epoch.stage == SleepStageType.deep;
    final truthAsleep =
        truthStage == SleepStageType.sleeping || truthStage == SleepStageType.deep;
    if (engineAsleep && truthAsleep) {
      tp++;
    } else if (!engineAsleep && !truthAsleep) {
      tn++;
    } else if (engineAsleep && !truthAsleep) {
      fp++;
    } else {
      fn++;
    }
    included++;

    if (truth.hasOptionalLabels) {
      final from = truth.optionalLabels.first.$1;
      final to = truth.optionalLabels.last.$2;
      if (offset >= from && offset < to) {
        final engineName = epoch.stage.name;
        final truthName = truthStage.name;
        matrix3.putIfAbsent(engineName, () => {});
        matrix3[engineName]![truthName] =
            (matrix3[engineName]![truthName] ?? 0) + 1;
      }
    }
  }

  final accuracy = (tp + tn) / included;
  final sensitivity = (tp + fn) == 0 ? 0.0 : tp / (tp + fn);
  final specificity = (tn + fp) == 0 ? 0.0 : tn / (tn + fp);
  final prevalence = (tp + fn) / included;
  final pe = (prevalence * (tp + fp) / included) +
      ((1 - prevalence) * (tn + fn) / included);
  final kappa = pe == 1 ? 0.0 : (accuracy - pe) / (1 - pe);

  final block = StringBuffer()
    ..writeln('Sleep/wake agreement (diary ground truth, N=$included):')
    ..writeln('  Accuracy:            ${_p(accuracy)}')
    ..writeln('  Sensitivity (asleep):${_p(sensitivity)}')
    ..writeln('  Specificity (awake): ${_p(specificity)}')
    ..writeln('  Cohen\'s kappa:      ${kappa.toStringAsFixed(2)}')
    ..writeln('  Confusion (rows=engine, cols=diary):')
    ..writeln('                awake  asleep')
    ..writeln('    awake       ${tn.toString().padLeft(4)} ${fp.toString().padLeft(4)}')
    ..writeln('    asleep      ${fn.toString().padLeft(4)} ${tp.toString().padLeft(4)}');

  String threeState = '';
  if (truth.hasOptionalLabels) {
    final buf = StringBuffer()
      ..writeln('3-state agreement over labeled windows:')
      ..writeln('  matrix (engine/truth): $matrix3');
    threeState = buf.toString();
  }

  return SleepStageValidationReport(
    accuracy: accuracy,
    sensitivity: sensitivity,
    specificity: specificity,
    kappa: kappa,
    sleepWakeBlock: block.toString(),
    threeStateBlock: threeState,
  );
}

String nightErrorsBlock(
  List<SleepStageEpoch> epochs,
  SleepMonitorSession session,
  SleepStageSummary? summary,
  DiaryTruth truth,
) {
  final buf = StringBuffer()..writeln('Night-level errors (diary reference):');
  if (summary == null) {
    buf.writeln('  (no summary available)');
    return buf.toString();
  }
  final onset = summary.sleepOnsetAt;
  final wake = summary.finalWakeAt;
  final onsetError = onset == null
      ? null
      : onset.difference(session.startedAt).inMinutes -
            (truth.onsetOffsetSeconds / 60).round();
  final wakeError = wake == null
      ? null
      : wake.difference(session.startedAt).inMinutes -
            (truth.finalWakeOffsetSeconds / 60).round();
  buf.writeln('  Sleep onset:      ${_minutesDelta(onsetError)}');
  buf.writeln('  Final wake:       ${_minutesDelta(wakeError)}');
  final sleepMinutes = summary.estimatedSleepMinutes;
  final diarySleepMinutes = truth.diaryAsleepSeconds() ~/ 60;
  buf.writeln(
    '  Sleep minutes:    ${_minutesDelta(sleepMinutes - diarySleepMinutes)} '
    '(engine $sleepMinutes vs diary $diarySleepMinutes)',
  );
  if (truth.hasOptionalLabels) {
    final deepTruthMinutes = truth.optionalLabels
        .where((label) => label.$3 == SleepStageType.deep)
        .fold<int>(0, (sum, label) => sum + (label.$2 - label.$1) ~/ 60);
    final deepEngine = summary.deepSleepMinutes;
    buf.writeln(
      '  Deep minutes:     ${_minutesDelta(deepEngine - deepTruthMinutes)} '
      '(engine $deepEngine vs labeled $deepTruthMinutes)',
    );
  }
  return buf.toString();
}

String _p(double value) => value.toStringAsFixed(3);

String _minutesDelta(int? minutes) {
  if (minutes == null) return '--';
  final sign = minutes >= 0 ? '+' : '-';
  return '$sign${minutes.abs()} min';
}
