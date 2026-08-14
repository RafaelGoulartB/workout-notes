import 'dart:convert';

enum PeriodizationDecision {
  maintain('maintain'),
  adjust('adjust'),
  endPhase('end_phase');

  final String value;
  const PeriodizationDecision(this.value);

  static PeriodizationDecision fromString(String? value) => values.firstWhere(
    (decision) => decision.value == value,
    orElse: () => PeriodizationDecision.maintain,
  );
}

class PeriodizationCheckin {
  final String id;
  final String phaseId;
  final DateTime weekStart;
  final int energy;
  final int hunger;
  final int recovery;
  final String performance;
  final PeriodizationDecision decision;
  final String? notes;
  final Map<String, dynamic> metricsSnapshot;
  final Map<String, dynamic> targetsSnapshot;
  final DateTime createdAt;

  const PeriodizationCheckin({
    required this.id,
    required this.phaseId,
    required this.weekStart,
    required this.energy,
    required this.hunger,
    required this.recovery,
    required this.performance,
    required this.decision,
    this.notes,
    this.metricsSnapshot = const {},
    this.targetsSnapshot = const {},
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'phase_id': phaseId,
    'week_start': _date(weekStart),
    'energy': energy,
    'hunger': hunger,
    'recovery': recovery,
    'performance': performance,
    'decision': decision.value,
    'notes': notes,
    'metrics_json': jsonEncode(metricsSnapshot),
    'targets_snapshot_json': jsonEncode(targetsSnapshot),
    'created_at': createdAt.toIso8601String(),
  };

  factory PeriodizationCheckin.fromMap(Map<String, dynamic> map) =>
      PeriodizationCheckin(
        id: map['id'] as String,
        phaseId: map['phase_id'] as String,
        weekStart: DateTime.parse(map['week_start'] as String),
        energy: (map['energy'] as num?)?.toInt() ?? 3,
        hunger: (map['hunger'] as num?)?.toInt() ?? 3,
        recovery: (map['recovery'] as num?)?.toInt() ?? 3,
        performance: map['performance'] as String? ?? 'stable',
        decision: PeriodizationDecision.fromString(map['decision'] as String?),
        notes: map['notes'] as String?,
        metricsSnapshot: _decode(map['metrics_json']),
        targetsSnapshot: _decode(map['targets_snapshot_json']),
        createdAt: DateTime.parse(map['created_at'] as String),
      );

  static Map<String, dynamic> _decode(dynamic raw) {
    if (raw is! String || raw.isEmpty) return {};
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
  }

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
