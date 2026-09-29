import 'sleep_entry.dart';
import 'sleep_monitor_session.dart';

class SleepNightSummary {
  final SleepEntry entry;
  final SleepMonitorSession? session;

  const SleepNightSummary({
    required this.entry,
    required this.session,
  });

  bool get hasStages =>
      session != null &&
      session!.analysisStatus == SleepMonitorSession.analysisAvailable &&
      (session!.sleepingMinutes != null || session!.deepSleepMinutes != null);

  int? get effectiveSleepMinutes =>
      entry.actualSleepMinutes ??
      session?.estimatedSleepMinutes ??
      entry.estimatedSleepMinutes ??
      entry.sleepMinutes;
}
