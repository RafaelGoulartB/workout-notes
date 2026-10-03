// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'dart:math' as math;

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Where a night's sleep duration came from, best source first.
abstract final class AiSleepDurationSource {
  static const actual = 'actual';
  static const monitorEstimate = 'monitor_estimate';
  static const entryEstimate = 'entry_estimate';
  static const recorded = 'recorded';
}

/// One recorded night with its duration and efficiency resolved ONCE, so every
/// sleep tool and the wellness analytics show the same numbers for it.
///
/// Duration: `actual_sleep_minutes`, then the monitor session's
/// `estimated_sleep_minutes`, then the entry's `estimated_sleep_minutes`, then
/// the recorded `sleep_minutes`. Efficiency: the monitor session's
/// `sleep_efficiency` when present, else duration / time in bed (0-100).
class AiSleepNight {
  final Map<String, Object?> row;

  const AiSleepNight(this.row);

  /// SELECT that joins every entry with its latest monitor session in ONE
  /// query. Session columns are prefixed with `s_`.
  static const String selectSql = '''
    SELECT se.id, se.date, se.sleep_minutes, se.actual_sleep_minutes,
      se.bedtime_minutes, se.wake_time_minutes, se.comment, se.source,
      se.time_in_bed_minutes, se.estimated_sleep_minutes,
      sms.id AS s_id, sms.status AS s_status,
      sms.monitor_mode AS s_monitor_mode, sms.started_at AS s_started_at,
      sms.ended_at AS s_ended_at, sms.alarm_at AS s_alarm_at,
      sms.time_in_bed_minutes AS s_time_in_bed_minutes,
      sms.estimated_sleep_minutes AS s_estimated_sleep_minutes,
      sms.quiet_minutes AS s_quiet_minutes,
      sms.noisy_minutes AS s_noisy_minutes,
      sms.noise_event_count AS s_noise_event_count,
      sms.signal_quality_score AS s_signal_quality_score,
      sms.analysis_status AS s_analysis_status,
      sms.sleep_onset_at AS s_sleep_onset_at,
      sms.final_wake_at AS s_final_wake_at,
      sms.sleep_latency_minutes AS s_sleep_latency_minutes,
      sms.awake_minutes AS s_awake_minutes,
      sms.sleeping_minutes AS s_sleeping_minutes,
      sms.unknown_minutes AS s_unknown_minutes,
      sms.restless_sleep_minutes AS s_restless_sleep_minutes,
      sms.snore_minutes AS s_snore_minutes,
      sms.awakening_count AS s_awakening_count,
      sms.sleep_efficiency AS s_sleep_efficiency,
      sms.stage_confidence AS s_stage_confidence,
      sms.stage_algorithm_version AS s_stage_algorithm_version,
      sms.smart_window_minutes AS s_smart_window_minutes,
      sms.alarm_fired_at AS s_alarm_fired_at,
      sms.alarm_trigger AS s_alarm_trigger,
      sms.wake_feeling AS s_wake_feeling
    FROM sleep_entries se
    LEFT JOIN sleep_monitor_sessions sms ON sms.id = (
      SELECT s2.id FROM sleep_monitor_sessions s2
      WHERE s2.sleep_entry_id = se.id
      ORDER BY s2.started_at DESC, s2.id DESC LIMIT 1
    )
  ''';

  /// Nights dated [startKey]..[endKey] (inclusive), newest first, with a
  /// single query (no per-night lookups).
  static Future<List<AiSleepNight>> load(
    DatabaseHelper db, {
    required String startKey,
    required String endKey,
    int? limit,
  }) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '$selectSql WHERE se.date >= ? AND se.date <= ? '
      'ORDER BY se.date DESC${limit == null ? '' : ' LIMIT $limit'}',
      [startKey, endKey],
    );
    return [for (final row in rows) AiSleepNight(row)];
  }

  /// The night of [date], or null.
  static Future<AiSleepNight?> loadDate(DatabaseHelper db, String date) async {
    final nights = await load(db, startKey: date, endKey: date, limit: 1);
    return nights.isEmpty ? null : nights.first;
  }

  int? _int(String key) => (row[key] as num?)?.toInt();
  double? _double(String key) => (row[key] as num?)?.toDouble();
  String? _text(String key) => row[key] as String?;

  String get date => row['date']! as String;
  String get entryId => row['id']! as String;
  String? get source => _text('source');
  String? get comment => _text('comment');
  bool get hasSession => row['s_id'] != null;

  int? get recordedMinutes => _int('sleep_minutes');
  int? get actualMinutes => _int('actual_sleep_minutes');
  int? get entryEstimateMinutes => _int('estimated_sleep_minutes');
  int? get monitorEstimateMinutes => _int('s_estimated_sleep_minutes');

  int? get minutes =>
      actualMinutes ??
      monitorEstimateMinutes ??
      entryEstimateMinutes ??
      recordedMinutes;

  String? get durationSource {
    if (actualMinutes != null) return AiSleepDurationSource.actual;
    if (monitorEstimateMinutes != null) {
      return AiSleepDurationSource.monitorEstimate;
    }
    if (entryEstimateMinutes != null) {
      return AiSleepDurationSource.entryEstimate;
    }
    if (recordedMinutes != null) return AiSleepDurationSource.recorded;
    return null;
  }

  int? get timeInBedMinutes =>
      _int('time_in_bed_minutes') ?? _int('s_time_in_bed_minutes');

  /// 0-100. Prefers the monitor session's own value.
  double? get efficiencyPct {
    final session = _double('s_sleep_efficiency');
    if (session != null) return session.clamp(0, 100).toDouble();
    final asleep = minutes;
    final inBed = timeInBedMinutes;
    if (asleep == null || inBed == null || inBed <= 0) return null;
    return (asleep / inBed * 100).clamp(0, 100).toDouble();
  }

  int? get bedtimeMinutes => _int('bedtime_minutes');
  int? get wakeMinutes => _int('wake_time_minutes');
  String? get bedtime => AiToolMath.clock(bedtimeMinutes);
  String? get wake => AiToolMath.clock(wakeMinutes);

  int? get awakenings => _int('s_awakening_count');
  int? get snoreMinutes => _int('s_snore_minutes');
  String? get alarmTrigger => _text('s_alarm_trigger');
  int? get wakeFeeling => _int('s_wake_feeling');
  int? get smartWindowMinutes => _int('s_smart_window_minutes');

  /// The session had an alarm set or an alarm that rang.
  bool get hadAlarm =>
      _text('s_alarm_at') != null || _text('s_alarm_fired_at') != null;

  bool get stagesAvailable =>
      _text('s_analysis_status') == SleepMonitorSession.analysisAvailable;

  /// Schedule regularity 0-100: how close bedtimes and wake times stay to
  /// their circular means (3 h of average drift scores 0). Null with fewer
  /// than two nights of either.
  static double? regularityScore(
    List<double> bedtimes,
    List<double> wakeTimes,
  ) {
    if (bedtimes.length < 2 || wakeTimes.length < 2) return null;
    double score(List<double> values) {
      final center = AiToolMath.circularMeanMinutes(values);
      final deviation = AiToolMath.average(
        values.map((v) => AiToolMath.circularDistanceMinutes(v, center)),
      )!;
      return (100 * (1 - math.min(deviation, 180) / 180)).clamp(0, 100);
    }

    return (score(bedtimes) + score(wakeTimes)) / 2;
  }

  /// The user's nightly sleep goal in minutes (setting or app default).
  static Future<int> goalMinutes(DatabaseHelper db) =>
      SleepGoalService(settings: db.settingsRepo).load();
}

/// Read-only sleep queries exposed to the AI Coach (`get_sleep`,
/// `get_sleep` with `detail: night`).
///
/// Durations and efficiencies come from [AiSleepNight], the only resolver, so
/// they match the wellness analytics. Raw microphone, spectral or motion data
/// never leaves the device; missing measurements stay absent.
class AiSleepToolService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiSleepToolService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  static const summaryDetail = 'summary';
  static const nightlyDetail = 'nightly';
  static const nightDetailMode = 'night';
  static const details = [summaryDetail, nightlyDetail];

  /// Every `detail` value of the `get_sleep` tool; `night` is served by
  /// [nightDetail].
  static const detailModes = [summaryDetail, nightlyDetail, nightDetailMode];

  /// `get_sleep`: [detail] is `summary` or `nightly`; the window ends at
  /// [endDate] (default today).
  Future<Map<String, dynamic>> sleep({
    int days = 14,
    String? endDate,
    String detail = summaryDetail,
  }) async {
    if (!details.contains(detail)) {
      throw AiToolArgException.invalid(
        'detail',
        'one of ${details.join(', ')}',
        detail,
      );
    }
    final today = dayOf(_now());
    final requested = AiToolMath.window(
      today: today,
      days: days,
      endDate: _date('end_date', endDate),
      defaultDays: 14,
      maxDays: 90,
    );
    // Nights after today cannot exist: never let them deflate the coverage.
    final window = requested.end.isAfter(today)
        ? AiDateWindow(
            requested.start.isAfter(today) ? today : requested.start,
            today,
            capped: true,
          )
        : requested;
    final nights = await AiSleepNight.load(
      db,
      startKey: window.startKey,
      endKey: window.endKey,
    );
    final result = <String, dynamic>{
      'applied': {...window.toApplied(), 'detail': detail},
      'recorded_nights': nights.length,
      'coverage_pct': nights.length / window.days * 100,
    };
    if (detail == nightlyDetail) {
      result['nights'] = [for (final night in nights) _nightlyRow(night)];
      final database = await db.database;
      final older = await database.query(
        'sleep_entries',
        columns: ['date'],
        where: 'date < ?',
        whereArgs: [window.startKey],
        orderBy: 'date DESC',
        limit: 1,
      );
      if (older.isNotEmpty) {
        result['has_more'] = true;
        result['next_end_date'] = dateKey(addDays(window.start, -1));
      }
      return result;
    }
    result.addAll(await _summary(nights));
    return result;
  }

  Map<String, dynamic> _nightlyRow(AiSleepNight night) => {
    'date': night.date,
    'duration_min': night.minutes,
    'efficiency_pct': night.efficiencyPct,
    'bedtime': night.bedtime,
    'wake': night.wake,
    'time_in_bed_min': night.timeInBedMinutes,
    'awakenings': night.awakenings,
    'source': night.source,
  };

  Future<Map<String, dynamic>> _summary(List<AiSleepNight> nights) async {
    if (nights.isEmpty) return const {};
    final durations = [
      for (final n in nights)
        if (n.minutes != null) n.minutes!.toDouble(),
    ];
    final efficiencies = [
      for (final n in nights)
        if (n.efficiencyPct != null) n.efficiencyPct!,
    ];
    final bedtimes = [
      for (final n in nights)
        if (n.bedtimeMinutes != null) n.bedtimeMinutes!.toDouble(),
    ];
    final wakes = [
      for (final n in nights)
        if (n.wakeMinutes != null) n.wakeMinutes!.toDouble(),
    ];
    final awakenings = [
      for (final n in nights)
        if (n.awakenings != null) n.awakenings!.toDouble(),
    ];
    final snoring = [
      for (final n in nights)
        if (n.snoreMinutes != null) n.snoreMinutes!.toDouble(),
    ];
    final goal = await AiSleepNight.goalMinutes(db);
    final average = AiToolMath.average(durations);

    final sources = <String, int>{};
    for (final night in nights) {
      final source = night.durationSource;
      if (source != null) sources[source] = (sources[source] ?? 0) + 1;
    }
    final manual = nights.where((n) => n.source == 'manual').length;

    return {
      'avg_sleep_min': average,
      'min_sleep_min': AiToolMath.minimum(durations),
      'max_sleep_min': AiToolMath.maximum(durations),
      'avg_efficiency_pct': AiToolMath.average(efficiencies),
      'regularity_score': AiSleepNight.regularityScore(bedtimes, wakes),
      'avg_bedtime': bedtimes.isEmpty
          ? null
          : AiToolMath.clock(AiToolMath.circularMeanMinutes(bedtimes).round()),
      'avg_wake': wakes.isEmpty
          ? null
          : AiToolMath.clock(AiToolMath.circularMeanMinutes(wakes).round()),
      'goal_min': goal,
      'avg_vs_goal_min': average == null ? null : average - goal,
      'goal_achievement_pct': average == null ? null : average / goal * 100,
      'nights_meeting_goal': durations.where((m) => m >= goal).length,
      'manual_nights': manual,
      'monitored_nights': nights.length - manual,
      'avg_awakenings': AiToolMath.average(awakenings),
      'avg_snoring_min': AiToolMath.average(snoring),
      'duration_sources': sources,
      'alarm': _alarmStats(nights),
    };
  }

  /// Smart-alarm usage; null when no night in the window had an alarm.
  Map<String, dynamic>? _alarmStats(List<AiSleepNight> nights) {
    final alarmNights = nights.where((n) => n.hadAlarm).toList();
    if (alarmNights.isEmpty) return null;
    int count(bool Function(AiSleepNight) test) =>
        alarmNights.where(test).length;
    final feelings = <int, int>{};
    for (final night in alarmNights) {
      final feeling = night.wakeFeeling;
      if (feeling != null) feelings[feeling] = (feelings[feeling] ?? 0) + 1;
    }
    return {
      'nights': alarmNights.length,
      'smart_window_nights': count((n) => (n.smartWindowMinutes ?? 0) > 0),
      'triggered_awake': count(
        (n) => n.alarmTrigger == SleepMonitorSession.triggerAwake,
      ),
      'triggered_stirring': count(
        (n) => n.alarmTrigger == SleepMonitorSession.triggerStirring,
      ),
      'triggered_deadline': count(
        (n) => n.alarmTrigger == SleepMonitorSession.triggerDeadline,
      ),
      if (feelings.isNotEmpty)
        'wake_feeling_nights': {
          'tired': feelings[SleepMonitorSession.feelingTired],
          'okay': feelings[SleepMonitorSession.feelingOkay],
          'refreshed': feelings[SleepMonitorSession.feelingRefreshed],
        },
    };
  }

  /// `get_sleep` with `detail: night`: the night recorded for local [date] (default
  /// today).
  Future<Map<String, dynamic>> nightDetail({String? date}) async {
    final day = _date('date', date) ?? dateKey(dayOf(_now()));
    final night = await AiSleepNight.loadDate(db, day);
    if (night == null) {
      throw AiToolNotFoundException(
        'no sleep recorded for $day',
        hint: 'call get_sleep with detail=nightly to see recorded dates',
      );
    }
    final minutes = night.minutes;
    int? distinct(int? value) => value == minutes ? null : value;
    final row = night.row;
    int? n(String key) => (row[key] as num?)?.toInt();
    double? d(String key) => (row[key] as num?)?.toDouble();
    String? t(String key) => row[key] as String?;
    final signal = d('s_signal_quality_score');
    final confidence = d('s_stage_confidence');
    final feeling = night.wakeFeeling;

    return {
      'date': night.date,
      'id': night.entryId,
      'source': night.source,
      'comment': night.comment,
      'duration': {
        'minutes': minutes,
        'source': night.durationSource,
        'recorded_min': distinct(night.recordedMinutes),
        'actual_min': distinct(night.actualMinutes),
        'monitor_estimate_min': distinct(night.monitorEstimateMinutes),
        'entry_estimate_min': distinct(night.entryEstimateMinutes),
      },
      'efficiency_pct': night.efficiencyPct,
      'bedtime': night.bedtime,
      'wake': night.wake,
      'time_in_bed_min': night.timeInBedMinutes,
      'sleep_latency_min': n('s_sleep_latency_minutes'),
      'sleep_onset_at': t('s_sleep_onset_at'),
      'final_wake_at': t('s_final_wake_at'),
      'stages': night.stagesAvailable
          ? {
              'awake_min': n('s_awake_minutes'),
              'sleeping_min': n('s_sleeping_minutes'),
              'unknown_min': n('s_unknown_minutes'),
              'restless_min': n('s_restless_sleep_minutes'),
              'snore_min': n('s_snore_minutes'),
              'awakenings': n('s_awakening_count'),
              'confidence_pct': confidence == null ? null : confidence * 100,
              'algorithm_version': t('s_stage_algorithm_version'),
            }
          : null,
      'monitoring': night.hasSession
          ? {
              'session_id': t('s_id'),
              'status': t('s_status'),
              'mode': t('s_monitor_mode'),
              'started_at': t('s_started_at'),
              'ended_at': t('s_ended_at'),
              'signal_quality_pct': signal == null ? null : signal * 100,
              'quiet_min': n('s_quiet_minutes'),
              'noisy_min': n('s_noisy_minutes'),
              'noise_events': n('s_noise_event_count'),
            }
          : null,
      'alarm':
          night.hadAlarm ||
              night.smartWindowMinutes != null ||
              night.alarmTrigger != null
          ? {
              'alarm_at': t('s_alarm_at'),
              'smart_window_minutes': night.smartWindowMinutes,
              'alarm_fired_at': t('s_alarm_fired_at'),
              'alarm_trigger': night.alarmTrigger,
              'wake_feeling': switch (feeling) {
                SleepMonitorSession.feelingTired => 'tired',
                SleepMonitorSession.feelingOkay => 'okay',
                SleepMonitorSession.feelingRefreshed => 'refreshed',
                _ => null,
              },
            }
          : null,
    };
  }

  /// Strict `yyyy-MM-dd` (throws `invalid_args`), null when absent.
  static String? _date(String param, String? value) =>
      AiToolArgs({param: value}).date(param);
}
