import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_schema.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/ai_revision.dart';

/// `propose_goal`: create, retarget, pause or resume a training goal.
///
/// Targets are given in the units the goal screens show: kg lifted for
/// volume, days for days, km for distance and **minutes** for time (stored in
/// seconds, the unit goal progress is measured in). Scope and metric of an
/// existing goal cannot change: it would silently reinterpret its history, so
/// the model is told to create a new goal instead.
class GoalProposalHandler extends AiProposalHandler {
  final DatabaseHelper _db;

  GoalProposalHandler({DatabaseHelper? db})
    : _db = db ?? DatabaseHelper.instance;

  @override
  String get kind => 'goal';

  @override
  String get toolName => 'propose_goal';

  @override
  AiToolDomain get domain => AiToolDomain.goals;

  static const _actions = ['create', 'update', 'activate', 'deactivate'];

  @override
  AiToolSpec get spec => AiToolSpec(
    name: toolName,
    proposal: true,
    domain: domain,
    description:
        'Create or change a weekly/monthly goal, or pause/resume one (goal_id from list_goals). Strength (anaerobic): volume or days. Cardio (aerobic): distance, time or days. Scope and metric cannot change after creation.',
    properties: {
      'action': AiSchema.enumOf(_actions),
      'goal_id': AiSchema.str('Not for create.'),
      'scope': AiSchema.enumOf(['anaerobic', 'aerobic'], 'Create only.'),
      'metric': AiSchema.enumOf([
        'volume',
        'days',
        'distance',
        'time',
      ], 'Create only.'),
      'period': AiSchema.enumOf(['weekly', 'monthly']),
      'target_value': AiSchema.number('Per period: kg, km, minutes or days.'),
      'title': AiSchema.str(),
    },
    required: ['action'],
  );

  static const _maxTitle = 60;

  @override
  Future<AiProposalDraft> prepare(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    args.allowOnly({
      'action',
      'goal_id',
      'scope',
      'metric',
      'period',
      'target_value',
      'title',
    });
    final action = args.requiredEnum('action', _actions);
    final goalId = args.optionalString('goal_id', maxLength: 80);
    final repo = _db.goalRepo;

    if (action == 'create') {
      if (goalId != null) {
        throw const AiProposalException(
          'invalid_args',
          '"goal_id" is not allowed when creating a goal.',
          param: 'goal_id',
          hint: 'Remove goal_id, or use action "update".',
        );
      }
      return _create(db, args);
    }
    if (goalId == null) {
      throw AiProposalException(
        'invalid_args',
        '"goal_id" is required to $action a goal.',
        param: 'goal_id',
        expected: 'goal id from list_goals',
        hint: 'Call list_goals and pass the id of the goal.',
      );
    }
    final goal = await repo.getByIdIn(db, goalId);
    if (goal == null) {
      throw const AiProposalException(
        'not_found',
        'Goal not found.',
        param: 'goal_id',
        hint: 'Call list_goals to get valid goal ids.',
      );
    }
    if (action == 'activate' || action == 'deactivate') {
      // Fields that do not apply (often placeholders) are ignored.
      final wanted = action == 'activate';
      if (goal.isActive == wanted) {
        throw AiProposalException(
          'no_changes',
          'The goal is already ${wanted ? 'active' : 'paused'}.',
          hint: 'Tell the user nothing needs to change.',
        );
      }
      return AiProposalDraft(
        payload: {'action': action, 'goal_id': goalId, 'active': wanted},
        preview: {
          'v': kAiProposalPreviewVersion,
          'action': action,
          'goal': _view(goal),
          'warnings': const <Map<String, dynamic>>[],
        },
        base: goal.toMap(),
        baseHash: aiRevision(goal.toMap()),
        subjectId: goalId,
        summary: {
          'action': action,
          'goal': goal.title.isEmpty ? goal.metric.value : goal.title,
        },
      );
    }

    // update
    final sameScope =
        !args.has('scope') ||
        args.optionalEnum('scope', ['anaerobic', 'aerobic']) ==
            goal.scope.value;
    final sameMetric =
        !args.has('metric') ||
        args.optionalEnum('metric', ['volume', 'days', 'distance', 'time']) ==
            goal.metric.value;
    if (!sameScope || !sameMetric) {
      throw const AiProposalException(
        'invalid_args',
        'Scope and metric of an existing goal cannot be changed.',
        param: 'metric',
        hint:
            'Create a new goal with the new scope/metric (and pause this one if the user wants).',
      );
    }
    final title = args.optionalString('title', maxLength: _maxTitle);
    final periodArg = args.optionalEnum('period', ['weekly', 'monthly']);
    final newPeriod = periodArg == null
        ? goal.period
        : GoalPeriod.fromString(periodArg);
    final (min, max) = _bounds(goal.metric, newPeriod);
    final target = args.optionalNumber(
      'target_value',
      min: min,
      max: max,
      zeroIsAbsent: true,
    );
    _checkWhole(goal.metric, target, max);
    if (target == null && _display(goal.metric, goal.targetValue) > max) {
      throw AiProposalException(
        'invalid_args',
        'The current target does not fit a ${newPeriod.value} goal.',
        param: 'target_value',
        expected: 'between ${min.toInt()} and ${max.toInt()}',
        hint: 'Send a new "target_value" together with the new period.',
      );
    }
    final updated = goal.copyWith(
      title: title ?? goal.title,
      period: newPeriod,
      targetValue: target == null ? null : _stored(goal.metric, target),
    );
    if (updated == goal) {
      throw const AiProposalException(
        'no_changes',
        'The goal already matches this proposal.',
        hint: 'Tell the user nothing needs to change.',
      );
    }
    return AiProposalDraft(
      payload: {
        'action': 'update',
        'goal_id': goalId,
        'title': updated.title,
        'period': updated.period.value,
        'target_value': updated.targetValue,
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'action': 'update',
        'goal': _view(updated),
        'previous': _view(goal),
        'changes': {
          if (updated.title != goal.title)
            'title': {'from': goal.title, 'to': updated.title},
          if (updated.period != goal.period)
            'period': {'from': goal.period.value, 'to': updated.period.value},
          if (updated.targetValue != goal.targetValue)
            'target': {
              'from': _display(goal.metric, goal.targetValue),
              'to': _display(goal.metric, updated.targetValue),
            },
        },
        'warnings': const <Map<String, dynamic>>[],
      },
      base: goal.toMap(),
      baseHash: aiRevision(goal.toMap()),
      subjectId: goalId,
      summary: {
        'action': 'update',
        'goal': updated.title.isEmpty ? goal.metric.value : updated.title,
        'target': _display(goal.metric, updated.targetValue),
        'unit': _unit(goal.metric),
        'period': updated.period.value,
      },
    );
  }

  Future<AiProposalDraft> _create(
    DatabaseExecutor db,
    AiProposalArgs args,
  ) async {
    final scope = GoalScope.fromString(
      args.requiredEnum('scope', ['anaerobic', 'aerobic']),
    );
    final valid = GoalMetric.forScope(scope);
    final metric = GoalMetric.fromString(
      args.requiredEnum('metric', ['volume', 'days', 'distance', 'time']),
    );
    if (!valid.contains(metric)) {
      throw AiProposalException(
        'invalid_args',
        'Metric "${metric.value}" does not exist for scope "${scope.value}".',
        param: 'metric',
        expected: 'one of: ${valid.map((m) => m.value).join(', ')}',
        received: metric.value,
        hint:
            'anaerobic (strength) goals use volume or days; aerobic (cardio) goals use distance, time or days.',
      );
    }
    final period = GoalPeriod.fromString(
      args.requiredEnum('period', ['weekly', 'monthly']),
    );
    final (min, max) = _bounds(metric, period);
    final target = args.requiredNumber('target_value', min: min, max: max);
    _checkWhole(metric, target, max);
    final title = args.optionalString('title', maxLength: _maxTitle) ?? '';
    final goal = Goal(
      id: '',
      title: title,
      scope: scope,
      metric: metric,
      period: period,
      targetValue: _stored(metric, target),
      createdAt: DateTime.now(),
    );
    final existing = await _db.goalRepo.getAll(activeOnly: true);
    final warnings = <Map<String, dynamic>>[
      if (existing.any(
        (g) => g.scope == scope && g.metric == metric && g.period == period,
      ))
        {'code': 'similar_goal_exists'},
    ];
    final suggested = await _db.goalRepo.suggestTarget(scope, metric, period);
    return AiProposalDraft(
      payload: {
        'action': 'create',
        'title': title,
        'scope': scope.value,
        'metric': metric.value,
        'period': period.value,
        'target_value': goal.targetValue,
      },
      preview: {
        'v': kAiProposalPreviewVersion,
        'action': 'create',
        'goal': _view(goal),
        'suggested_target': suggested == null
            ? null
            : _display(metric, suggested),
        'warnings': warnings,
      },
      summary: {
        'action': 'create',
        'metric': metric.value,
        'period': period.value,
        'target': target,
        'unit': _unit(metric),
        'recent_average_based_suggestion': ?(suggested == null
            ? null
            : _display(metric, suggested)),
      },
    );
  }

  /// Allowed `target_value` range, in display units.
  (double, double) _bounds(GoalMetric metric, GoalPeriod period) =>
      switch (metric) {
        GoalMetric.volume => (1.0, 10000000.0),
        GoalMetric.days => (1.0, period == GoalPeriod.weekly ? 7.0 : 31.0),
        GoalMetric.distance => (0.1, 10000.0),
        GoalMetric.time => (1.0, 60000.0),
      };

  void _checkWhole(GoalMetric metric, double? value, double max) {
    if (value != null &&
        metric == GoalMetric.days &&
        value != value.roundToDouble()) {
      throw AiProposalException(
        'invalid_args',
        'A days goal needs a whole number of days.',
        param: 'target_value',
        received: value,
        hint: 'Use a whole number between 1 and ${max.toInt()}.',
      );
    }
  }

  static double _stored(GoalMetric metric, double display) =>
      metric == GoalMetric.time ? display * 60 : display;

  static double _display(GoalMetric metric, double stored) =>
      metric == GoalMetric.time ? stored / 60 : stored;

  static String _unit(GoalMetric metric) => switch (metric) {
    GoalMetric.volume => 'kg',
    GoalMetric.days => 'days',
    GoalMetric.distance => 'km',
    GoalMetric.time => 'min',
  };

  Map<String, dynamic> _view(Goal goal) => {
    'title': goal.title,
    'scope': goal.scope.value,
    'metric': goal.metric.value,
    'period': goal.period.value,
    'target': _display(goal.metric, goal.targetValue),
    'unit': _unit(goal.metric),
    'active': goal.isActive,
  };

  @override
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async {
    final id = proposal.payload['goal_id'] as String?;
    if (proposal.payload['action'] == 'create') return null;
    if (id == null) return 'stale_target_missing';
    final goal = await _db.goalRepo.getByIdIn(txn, id);
    if (goal == null) return 'stale_target_missing';
    if (proposal.baseHash != null &&
        aiRevision(goal.toMap()) != proposal.baseHash) {
      return 'stale_revision';
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) async {
    final payload = proposal.payload;
    final action = payload['action'];
    final repo = _db.goalRepo;
    switch (action) {
      case 'create':
        final goal = Goal(
          id: proposal.id,
          title: (payload['title'] as String?) ?? '',
          scope: GoalScope.fromString(payload['scope'] as String? ?? ''),
          metric: GoalMetric.fromString(payload['metric'] as String? ?? ''),
          period: GoalPeriod.fromString(payload['period'] as String? ?? ''),
          targetValue: (payload['target_value'] as num).toDouble(),
          createdAt: DateTime.now(),
        );
        await repo.insertIn(txn, goal);
        return {'goal_id': goal.id, 'action': 'create'};
      case 'update':
        final id = payload['goal_id'] as String;
        final goal = await repo.getByIdIn(txn, id);
        if (goal == null) {
          throw const AiProposalException.stale(
            'stale_target_missing',
            'The goal no longer exists.',
          );
        }
        await repo.updateIn(
          txn,
          goal.copyWith(
            title: payload['title'] as String?,
            period: GoalPeriod.fromString(payload['period'] as String? ?? ''),
            targetValue: (payload['target_value'] as num).toDouble(),
          ),
        );
        return {'goal_id': id, 'action': 'update'};
      case 'activate' || 'deactivate':
        final id = payload['goal_id'] as String;
        await repo.toggleActiveIn(txn, id, payload['active'] == true);
        return {'goal_id': id, 'action': action};
    }
    throw const AiProposalException(
      'invalid_payload',
      'The stored proposal is not a valid goal change.',
    );
  }
}
