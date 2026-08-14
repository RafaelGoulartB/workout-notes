import 'periodization_target.dart';

class PeriodizationPhaseDraft {
  final String name;
  final String? templateKey;
  final int color;
  final DateTime startDate;
  final DateTime endDate;
  final String? intent;
  final PeriodizationTarget? target;
  final String? routineId;

  const PeriodizationPhaseDraft({
    required this.name,
    this.templateKey,
    required this.color,
    required this.startDate,
    required this.endDate,
    this.intent,
    this.target,
    this.routineId,
  });
}
