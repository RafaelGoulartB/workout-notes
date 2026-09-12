import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_stage_engine.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';

/// dart run tool/replay_sleep.dart diagnostic.json [labels.json]
/// Reference labels cover only independently known intervals. Unlabelled time
/// stays unlabelled; a remembered bedtime never implies epoch-level sleep.
void main(List<String> args) {
  if (args.length == 1 && args.first == '--template') {
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'labels': [
          {
            'start_seconds': 0,
            'end_seconds': 900,
            'state': 'awake',
            'source': 'controlled_awake',
          },
        ],
        'note':
            'Offsets from session start. Use awake/asleep only for known intervals. '
            'Omit uncertain intervals. Do not label sleep from absence of recollection.',
      }),
    );
    return;
  }
  if (args.isEmpty || args.length > 2) {
    stderr.writeln(
      'Usage: dart run tool/replay_sleep.dart diagnostic.json [labels.json]',
    );
    exitCode = 1;
    return;
  }
  try {
    final diagnostic =
        jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
    final segments = (diagnostic['segments'] as List)
        .map(
          (s) =>
              SleepMonitorSegment.fromMap(Map<String, dynamic>.from(s as Map)),
        )
        .toList();
    final session = SleepMonitorSession.fromNative(
      Map<String, dynamic>.from(diagnostic['session'] as Map),
      segments,
    );
    final result = const SleepStageEngine().run(
      session: session,
      segments: segments,
    );
    if (!result.ran) throw FormatException('Cannot replay: ${result.blockers}');
    final labels = args.length == 2
        ? (jsonDecode(File(args[1]).readAsStringSync())
                  as Map<String, dynamic>)['labels']
              as List
        : const [];
    final validation = evaluateLabels(
      result.epochs,
      session.startedAt,
      labels.map((v) => Map<String, dynamic>.from(v as Map)).toList(),
    );
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert({
        'engine_version': result.epochs.firstOrNull?.algorithmVersion,
        'recorded_engine_version': diagnostic['engine_version'],
        'parameters': SleepWakeEngine.supports(session)
            ? SleepWakeEngine.parameters
            : SleepStageEngine.parameters,
        'coverage': result.coverage,
        'validation': validation,
        'epochs': [
          for (final e in result.epochs)
            {...e.toMap(), 'reason': result.decisionReasons[e.id]},
        ],
      }),
    );
  } catch (error) {
    stderr.writeln('Replay failed: $error');
    exitCode = 1;
  }
}

Map<String, dynamic> evaluateLabels(
  List<SleepStageEpoch> epochs,
  DateTime start,
  List<Map<String, dynamic>> labels,
) {
  final ordered = [...labels]
    ..sort(
      (a, b) =>
          (a['start_seconds'] as num).compareTo(b['start_seconds'] as num),
    );
  var previousEnd = 0;
  var labelled = 0;
  var unknown = 0;
  var trueAwake = 0;
  var trueSleep = 0;
  var falseSleep = 0;
  var falseAwake = 0;
  var unknownAwake = 0;
  var unknownSleep = 0;
  final sortedEpochs = [...epochs]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  DateTime? priorEpochEnd;
  for (final e in sortedEpochs) {
    if (e.durationSeconds <= 0 ||
        (priorEpochEnd != null && e.startedAt.isBefore(priorEpochEnd))) {
      throw const FormatException(
        'Epochs must be non-overlapping positive intervals',
      );
    }
    priorEpochEnd = e.endedAt;
  }
  for (final label in ordered) {
    final from = label['start_seconds'] as int;
    final to = label['end_seconds'] as int;
    final state = label['state'];
    if (from < previousEnd ||
        to <= from ||
        !['awake', 'asleep'].contains(state) ||
        label['source'] is! String ||
        (label['source'] as String).isEmpty) {
      throw const FormatException(
        'Labels need ordered non-overlapping intervals, awake/asleep and a source',
      );
    }
    previousEnd = to;
    labelled += to - from;
    var classified = 0;
    for (final epoch in sortedEpochs) {
      final epochFrom = epoch.startedAt.difference(start).inSeconds;
      final overlap = math.max<int>(
        0,
        math.min<int>(to, epochFrom + epoch.durationSeconds) -
            math.max<int>(from, epochFrom),
      );
      if (overlap == 0 || epoch.stage == SleepStageType.unknown) continue;
      classified += overlap;
      if (epoch.isSleep) {
        if (state == 'asleep') {
          trueSleep += overlap;
        } else {
          falseSleep += overlap;
        }
      } else {
        if (state == 'awake') {
          trueAwake += overlap;
        } else {
          falseAwake += overlap;
        }
      }
    }
    final missing = to - from - classified;
    unknown += missing;
    if (state == 'awake') {
      unknownAwake += missing;
    } else {
      unknownSleep += missing;
    }
  }
  double? fraction(int numerator, int denominator) =>
      denominator == 0 ? null : numerator / denominator;
  final wakeRecall = fraction(trueAwake, trueAwake + falseSleep + unknownAwake);
  final sleepRecall = fraction(
    trueSleep,
    trueSleep + falseAwake + unknownSleep,
  );
  return {
    'labelled_seconds': labelled,
    'unknown_seconds': unknown,
    'labelled_coverage': fraction(labelled - unknown, labelled),
    'false_sleep_seconds': falseSleep,
    'false_awake_seconds': falseAwake,
    'unknown_awake_seconds': unknownAwake,
    'unknown_asleep_seconds': unknownSleep,
    'awake_recall_including_abstentions': wakeRecall,
    'asleep_recall_including_abstentions': sleepRecall,
    'balanced_recall': wakeRecall == null || sleepRecall == null
        ? null
        : (wakeRecall + sleepRecall) / 2,
    'accuracy_on_classified_seconds': fraction(
      trueAwake + trueSleep,
      labelled - unknown,
    ),
  };
}
