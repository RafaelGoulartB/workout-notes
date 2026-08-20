/// Helpers to finalize interrupted native run spools before SQLite import.
class RunSpoolRecovery {
  /// Marks an in-progress spool as completed and reconciles duration fields.
  ///
  /// Prefers the last GPS point timestamp for [ended_at] so wall-clock time
  /// after process death does not inflate moving pace. Duration is raised to
  /// match start→end when the spool was stale; moving time is never increased
  /// above duration.
  static void finalizeInterruptedActivity(
    Map<String, dynamic> activity, {
    List<Map<String, dynamic>> points = const [],
    DateTime? now,
  }) {
    activity['status'] = 'completed';

    DateTime? lastPointAt;
    for (var i = points.length - 1; i >= 0; i--) {
      lastPointAt = DateTime.tryParse(points[i]['recorded_at'] as String? ?? '');
      if (lastPointAt != null) break;
    }

    final startedAt = DateTime.tryParse(activity['started_at'] as String? ?? '');
    final storedDuration = (activity['duration_seconds'] as num?)?.toInt() ?? 0;
    final clock = now ?? DateTime.now();
    final endedAt = lastPointAt ??
        (startedAt != null
            ? startedAt.add(Duration(seconds: storedDuration.clamp(0, 48 * 3600)))
            : clock);

    activity['ended_at'] ??= endedAt.toIso8601String();

    if (startedAt != null) {
      final wallSeconds = endedAt.difference(startedAt).inSeconds.clamp(0, 48 * 3600);
      if (wallSeconds > storedDuration) {
        activity['duration_seconds'] = wallSeconds;
      } else if (storedDuration <= 0 && wallSeconds > 0) {
        activity['duration_seconds'] = wallSeconds;
      }
    }

    final duration = (activity['duration_seconds'] as num?)?.toInt() ?? 0;
    final moving = (activity['moving_time_seconds'] as num?)?.toInt() ?? duration;
    activity['moving_time_seconds'] = moving.clamp(0, duration);

    final distance = (activity['distance_meters'] as num?)?.toDouble() ?? 0;
    final movingFinal = (activity['moving_time_seconds'] as num?)?.toInt() ?? 0;
    if (distance >= 1 && movingFinal > 0) {
      activity['avg_pace_sec_per_km'] = movingFinal / (distance / 1000.0);
    }
  }
}
