import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';

/// Read-only sleep queries exposed to the AI Coach.
///
/// The service exposes bounded, useful aggregates instead of raw microphone,
/// spectral or motion samples. Missing measurements remain null so the model
/// cannot confuse unavailable data with a measured zero.
class AiSleepToolService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiSleepToolService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> nightDetail({String? date}) async {
    final resolvedDate = _validatedDate(date ?? _date(_now()));
    final database = await db.database;
    final entries = await database.query(
      'sleep_entries',
      where: 'date = ?',
      whereArgs: [resolvedDate],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (entries.isEmpty) {
      return {
        'date': resolvedDate,
        'found': false,
        'message': 'No sleep entry was recorded for this local date.',
      };
    }

    final entry = entries.first;
    final session = await _sessionForEntry(entry['id'] as String);
    final epochSummary = session == null
        ? null
        : await _stageEpochSummary(session['id'] as String);
    final duration = _duration(entry, session);
    final timeInBed =
        (entry['time_in_bed_minutes'] ?? session?['time_in_bed_minutes'])
            as num?;
    final computedEfficiency = _efficiency(
      duration.effectiveMinutes,
      timeInBed?.toDouble(),
    );

    return {
      'date': resolvedDate,
      'found': true,
      'entryId': entry['id'],
      'source': entry['source'],
      'comment': entry['comment'],
      'duration': duration.toMap(),
      'schedule': {
        'bedtimeMinutesAfterMidnight': entry['bedtime_minutes'],
        'bedtimeLocal': _clock(entry['bedtime_minutes']),
        'wakeTimeMinutesAfterMidnight': entry['wake_time_minutes'],
        'wakeTimeLocal': _clock(entry['wake_time_minutes']),
        'timeInBedMinutes': timeInBed?.toInt(),
        'sleepOnsetAt': session?['sleep_onset_at'],
        'finalWakeAt': session?['final_wake_at'],
        'sleepLatencyMinutes': session?['sleep_latency_minutes'],
      },
      'stages': {
        'available':
            session?['analysis_status'] ==
            SleepMonitorSession.analysisAvailable,
        'analysisStatus': session?['analysis_status'],
        'awakeMinutes': session?['awake_minutes'],
        'sleepingMinutes': session?['sleeping_minutes'],
        'deepSleepMinutes': session?['deep_sleep_minutes'],
        'unknownMinutes': session?['unknown_minutes'],
        'awakeningCount': session?['awakening_count'],
        'efficiencyPct': _roundOrNull(
          (session?['sleep_efficiency'] as num?)?.toDouble() ??
              computedEfficiency,
        ),
        'efficiencySource': session?['sleep_efficiency'] != null
            ? 'sleep_stage_analysis'
            : computedEfficiency != null
            ? 'effective_sleep_divided_by_time_in_bed'
            : null,
        'confidence': session?['stage_confidence'],
        'algorithmVersion': session?['stage_algorithm_version'],
        'epochSummary': epochSummary,
      },
      'monitoring': session == null
          ? null
          : {
              'sessionId': session['id'],
              'status': session['status'],
              'monitorMode': session['monitor_mode'],
              'sensorMode': session['sensor_mode'],
              'startedAt': session['started_at'],
              'endedAt': session['ended_at'],
              'endReason': session['end_reason'],
              'analysisStatus': session['analysis_status'],
              'signalQualityScore': session['signal_quality_score'],
              'noise': {
                'quietMinutes': session['quiet_minutes'],
                'noisyMinutes': session['noisy_minutes'],
                'eventCount': session['noise_event_count'],
              },
            },
      'createdAt': entry['created_at'],
      'dataSemantics': {
        'null': 'measurement unavailable or not reported',
        'durationPriority': const [
          'actual_sleep_minutes',
          'monitor_estimated_sleep_minutes',
          'estimated_sleep_minutes',
          'recorded_sleep_minutes',
        ],
        'monitoringLimitations':
            'noise and acoustic sleep stages are non-clinical estimates; they do not diagnose snoring, apnea or another condition',
      },
    };
  }

  Future<Map<String, dynamic>> history({int days = 30, String? endDate}) async {
    days = days.clamp(1, 31);
    final database = await db.database;
    final end = _validatedDate(endDate ?? _date(_now()));
    final endDay = DateTime.parse(end);
    final start = _date(endDay.subtract(Duration(days: days - 1)));
    final entries = await database.query(
      'sleep_entries',
      where: 'date BETWEEN ? AND ?',
      whereArgs: [start, end],
      orderBy: 'date DESC, created_at DESC',
    );

    final nights = <Map<String, dynamic>>[];
    for (final entry in entries.reversed) {
      final session = await _sessionForEntry(entry['id'] as String);
      nights.add(_historyNight(entry, session));
    }

    return {
      'startDate': start,
      'endDate': end,
      'windowDays': days,
      'recordedNights': nights.length,
      'coveragePct': _round(nights.length / days * 100),
      'nights': nights,
      'previousEndDate': _date(
        DateTime.parse(start).subtract(const Duration(days: 1)),
      ),
      'dataSemantics':
          'missing dates are absent; null means a measurement was unavailable, not zero',
    };
  }

  Future<Map<String, dynamic>> profile() async {
    final database = await db.database;
    final settingsRows = await database.query(
      'app_settings',
      where: 'key IN (?, ?)',
      whereArgs: const ['sleep_goal_minutes', 'sleep_monitor_default_mode'],
    );
    final settings = {
      for (final row in settingsRows)
        row['key'] as String: row['value'] as String?,
    };
    final rawGoal = int.tryParse(settings['sleep_goal_minutes'] ?? '');
    final goalMinutes = SleepGoalService.normalize(
      rawGoal ?? SleepGoalService.defaultGoalMinutes,
    );
    final start30 = _date(_now().subtract(const Duration(days: 29)));

    return {
      'dailyGoalMinutes': goalMinutes,
      'goalSource': rawGoal == null ? 'app_default' : 'user_setting',
      'defaultMonitorMode':
          settings['sleep_monitor_default_mode'] ?? 'alarm_without_mission',
      'allTime': await _profilePeriod(goalMinutes: goalMinutes),
      'last30Days': await _profilePeriod(
        goalMinutes: goalMinutes,
        fromDate: start30,
      ),
      'privacy':
          'alarm mission secrets, barcode hashes and salts are never exposed to the AI Coach',
    };
  }

  Future<Map<String, dynamic>?> _sessionForEntry(String entryId) async {
    final database = await db.database;
    final rows = await database.query(
      'sleep_monitor_sessions',
      where: 'sleep_entry_id = ?',
      whereArgs: [entryId],
      orderBy: 'started_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<Map<String, dynamic>> _stageEpochSummary(String sessionId) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT
        COUNT(*) epoch_count,
        SUM(CASE WHEN stage != 'unknown' THEN 1 ELSE 0 END) known_epoch_count,
        SUM(CASE WHEN stage = 'awake' THEN duration_seconds ELSE 0 END) awake_seconds,
        SUM(CASE WHEN stage = 'sleeping' THEN duration_seconds ELSE 0 END) sleeping_seconds,
        SUM(CASE WHEN stage = 'deep' THEN duration_seconds ELSE 0 END) deep_seconds,
        SUM(CASE WHEN stage = 'unknown' THEN duration_seconds ELSE 0 END) unknown_seconds,
        AVG(CASE WHEN stage != 'unknown' THEN confidence END) average_confidence
      FROM sleep_stage_epochs
      WHERE session_id = ?
      ''',
      [sessionId],
    );
    final row = rows.first;
    final total = (row['epoch_count'] as num?)?.toInt() ?? 0;
    final known = (row['known_epoch_count'] as num?)?.toInt() ?? 0;
    double? minutes(String key) {
      final seconds = (row[key] as num?)?.toDouble();
      return seconds == null ? null : _round(seconds / 60);
    }

    return {
      'epochCount': total,
      'knownEpochCount': known,
      'coveragePct': total == 0 ? 0.0 : _round(known / total * 100),
      'awakeMinutes': minutes('awake_seconds'),
      'sleepingMinutes': minutes('sleeping_seconds'),
      'deepSleepMinutes': minutes('deep_seconds'),
      'unknownMinutes': minutes('unknown_seconds'),
      'averageConfidence': _roundOrNull(
        (row['average_confidence'] as num?)?.toDouble(),
      ),
    };
  }

  Map<String, dynamic> _historyNight(
    Map<String, dynamic> entry,
    Map<String, dynamic>? session,
  ) {
    final duration = _duration(entry, session);
    final timeInBed =
        (entry['time_in_bed_minutes'] ?? session?['time_in_bed_minutes'])
            as num?;
    return {
      'date': entry['date'],
      'entryId': entry['id'],
      'source': entry['source'],
      'duration': duration.toMap(),
      'bedtimeMinutesAfterMidnight': entry['bedtime_minutes'],
      'bedtimeLocal': _clock(entry['bedtime_minutes']),
      'wakeTimeMinutesAfterMidnight': entry['wake_time_minutes'],
      'wakeTimeLocal': _clock(entry['wake_time_minutes']),
      'timeInBedMinutes': timeInBed?.toInt(),
      'efficiencyPct': _roundOrNull(
        (session?['sleep_efficiency'] as num?)?.toDouble() ??
            _efficiency(duration.effectiveMinutes, timeInBed?.toDouble()),
      ),
      'hasSleepStages':
          session?['analysis_status'] == SleepMonitorSession.analysisAvailable,
      'analysisStatus': session?['analysis_status'],
      'deepSleepMinutes': session?['deep_sleep_minutes'],
      'awakeningCount': session?['awakening_count'],
    };
  }

  Future<Map<String, dynamic>> _profilePeriod({
    required int goalMinutes,
    String? fromDate,
  }) async {
    final database = await db.database;
    final where = fromDate == null ? '' : 'WHERE se.date >= ?';
    final args = fromDate == null ? const <Object?>[] : <Object?>[fromDate];
    final entryRows = await database.rawQuery(
      '''
      SELECT
        COUNT(*) recorded_nights,
        SUM(CASE WHEN se.source = 'manual' THEN 1 ELSE 0 END) manual_nights,
        SUM(CASE WHEN se.source != 'manual' THEN 1 ELSE 0 END) monitored_nights,
        AVG(COALESCE(se.actual_sleep_minutes, se.estimated_sleep_minutes, se.sleep_minutes)) average_sleep_minutes,
        SUM(CASE WHEN COALESCE(se.actual_sleep_minutes, se.estimated_sleep_minutes, se.sleep_minutes) >= ? THEN 1 ELSE 0 END) nights_meeting_goal
      FROM sleep_entries se
      $where
      ''',
      [goalMinutes, ...args],
    );
    final stageWhere = fromDate == null ? '' : 'AND se.date >= ?';
    final stageRows = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT CASE WHEN sms.analysis_status = ? THEN se.id END) stage_available_nights
      FROM sleep_entries se
      LEFT JOIN sleep_monitor_sessions sms ON sms.sleep_entry_id = se.id
      WHERE 1 = 1 $stageWhere
      ''',
      [SleepMonitorSession.analysisAvailable, ...args],
    );
    final row = entryRows.first;
    final recorded = (row['recorded_nights'] as num?)?.toInt() ?? 0;
    final monitored = (row['monitored_nights'] as num?)?.toInt() ?? 0;
    final average = (row['average_sleep_minutes'] as num?)?.toDouble();
    final stageAvailable =
        (stageRows.first['stage_available_nights'] as num?)?.toInt() ?? 0;
    return {
      'recordedNights': recorded,
      'manualNights': (row['manual_nights'] as num?)?.toInt() ?? 0,
      'monitoredNights': monitored,
      'stageAvailableNights': stageAvailable,
      'stageCoveragePct': monitored == 0
          ? 0.0
          : _round(stageAvailable / monitored * 100),
      'averageSleepMinutes': _roundOrNull(average),
      'differenceFromGoalMinutes': average == null
          ? null
          : _round(average - goalMinutes),
      'goalAchievementPct': average == null
          ? null
          : _round(average / goalMinutes * 100),
      'nightsMeetingGoal': (row['nights_meeting_goal'] as num?)?.toInt() ?? 0,
    };
  }

  static _ResolvedDuration _duration(
    Map<String, dynamic> entry,
    Map<String, dynamic>? session,
  ) {
    final recorded = (entry['sleep_minutes'] as num?)?.toInt();
    final actual = (entry['actual_sleep_minutes'] as num?)?.toInt();
    final estimated = (entry['estimated_sleep_minutes'] as num?)?.toInt();
    final monitorEstimated = (session?['estimated_sleep_minutes'] as num?)
        ?.toInt();
    if (actual != null) {
      return _ResolvedDuration(
        recordedMinutes: recorded,
        actualMinutes: actual,
        estimatedMinutes: estimated,
        monitorEstimatedMinutes: monitorEstimated,
        effectiveMinutes: actual,
        effectiveSource: 'actual_sleep_minutes',
      );
    }
    if (monitorEstimated != null) {
      return _ResolvedDuration(
        recordedMinutes: recorded,
        actualMinutes: null,
        estimatedMinutes: estimated,
        monitorEstimatedMinutes: monitorEstimated,
        effectiveMinutes: monitorEstimated,
        effectiveSource: 'monitor_estimated_sleep_minutes',
      );
    }
    if (estimated != null) {
      return _ResolvedDuration(
        recordedMinutes: recorded,
        actualMinutes: null,
        estimatedMinutes: estimated,
        monitorEstimatedMinutes: null,
        effectiveMinutes: estimated,
        effectiveSource: 'estimated_sleep_minutes',
      );
    }
    return _ResolvedDuration(
      recordedMinutes: recorded,
      actualMinutes: null,
      estimatedMinutes: null,
      monitorEstimatedMinutes: null,
      effectiveMinutes: recorded,
      effectiveSource: 'recorded_sleep_minutes',
    );
  }

  static double? _efficiency(num? asleep, num? inBed) {
    if (asleep == null || inBed == null || inBed <= 0) return null;
    return (asleep / inBed * 100).clamp(0, 100).toDouble();
  }

  static String? _clock(Object? raw) {
    final minutes = (raw as num?)?.toInt();
    if (minutes == null) return null;
    final normalized = minutes % 1440;
    final hour = normalized ~/ 60;
    final minute = normalized % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  static String _validatedDate(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const FormatException('date must use YYYY-MM-DD');
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || _date(parsed) != value) {
      throw const FormatException('date is invalid');
    }
    return value;
  }

  static String _date(DateTime value) =>
      value.toIso8601String().substring(0, 10);

  static double _round(double value) => (value * 10).round() / 10;

  static double? _roundOrNull(double? value) =>
      value == null ? null : _round(value);
}

class _ResolvedDuration {
  final int? recordedMinutes;
  final int? actualMinutes;
  final int? estimatedMinutes;
  final int? monitorEstimatedMinutes;
  final int? effectiveMinutes;
  final String effectiveSource;

  const _ResolvedDuration({
    required this.recordedMinutes,
    required this.actualMinutes,
    required this.estimatedMinutes,
    required this.monitorEstimatedMinutes,
    required this.effectiveMinutes,
    required this.effectiveSource,
  });

  Map<String, dynamic> toMap() => {
    'recordedMinutes': recordedMinutes,
    'actualMinutes': actualMinutes,
    'estimatedMinutes': estimatedMinutes,
    'monitorEstimatedMinutes': monitorEstimatedMinutes,
    'effectiveMinutes': effectiveMinutes,
    'effectiveSource': effectiveSource,
  };
}
