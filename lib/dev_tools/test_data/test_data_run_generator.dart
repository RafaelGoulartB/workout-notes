import 'dart:math' as math;

import 'package:workout_notes/utils/run_pace_analytics.dart';

import 'test_data_context.dart';

class RunGenerationResult {
  final int runs;

  const RunGenerationResult({required this.runs});
}

/// Generates a realistic running scenario: three sessions per week
/// (easy / tempo / long) with gradual volume build and pace improvement,
/// plus a GPS trail per run so history, stats, splits and pace charts
/// render like real recorded data.
class TestDataRunGenerator {
  TestDataRunGenerator(this.context);

  final TestDataContext context;

  /// São Paulo city center — production runs start near the user's GPS fix,
  /// so the debug scenario just needs a plausible dense-urban coordinate.
  static const double _startLat = -23.5505;
  static const double _startLng = -46.6333;

  /// Track points recorded every N seconds (real GPS logs at 1 Hz; a sparser
  /// cadence keeps the generated scenario fast to insert while remaining
  /// dense enough for the pace chart's 80 m rolling window).
  static const int _pointIntervalSeconds = 2;

  Future<RunGenerationResult> generate() async {
    var count = 0;
    final totalDays = context.now.difference(context.start).inDays;
    for (var day = 0; day <= totalDays; day++) {
      final date = context.start.add(Duration(days: day));
      final plan = _planFor(date.weekday);
      if (plan == null || context.random.nextDouble() < 0.08) continue;
      if (await _run(date, day, plan)) count++;
    }
    return RunGenerationResult(runs: count);
  }

  _RunPlan? _planFor(int weekday) => switch (weekday) {
        DateTime.tuesday => const _RunPlan(
          kind: 'easy',
          baseKm: 6.0,
          basePaceSecPerKm: 350,
          title: 'Corrida leve',
        ),
        DateTime.thursday => const _RunPlan(
          kind: 'tempo',
          baseKm: 5.0,
          basePaceSecPerKm: 310,
          title: 'Treino de ritmo',
        ),
        DateTime.saturday => const _RunPlan(
          kind: 'long',
          baseKm: 10.0,
          basePaceSecPerKm: 335,
          title: 'Longão de fim de semana',
        ),
        _ => null,
      };

  Future<bool> _run(DateTime date, int day, _RunPlan plan) async {
    final totalDays = context.now.difference(context.start).inDays;
    final progress = totalDays == 0 ? 0.0 : (day / totalDays).clamp(0.0, 1.0);

    // Volume builds and pace improves slightly across the scenario.
    final km = plan.baseKm * (1 + progress * 0.25) + context.jitter(0, 0.4);
    final targetPace = plan.basePaceSecPerKm - progress * 20 + context.jitter(0, 6);
    final baseSpeed = 1000.0 / targetPace;

    final movingSeconds = (km * targetPace).round();
    final totalTicks = math.max(2, movingSeconds ~/ _pointIntervalSeconds);

    final startedAt = _startTime(date, plan.kind);
    final activityId = context.id('run', '$day:${plan.kind}');
    final lat = _startLat + context.jitter(0, 0.004);
    final lng = _startLng + context.jitter(0, 0.004);
    final startHeading = context.random.nextDouble() * 2 * math.pi;

    final points = <Map<String, Object?>>[];
    points.add({
      'id': context.id('run_point', '$day:0'),
      'activity_id': activityId,
      'seq': 0,
      'lat': double.parse(lat.toStringAsFixed(6)),
      'lng': double.parse(lng.toStringAsFixed(6)),
      'altitude': double.parse(
        (760 + context.jitter(0, 3)).toStringAsFixed(1),
      ),
      'accuracy': 4.0 + context.random.nextDouble() * 4,
      'speed': null,
      'recorded_at': startedAt.toIso8601String(),
    });

    var curLat = lat;
    var curLng = lng;
    var prevLat = lat;
    var prevLng = lng;
    var distanceMeters = 0.0;
    var minSecPerKm = double.infinity;
    final startedMs = startedAt.millisecondsSinceEpoch;

    for (var tick = 1; tick <= totalTicks; tick++) {
      final speed = _speedFor(tick, totalTicks, baseSpeed);
      final secPerKm = 1000.0 / speed;
      if (secPerKm < minSecPerKm) minSecPerKm = secPerKm;
      final heading = _headingAt(tick, totalTicks, startHeading);
      final step = speed * _pointIntervalSeconds;
      curLat += (step * math.cos(heading)) / 111320.0;
      curLng +=
          (step * math.sin(heading)) /
          (111320.0 * math.cos(curLat * math.pi / 180.0));
      distanceMeters += RunPaceAnalytics.haversineMeters(
        lat1: prevLat,
        lng1: prevLng,
        lat2: curLat,
        lng2: curLng,
      );
      final altitude = 760 + 18 * math.sin(tick * 0.02) + context.jitter(0, 3);
      points.add({
        'id': context.id('run_point', '$day:$tick'),
        'activity_id': activityId,
        'seq': tick,
        'lat': double.parse(curLat.toStringAsFixed(6)),
        'lng': double.parse(curLng.toStringAsFixed(6)),
        'altitude': double.parse(altitude.toStringAsFixed(1)),
        'accuracy': 4.0 + context.random.nextDouble() * 4,
        'speed': double.parse(speed.toStringAsFixed(2)),
        'recorded_at': DateTime.fromMillisecondsSinceEpoch(
          startedMs + tick * _pointIntervalSeconds * 1000,
        ).toIso8601String(),
      });
      prevLat = curLat;
      prevLng = curLng;
    }

    final elapsedSeconds = totalTicks * _pointIntervalSeconds;
    final durationSeconds = (elapsedSeconds * (1.01 + context.random.nextDouble() * 0.02)).round();
    final avgPace = distanceMeters > 0
        ? elapsedSeconds / (distanceMeters / 1000.0)
        : null;
    final endedAt = startedAt.add(Duration(seconds: elapsedSeconds));

    await context.database.insert('run_activities', {
      'id': activityId,
      'started_at': startedAt.toIso8601String(),
      'ended_at': endedAt.toIso8601String(),
      'duration_seconds': durationSeconds,
      'moving_time_seconds': elapsedSeconds,
      'distance_meters': double.parse(distanceMeters.toStringAsFixed(1)),
      'avg_pace_sec_per_km': avgPace == null
          ? null
          : double.parse(avgPace.toStringAsFixed(1)),
      'max_pace_sec_per_km': double.parse(minSecPerKm.toStringAsFixed(1)),
      'calories': (distanceMeters / 1000.0 * 70).round(),
      'title': plan.title,
      'notes': _notes(plan.kind),
      'status': 'completed',
      'polyline_summary': _polylineSummary(points),
      'created_at': startedAt.toIso8601String(),
      'updated_at': endedAt.toIso8601String(),
    });

    for (final point in points) {
      await context.database.insert('run_track_points', point);
    }
    return true;
  }

  DateTime _startTime(DateTime date, String kind) {
    final hour = switch (kind) {
      'tempo' => 6,
      'long' => 7 + context.random.nextInt(2),
      _ => 6 + context.random.nextInt(2),
    };
    return DateTime(
      date.year,
      date.month,
      date.day,
      hour,
      context.random.nextInt(4) * 15,
    );
  }

  /// Speed for a given tick — multi-frequency undulation plus a brief surge
  /// and a gradual fatigue drift, scaled to realistic running pace.
  double _speedFor(int tick, int totalTicks, double baseSpeed) {
    final slowWave = baseSpeed * 0.10 * math.sin(tick * 0.045);
    final fastWave = baseSpeed * 0.05 * math.sin(tick * 0.12 + 0.6);
    final surge = (tick % 90) < 12 ? baseSpeed * 0.06 : 0.0;
    final fatigue = baseSpeed * 0.09 * (tick / math.max(1, totalTicks));
    return math.max(1.2, baseSpeed + slowWave + fastWave + surge - fatigue);
  }

  /// Gentle weave with an eased 180° turn at the halfway point, so the map
  /// shows a plausible out-and-back route instead of a random walk.
  double _headingAt(int tick, int totalTicks, double startHeading) {
    var heading = startHeading + math.sin(tick * 0.02) * 0.2;
    final half = totalTicks ~/ 2;
    if (tick >= half) {
      final progress = (tick - half + 1) / math.max(1, totalTicks - half);
      final eased = math.min(1.0, progress * 5);
      heading += math.pi * (1 - (1 - eased) * (1 - eased));
    }
    return heading;
  }

  String? _notes(String kind) {
    if (context.random.nextDouble() > 0.25) return null;
    return switch (kind) {
      'easy' => 'Ritmo conversado, respiração tranquila',
      'tempo' => 'Ritmo confortável e desafiador',
      _ => 'Prova longa, hidratação no km 5',
    };
  }

  static String? _polylineSummary(List<Map<String, Object?>> points) {
    if (points.isEmpty) return null;
    final step = points.length <= 100 ? 1 : (points.length / 100).ceil();
    final buffer = StringBuffer();
    for (var i = 0; i < points.length; i += step) {
      final lat = points[i]['lat']! as double;
      final lng = points[i]['lng']! as double;
      if (buffer.isNotEmpty) buffer.write(';');
      buffer.write('${lat.toStringAsFixed(5)},${lng.toStringAsFixed(5)}');
    }
    return buffer.toString();
  }
}

class _RunPlan {
  final String kind;
  final double baseKm;
  final double basePaceSecPerKm;
  final String title;

  const _RunPlan({
    required this.kind,
    required this.baseKm,
    required this.basePaceSecPerKm,
    required this.title,
  });
}