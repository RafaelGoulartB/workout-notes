import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_revision.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// `propose_nutrition_goal`: change the daily calorie and macro targets.
///
/// An active periodization plan overrides the settings goal field by field
/// (`EffectiveNutritionGoalService`), so the proposal says which goal it
/// changes: the settings goal, or the targets of the active phase from the
/// current week on. Weeks already lived are never rewritten, and a proposal
/// prepared in one week is stale once the next one starts.
class NutritionGoalProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;
  final DateTime Function() _now;

  NutritionGoalProposalHandler({DatabaseHelper? db, DateTime Function()? now})
    : _db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  @override
  String get kind => 'nutrition_goal';

  @override
  String get toolName => 'propose_nutrition_goal';

  @override
  AiToolDomain get domain => AiToolDomain.nutrition;

  static const _fields = ['calories', 'protein_g', 'carbs_g', 'fat_g'];
  static const _scopes = ['settings', 'active_phase'];

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Change the daily nutrition goal; send only fields to change. A running plan phase overrides the settings goal: then use scope active_phase (applies from this week on; lived weeks stay).',
    properties: {
      'calories': AiSchema.number('kcal', _min['calories'], _max['calories']),
      'protein_g': AiSchema.number('g', _min['protein_g'], _max['protein_g']),
      'carbs_g': AiSchema.number('g', _min['carbs_g'], _max['carbs_g']),
      'fat_g': AiSchema.number('g', _min['fat_g'], _max['fat_g']),
      'scope': AiSchema.enumOf(_scopes),
    },
  );

  static const _min = {
    'calories': 500.0,
    'protein_g': 10.0,
    'carbs_g': 10.0,
    'fat_g': 5.0,
  };
  static const _max = {
    'calories': 10000.0,
    'protein_g': 600.0,
    'carbs_g': 1500.0,
    'fat_g': 600.0,
  };

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({..._fields, 'scope'});
    final values = <String, double>{};
    for (final field in _fields) {
      final value = args.optionalNumber(
        field,
        min: _min[field],
        max: _max[field],
        // 0 is the placeholder for a macro the user did not mention.
        zeroIsAbsent: true,
      );
      if (value != null) values[field] = value;
    }
    if (values.isEmpty) {
      throw const AiProposalException(
        'invalid_args',
        'Send at least one of calories, protein_g, carbs_g or fat_g.',
        param: 'calories',
        hint: 'Include the nutrient(s) the goal should change.',
      );
    }
    var scope = args.optionalEnum('scope', _scopes);
    final today = dayOf(_now());
    final periodization = _db.periodizationRepo;
    final phase = await periodization.getEffectivePhase(today);
    scope ??= phase == null ? 'settings' : 'active_phase';
    final nutrition = _db.nutritionRepo;

    if (scope == 'settings') {
      final current = await nutrition.getActiveGoalIn(db);
      final before = _goalValues(current);
      final after = {...before, ...values};
      final warnings = <Map<String, dynamic>>[
        ..._consistency(after),
        if (current != null &&
            (current.tdee != null || current.adjustmentKind != null))
          {'code': 'tdee_reset'},
      ];
      if (phase != null) {
        final target = await periodization.getEffectiveTarget(
          phase.id,
          date: today,
        );
        final overridden = [
          for (final field in values.keys)
            if (target != null && _targetValue(target, field) != null) field,
        ];
        if (overridden.isNotEmpty) {
          warnings.add({
            'code': 'plan_overrides_goal',
            'phase': phase.name,
            'fields': overridden,
          });
        }
      }
      if (_same(before, after)) {
        throw const AiProposalException(
          'no_changes',
          'The goal already has these values.',
          hint: 'Tell the user nothing needs to change.',
        );
      }
      return AiProposalDraft(
        payload: {'scope': 'settings', 'values': values},
        preview: {
          'v': kAiProposalPreviewVersion,
          'scope': 'settings',
          'before': before,
          'after': after,
          'warnings': warnings,
        },
        base: {'goal': before, 'goal_id': current?.id},
        baseHash: aiRevision({'id': current?.id, 'goal': before}),
        summary: {'scope': 'settings', 'after': after},
      );
    }

    if (phase == null) {
      throw const AiProposalException(
        'no_active_phase',
        'There is no active periodization phase today.',
        param: 'scope',
        hint: 'Use scope "settings", or omit scope.',
      );
    }
    final fromWeek = (phase.weekAt(today) - 1).clamp(0, phase.totalWeeks - 1);
    final weekly = await periodization.getWeeklyTargets(phase);
    final currentTarget = weekly[fromWeek];
    final before = {
      'calories': currentTarget?.calories,
      'protein_g': currentTarget?.proteinG,
      'carbs_g': currentTarget?.carbsG,
      'fat_g': currentTarget?.fatG,
    };
    final after = {...before, ...values};
    if (_same(before, after) && !_laterWeeksDiffer(weekly, fromWeek, values)) {
      throw const AiProposalException(
        'no_changes',
        'The phase already has these targets.',
        hint: 'Tell the user nothing needs to change.',
      );
    }
    final warnings = <Map<String, dynamic>>[
      ..._consistency(after),
      if (currentTarget != null && currentTarget.hasRestDayNutrition)
        {'code': 'rest_day_unchanged'},
    ];
    return AiProposalDraft(
      payload: {
        'scope': 'active_phase',
        'phase_id': phase.id,
        'from_week': fromWeek,
        'values': values,
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'scope': 'active_phase',
        'before': before,
        'after': after,
        'phase': {
          'name': phase.name,
          'from_week': fromWeek + 1,
          'total_weeks': phase.totalWeeks,
          'weeks_changed': phase.totalWeeks - fromWeek,
          'end_date': dateKey(phase.endDate),
        },
        'warnings': warnings,
      },
      base: {'phase_id': phase.id, 'from_week': fromWeek},
      baseHash: _phaseHash(phase, weekly, fromWeek),
      subjectId: phase.id,
      summary: {
        'scope': 'active_phase',
        'phase': phase.name,
        'from_week': fromWeek + 1,
        'weeks_changed': phase.totalWeeks - fromWeek,
        'after': after,
      },
    );
  }

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final payload = proposal.payload;
    if (payload['scope'] == 'settings') {
      final current = await _db.nutritionRepo.getActiveGoalIn(txn);
      final hash = aiRevision({
        'id': current?.id,
        'goal': _goalValues(current),
      });
      return hash == proposal.baseHash ? null : 'stale_revision';
    }
    final phase = await _db.periodizationRepo.getPhaseIn(
      txn,
      payload['phase_id'] as String? ?? '',
    );
    if (phase == null) return 'stale_target_missing';
    final fromWeek = (payload['from_week'] as num?)?.toInt() ?? 0;
    final todayWeek = (phase.weekAt(dayOf(_now())) - 1).clamp(
      0,
      phase.totalWeeks - 1,
    );
    // A new week started since the preview: applying it would rewrite a week
    // that is now (partly) lived.
    if (todayWeek > fromWeek) return 'stale_week_started';
    final weekly = await _db.periodizationRepo.getWeeklyTargetsIn(txn, phase);
    return _phaseHash(phase, weekly, fromWeek) == proposal.baseHash
        ? null
        : 'stale_revision';
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final values = (payload['values'] as Map? ?? const {})
        .cast<String, dynamic>();
    double? value(String key) => (values[key] as num?)?.toDouble();
    if (payload['scope'] == 'settings') {
      final current = await _db.nutritionRepo.getActiveGoalIn(txn);
      final merged = {..._goalValues(current), ...values};
      double? m(String key) => (merged[key] as num?)?.toDouble();
      final goal = await _db.nutritionRepo.saveGoalIn(
        txn,
        id: proposal.id,
        calories: m('calories'),
        proteinG: m('protein_g'),
        carbsG: m('carbs_g'),
        fatG: m('fat_g'),
      );
      return {'scope': 'settings', 'goal_id': goal.id};
    }
    final phase = await _db.periodizationRepo.getPhaseIn(
      txn,
      payload['phase_id'] as String? ?? '',
    );
    if (phase == null) {
      throw const AiProposalException.stale(
        'stale_target_missing',
        'The phase no longer exists.',
      );
    }
    final weeks = await _db.periodizationRepo.applyNutritionFromWeekIn(
      txn,
      phase,
      fromWeek: (payload['from_week'] as num).toInt(),
      calories: value('calories'),
      proteinG: value('protein_g'),
      carbsG: value('carbs_g'),
      fatG: value('fat_g'),
    );
    return {'scope': 'active_phase', 'phase': phase.name, 'weeks': weeks};
  }

  // ---------------------------------------------------------------- helpers

  Map<String, double?> _goalValues(NutritionGoal? goal) => {
    'calories': goal?.calories,
    'protein_g': goal?.proteinG,
    'carbs_g': goal?.carbsG,
    'fat_g': goal?.fatG,
  };

  double? _targetValue(PeriodizationTarget target, String field) =>
      switch (field) {
        'calories' => target.calories,
        'protein_g' => target.proteinG,
        'carbs_g' => target.carbsG,
        _ => target.fatG,
      };

  bool _same(Map<String, double?> a, Map<String, double?> b) =>
      _fields.every((f) => a[f] == b[f]);

  bool _laterWeeksDiffer(
    List<PeriodizationTarget?> weekly,
    int fromWeek,
    Map<String, double> values,
  ) {
    for (var week = fromWeek; week < weekly.length; week++) {
      final target = weekly[week];
      for (final entry in values.entries) {
        if (target == null || _targetValue(target, entry.key) != entry.value) {
          return true;
        }
      }
    }
    return false;
  }

  String _phaseHash(
    PeriodizationPhase phase,
    List<PeriodizationTarget?> weekly,
    int fromWeek,
  ) => aiRevision({
    'phase': phase.id,
    'from': fromWeek,
    'weeks': [
      for (var week = fromWeek; week < weekly.length; week++)
        weekly[week]?.nutritionJson,
    ],
  });

  /// Macros that do not add up to the calories (4/4/9 kcal per gram) are worth
  /// a note: the numbers are the user's to keep, but they should see it.
  List<Map<String, dynamic>> _consistency(Map<String, double?> goal) {
    final calories = goal['calories'];
    final protein = goal['protein_g'];
    final carbs = goal['carbs_g'];
    final fat = goal['fat_g'];
    if (calories == null || protein == null || carbs == null || fat == null) {
      return const [];
    }
    final fromMacros = protein * 4 + carbs * 4 + fat * 9;
    if (calories <= 0 || (fromMacros - calories).abs() / calories <= 0.15) {
      return const [];
    }
    return [
      {
        'code': 'macros_do_not_match_calories',
        'macro_calories': fromMacros.round(),
        'calories': calories.round(),
      },
    ];
  }
}
