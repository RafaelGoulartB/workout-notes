import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/periodization_palette.dart';

/// What a phase is for. Picking a kind sets the phase colour and icon and
/// seeds sensible nutrition/body defaults; the kind's [key] is stored in
/// `periodization_phases.template_key`.
///
/// Phases saved by the old wizard used finer template keys (`base`,
/// `intensification`, `taper`…); [fromKey] folds them onto the closest kind.
enum PhaseKind {
  cut(
    key: 'cutting',
    color: kPhaseColorBlue,
    icon: Icons.trending_down_rounded,
    calorieFactor: 0.8,
    proteinPerKg: 2.2,
    fatPerKg: 0.8,
    weeklyWeightChangePercent: -0.5,
  ),
  bulk(
    key: 'bulking',
    color: kPhaseColorPurple,
    icon: Icons.trending_up_rounded,
    calorieFactor: 1.1,
    proteinPerKg: 1.8,
    fatPerKg: 1.0,
    weeklyWeightChangePercent: 0.25,
  ),
  maintenance(
    key: 'maintenance',
    color: kPhaseColorGreen,
    icon: Icons.balance_rounded,
    calorieFactor: 1.0,
    proteinPerKg: 1.8,
    fatPerKg: 1.0,
    weeklyWeightChangePercent: 0,
  ),
  strength(
    key: 'strength',
    color: kPhaseColorRed,
    icon: Icons.fitness_center_rounded,
    calorieFactor: 1.0,
    proteinPerKg: 2.0,
    fatPerKg: 1.0,
    weeklyWeightChangePercent: 0,
  ),
  running(
    key: 'running',
    color: kPhaseColorTeal,
    icon: Icons.directions_run_rounded,
    calorieFactor: 1.0,
    proteinPerKg: 1.6,
    fatPerKg: 1.0,
    weeklyWeightChangePercent: 0,
  ),
  deload(
    key: 'deload',
    color: kPhaseColorAmber,
    icon: Icons.self_improvement_rounded,
    calorieFactor: 1.0,
    proteinPerKg: 1.8,
    fatPerKg: 1.0,
    weeklyWeightChangePercent: 0,
  ),
  custom(key: 'custom', color: kPhaseColorTeal, icon: Icons.flag_rounded);

  const PhaseKind({
    required this.key,
    required this.color,
    required this.icon,
    this.calorieFactor,
    this.proteinPerKg,
    this.fatPerKg,
    this.weeklyWeightChangePercent,
  });

  final String key;
  final int color;
  final IconData icon;

  /// Daily calories as a fraction of TDEE (0.8 = 20 % deficit). Null for
  /// kinds that do not imply a nutrition strategy.
  final double? calorieFactor;
  final double? proteinPerKg;
  final double? fatPerKg;
  final double? weeklyWeightChangePercent;

  static PhaseKind fromKey(String? key) => switch (key) {
    'cutting' || 'cut' => PhaseKind.cut,
    'bulking' || 'bulk' => PhaseKind.bulk,
    'maintenance' => PhaseKind.maintenance,
    'strength' || 'base' || 'intensification' || 'peak' => PhaseKind.strength,
    'running' || 'aerobic_base' || 'build' || 'event' => PhaseKind.running,
    'deload' || 'taper' => PhaseKind.deload,
    _ => PhaseKind.custom,
  };

  String label(AppLocalizations loc) => switch (this) {
    PhaseKind.cut => loc.planningKindCut,
    PhaseKind.bulk => loc.planningKindBulk,
    PhaseKind.maintenance => loc.planningKindMaintenance,
    PhaseKind.strength => loc.planningKindStrength,
    PhaseKind.running => loc.planningKindRunning,
    PhaseKind.deload => loc.planningKindDeload,
    PhaseKind.custom => loc.planningKindCustom,
  };

  String description(AppLocalizations loc) => switch (this) {
    PhaseKind.cut => loc.planningKindCutHint,
    PhaseKind.bulk => loc.planningKindBulkHint,
    PhaseKind.maintenance => loc.planningKindMaintenanceHint,
    PhaseKind.strength => loc.planningKindStrengthHint,
    PhaseKind.running => loc.planningKindRunningHint,
    PhaseKind.deload => loc.planningKindDeloadHint,
    PhaseKind.custom => loc.planningKindCustomHint,
  };
}

/// One phase of a [PlanBlueprint]: a kind and a length in weeks.
class PlanBlueprintPhase {
  final PhaseKind kind;
  final int weeks;

  /// Optional name override; defaults to the kind label.
  final String Function(AppLocalizations loc)? name;

  const PlanBlueprintPhase(this.kind, this.weeks, {this.name});

  String nameFor(AppLocalizations loc) => name?.call(loc) ?? kind.label(loc);
}

/// Ready-made plan shapes offered when creating a plan.
enum PlanBlueprint {
  recomposition(Icons.swap_vert_rounded),
  strength(Icons.fitness_center_rounded),
  running(Icons.directions_run_rounded),
  blank(Icons.add_rounded);

  const PlanBlueprint(this.icon);

  final IconData icon;

  String label(AppLocalizations loc) => switch (this) {
    PlanBlueprint.recomposition => loc.planningBlueprintRecomposition,
    PlanBlueprint.strength => loc.planningBlueprintStrength,
    PlanBlueprint.running => loc.planningBlueprintRunning,
    PlanBlueprint.blank => loc.planningBlueprintBlank,
  };

  List<PlanBlueprintPhase> get phases => switch (this) {
    PlanBlueprint.recomposition => const [
      PlanBlueprintPhase(PhaseKind.cut, 12),
      PlanBlueprintPhase(PhaseKind.maintenance, 2),
      PlanBlueprintPhase(PhaseKind.bulk, 16),
    ],
    PlanBlueprint.strength => [
      PlanBlueprintPhase(
        PhaseKind.strength,
        6,
        name: (loc) => loc.planningPhaseNameAccumulation,
      ),
      PlanBlueprintPhase(
        PhaseKind.strength,
        4,
        name: (loc) => loc.planningPhaseNameIntensification,
      ),
      const PlanBlueprintPhase(PhaseKind.deload, 1),
      PlanBlueprintPhase(
        PhaseKind.strength,
        2,
        name: (loc) => loc.planningPhaseNamePeak,
      ),
    ],
    PlanBlueprint.running => [
      PlanBlueprintPhase(
        PhaseKind.running,
        8,
        name: (loc) => loc.planningPhaseNameBase,
      ),
      PlanBlueprintPhase(
        PhaseKind.running,
        6,
        name: (loc) => loc.planningPhaseNameBuild,
      ),
      PlanBlueprintPhase(
        PhaseKind.deload,
        2,
        name: (loc) => loc.planningPhaseNameTaper,
      ),
    ],
    PlanBlueprint.blank => const [PlanBlueprintPhase(PhaseKind.maintenance, 4)],
  };

  String summary(AppLocalizations loc) =>
      phases.map((phase) => phase.nameFor(loc)).join(' → ');
}
