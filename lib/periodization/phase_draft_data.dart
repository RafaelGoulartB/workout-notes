import 'package:workout_notes/models/periodization_target.dart';

/// Data exchanged between the plan wizard and the phase editor in draft
/// mode: the wizard seeds the editor with an existing draft phase and the
/// editor returns the edited phase (never persisted — the wizard saves the
/// whole plan at once). [weeklyTargets] holds one effective target per week;
/// linked routines are part of each weekly target (`routineIds`).
class PeriodizationPhaseDraftData {
  final String name;
  final String? intent;
  final String? templateKey;
  final int color;
  final DateTime startDate;
  final DateTime endDate;
  final List<PeriodizationTarget> weeklyTargets;

  const PeriodizationPhaseDraftData({
    required this.name,
    this.intent,
    this.templateKey,
    required this.color,
    required this.startDate,
    required this.endDate,
    this.weeklyTargets = const [],
  });
}
