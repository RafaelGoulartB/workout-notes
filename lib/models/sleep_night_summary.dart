import 'sleep_entry.dart';
import 'sleep_monitor_session.dart';
import 'sleep_stage_epoch.dart';
import 'sleep_stage_type.dart';

class SleepNightSummary {
  final SleepEntry entry;
  final SleepMonitorSession? session;
  final List<SleepStageEpoch> stages;

  const SleepNightSummary({
    required this.entry,
    required this.session,
    required this.stages,
  });

  bool get hasStages =>
      stages.any((epoch) => epoch.stage != SleepStageType.unknown) ||
      (session != null &&
          session!.analysisStatus == SleepMonitorSession.analysisAvailable &&
          (session!.sleepingMinutes != null ||
              session!.deepSleepMinutes != null));

  int? get effectiveSleepMinutes =>
      entry.actualSleepMinutes ??
      session?.estimatedSleepMinutes ??
      entry.estimatedSleepMinutes ??
      entry.sleepMinutes;
}
