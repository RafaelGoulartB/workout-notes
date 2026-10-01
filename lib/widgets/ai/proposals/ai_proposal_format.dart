import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Reads a JSON-ish value as a map / list / number without throwing: previews
/// come from storage and may be written by another version of the app.
Map<String, dynamic> jsonMap(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : const {};

List<Map<String, dynamic>> jsonMaps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) item.cast<String, dynamic>(),
      ]
    : const [];

num? jsonNum(Object? value) => value is num ? value : null;

String? jsonText(Object? value) =>
    value is String && value.trim().isNotEmpty ? value : null;

bool jsonTrue(Object? value) => value == true;

/// Locale-aware formatting of the numbers, units and dates a proposal card
/// shows (`pt_BR` for Portuguese).
class AiProposalFormat {
  final AppLocalizations l10n;

  const AiProposalFormat(this.l10n);

  String get locale =>
      l10n.localeName.startsWith('pt') ? 'pt_BR' : l10n.localeName;

  /// `1.234,5` / `1,234.5`, at most [maxFraction] decimals, no trailing zeros.
  String number(num? value, {int maxFraction = 1}) {
    if (value == null) return '—';
    final fraction = maxFraction <= 0 ? '' : '.${'#' * maxFraction}';
    return NumberFormat('#,##0$fraction', locale).format(value);
  }

  String withUnit(num? value, String unit, {int maxFraction = 1}) =>
      value == null ? '—' : '${number(value, maxFraction: maxFraction)} $unit';

  String kcal(num? value) => withUnit(value, 'kcal', maxFraction: 0);

  String grams(num? value) => withUnit(value, 'g');

  /// `yyyy-MM-dd` as `Wed, Sep 30, 2026` / `qua., 30 de set. de 2026`.
  String date(String? key) {
    final parsed = key == null ? null : DateTime.tryParse(key);
    if (parsed == null) return key ?? '—';
    return DateFormat.yMMMEd(locale).format(parsed);
  }

  /// Weekday name for an ISO weekday (1 = Monday … 7 = Sunday).
  String weekday(int? isoWeekday) {
    if (isoWeekday == null || isoWeekday < 1 || isoWeekday > 7) return '—';
    // 2024-01-01 was a Monday.
    return DateFormat.EEEE(locale).format(DateTime(2024, 1, isoWeekday));
  }

  /// `1:30` below an hour, `1h05` from then on.
  String seconds(int? value) {
    if (value == null) return '—';
    if (value >= 3600) return DurationFormat.elapsed(value);
    return DurationFormat.minSecOrSeconds(value);
  }

  String km(num? value) => withUnit(value, 'km', maxFraction: 2);

  String kmFromMeters(num? meters) => meters == null ? '—' : km(meters / 1000);

  /// Library name of an exercise preview (`{name, locale_key}`).
  String exerciseName(Map<String, dynamic> exercise) =>
      ExerciseLocaleHelper.exerciseName(l10n, {
        'locale_key': exercise['locale_key'],
        'name': exercise['name'],
      });

  /// Localized label of a diary meal key.
  String mealLabel(String? key, String? customName) {
    if (customName != null && customName.trim().isNotEmpty) return customName;
    return switch (key) {
      'breakfast' => l10n.nutritionMealBreakfast,
      'lunch' => l10n.nutritionMealLunch,
      'dinner' => l10n.nutritionMealDinner,
      'snacks' => l10n.nutritionMealSnacks,
      _ => key ?? '—',
    };
  }

  String measureLabel(String type) => switch (type) {
    'weight' => l10n.bodyTrackerWeight,
    'bodyFat' => l10n.bodyTrackerBodyFat,
    'waist' => l10n.bodyTrackerWaist,
    'chest' => l10n.bodyTrackerChest,
    'arm' => l10n.bodyTrackerArm,
    'forearm' => l10n.bodyTrackerForearm,
    'neck' => l10n.bodyTrackerNeck,
    'thigh' => l10n.bodyTrackerThigh,
    'calf' => l10n.bodyTrackerCalf,
    'hip' => l10n.bodyTrackerHip,
    'bloodPressure' => l10n.bodyTrackerBloodPressure,
    _ => type,
  };
}

/// Stable-code to localized-text tables for the proposal card. Codes are what
/// the database stores; text is never stored.
abstract final class AiProposalText {
  static String title(
    AppLocalizations l10n,
    String kind,
    Map<String, dynamic> preview,
  ) {
    final action = preview['action'];
    return switch (kind) {
      'routine' =>
        action == 'update'
            ? l10n.aiProposalTitleRoutineUpdate
            : l10n.aiProposalTitleRoutineCreate,
      'manual_food' => l10n.aiProposalTitleManualFood,
      'meal_log' => l10n.aiProposalTitleMealLog,
      'body_measurement' => l10n.aiProposalTitleBodyMeasurement,
      'goal' => switch (action) {
        'update' => l10n.aiProposalTitleGoalUpdate,
        'activate' => l10n.aiProposalTitleGoalActivate,
        'deactivate' => l10n.aiProposalTitleGoalDeactivate,
        _ => l10n.aiProposalTitleGoalCreate,
      },
      'nutrition_goal' => l10n.aiProposalTitleNutritionGoal,
      'workout_schedule' => switch (action) {
        'move' => l10n.aiProposalTitleMoveWorkout,
        'copy' => l10n.aiProposalTitleCopyWorkout,
        _ => l10n.aiProposalTitleScheduleRoutineDay,
      },
      'run_plan' =>
        action == 'scale_week'
            ? l10n.aiProposalTitleRunScale
            : l10n.aiProposalTitleRunMove,
      _ => l10n.aiProposalTitleUnknown,
    };
  }

  static IconData icon(String kind, Map<String, dynamic> preview) {
    final action = preview['action'];
    return switch (kind) {
      'routine' =>
        action == 'update'
            ? Icons.edit_note_rounded
            : Icons.playlist_add_rounded,
      'manual_food' => Icons.restaurant_menu_rounded,
      'meal_log' => Icons.lunch_dining_rounded,
      'body_measurement' => Icons.monitor_weight_outlined,
      'goal' => Icons.flag_rounded,
      'nutrition_goal' => Icons.local_fire_department_rounded,
      'workout_schedule' => Icons.event_available_rounded,
      'run_plan' => Icons.directions_run_rounded,
      _ => Icons.auto_awesome_rounded,
    };
  }

  static String status(AppLocalizations l10n, AiProposalStatus status) =>
      switch (status) {
        AiProposalStatus.awaiting => l10n.aiProposalStatusAwaiting,
        AiProposalStatus.applied => l10n.aiProposalStatusApplied,
        AiProposalStatus.rejected => l10n.aiProposalStatusRejected,
        AiProposalStatus.stale => l10n.aiProposalStatusStale,
        AiProposalStatus.failed => l10n.aiProposalStatusFailed,
        AiProposalStatus.expired => l10n.aiProposalStatusExpired,
      };

  /// Localized reason of a stale/failed proposal from its stable error code.
  static String error(AppLocalizations l10n, String? code) => switch (code) {
    'stale_revision' => l10n.aiProposalErrorStaleRevision,
    'stale_target_missing' => l10n.aiProposalErrorTargetMissing,
    'stale_week_started' => l10n.aiProposalErrorWeekStarted,
    'stale_date_passed' => l10n.aiProposalErrorDatePassed,
    'exercise_missing' => l10n.aiProposalErrorExerciseMissing,
    'food_missing' => l10n.aiProposalErrorFoodMissing,
    'saved_meal_missing' => l10n.aiProposalErrorSavedMealMissing,
    'expired' => l10n.aiProposalHintExpired,
    _ => l10n.aiProposalErrorFailed,
  };

  /// Localized sentence for a preview warning (`{code, ...params}`), or null
  /// for a code this version does not know.
  static String? warning(
    AppLocalizations l10n,
    AiProposalFormat fmt,
    Map<String, dynamic> warning,
  ) {
    String name() => (warning['name'] as String?) ?? '';
    String measure() {
      final type = warning['type'] as String?;
      return type == null ? '' : fmt.measureLabel(type);
    }

    return switch (warning['code']) {
      'routine_name_exists' => l10n.aiProposalWarnRoutineNameExists,
      'similar_food_exists' => l10n.aiProposalWarnSimilarFood(name()),
      'already_logged' => l10n.aiProposalWarnAlreadyLogged(measure()),
      'large_change' => l10n.aiProposalWarnLargeChange(
        measure(),
        (warning['percent'] as num?)?.toInt() ?? 0,
      ),
      'large_portion' => l10n.aiProposalWarnLargePortion(
        name(),
        (warning['calories'] as num?)?.toInt() ?? 0,
      ),
      'saved_meal_items_unavailable' => l10n.aiProposalWarnSavedMealItems(
        (warning['count'] as num?)?.toInt() ?? 0,
        name(),
      ),
      'already_in_meal' => l10n.aiProposalWarnAlreadyInMeal(name()),
      'similar_goal_exists' => l10n.aiProposalWarnSimilarGoal,
      'plan_overrides_goal' => l10n.aiProposalWarnPlanOverrides(
        (warning['phase'] as String?) ?? '',
      ),
      'tdee_reset' => l10n.aiProposalWarnTdeeReset,
      'macros_do_not_match_calories' => l10n.aiProposalWarnMacrosMismatch(
        (warning['macro_calories'] as num?)?.toInt() ?? 0,
        (warning['calories'] as num?)?.toInt() ?? 0,
      ),
      'rest_day_unchanged' => l10n.aiProposalWarnRestDay,
      'date_has_workouts' => l10n.aiProposalWarnDateHasWorkouts(
        (warning['count'] as num?)?.toInt() ?? 0,
      ),
      'run_same_day' => l10n.aiProposalWarnRunSameDay(
        (warning['other'] as String?) ?? '',
      ),
      'run_hard_back_to_back' => l10n.aiProposalWarnRunBackToBack(
        (warning['other'] as String?) ?? '',
      ),
      'run_better_day' => l10n.aiProposalWarnRunBetterDay(
        fmt.weekday((warning['day_of_week'] as num?)?.toInt()),
      ),
      _ => null,
    };
  }
}

/// Small section label used inside the proposal bodies.
class AiProposalSectionLabel extends StatelessWidget {
  final String text;

  const AiProposalSectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// `Label ........ value` row used by the compact summaries.
class AiProposalValueRow extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasized;

  const AiProposalValueRow({
    super.key,
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasized
        ? theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodySmall;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: style)),
          const SizedBox(width: 8),
          Flexible(
            child: Text(value, style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// A coloured `before → after` change line.
class AiProposalChangeLine extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final String text;
  final String? caption;
  final bool strike;

  const AiProposalChangeLine({
    super.key,
    required this.icon,
    required this.text,
    this.color,
    this.caption,
    this.strike = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 15, color: tint),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: text,
                    style: theme.textTheme.bodySmall?.copyWith(
                      decoration: strike ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  if (caption != null)
                    TextSpan(
                      text: '  $caption',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wrap of metric chips for macros (kcal, protein, carbs, fat).
class AiProposalMacroChips extends StatelessWidget {
  final Map<String, dynamic> values;
  final bool compact;

  const AiProposalMacroChips({
    super.key,
    required this.values,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final fmt = AiProposalFormat(l10n);
    String? chip(String label, String key, String unit, {int fraction = 1}) {
      final value = jsonNum(values[key]);
      return value == null
          ? null
          : '$label ${fmt.withUnit(value, unit, maxFraction: fraction)}';
    }

    final texts = [
      chip(l10n.nutritionProgressCalories, 'calories', 'kcal', fraction: 0),
      chip(l10n.nutritionProgressProtein, 'protein_g', 'g'),
      chip(l10n.nutritionProgressCarbs, 'carbs_g', 'g'),
      chip(l10n.nutritionProgressFat, 'fat_g', 'g'),
    ].whereType<String>().toList();
    if (texts.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [for (final text in texts) AppMetricChip(text: text)],
    );
  }
}
