import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_goal_input.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Edits the goal of the run about to start: a distance or time target (a
/// preset or any custom value) and an optional pace goal with tolerance.
/// Returns the new goal, or null when dismissed.
Future<RunSessionGoal?> showRunGoalSheet(
  BuildContext context, {
  required RunSessionGoal goal,
}) {
  return showModalBottomSheet<RunSessionGoal>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _GoalSheet(goal: goal),
  );
}

enum _GoalKind { none, distance, time }

class _GoalSheet extends StatefulWidget {
  final RunSessionGoal goal;

  const _GoalSheet({required this.goal});

  @override
  State<_GoalSheet> createState() => _GoalSheetState();
}

class _GoalSheetState extends State<_GoalSheet> {
  static const _distancePresets = [1000, 2000, 3000, 5000, 10000, 21097];
  static const _timePresets = [600, 900, 1200, 1800, 2700, 3600];
  static const _tolerances = [3, 5, 10];

  late _GoalKind _kind;
  late int _distanceMeters;
  late int _timeSeconds;
  late bool _paceOn;
  late int _tolerance;
  final _customController = TextEditingController();
  late final TextEditingController _paceController;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final goal = widget.goal;
    _kind = !goal.enabled
        ? _GoalKind.none
        : goal.metric == RunIntervalMetric.time
        ? _GoalKind.time
        : _GoalKind.distance;
    _distanceMeters =
        goal.metric == RunIntervalMetric.distance && goal.value > 0
        ? goal.value
        : 5000;
    _timeSeconds = goal.metric == RunIntervalMetric.time && goal.value > 0
        ? goal.value
        : 1800;
    _paceOn = goal.hasPaceGoal;
    _tolerance = _tolerances.contains(goal.paceTolerancePercent)
        ? goal.paceTolerancePercent
        : 5;
    _paceController = TextEditingController(
      text: goal.hasPaceGoal
          ? RunGoalInput.paceText(goal.paceTargetSecPerKm!)
          : '',
    );
    // A value that is not one of the presets starts in the custom field.
    if (_kind == _GoalKind.distance &&
        !_distancePresets.contains(_distanceMeters)) {
      _customController.text = RunFormatters.decimal(_distanceMeters / 1000, 2);
    } else if (_kind == _GoalKind.time &&
        !_timePresets.contains(_timeSeconds)) {
      _customController.text = RunFormatters.decimal(_timeSeconds / 60, 1);
    }
  }

  @override
  void dispose() {
    _customController.dispose();
    _paceController.dispose();
    super.dispose();
  }

  int? get _customValue => switch (_kind) {
    _GoalKind.distance => RunGoalInput.distanceMeters(_customController.text),
    _GoalKind.time => RunGoalInput.timeSeconds(_customController.text),
    _GoalKind.none => null,
  };

  bool get _usingCustom => _customController.text.trim().isNotEmpty;

  int? get _effectiveValue => _usingCustom
      ? _customValue
      : (_kind == _GoalKind.distance ? _distanceMeters : _timeSeconds);

  int? get _paceValue => RunGoalInput.paceSecPerKm(_paceController.text);

  void _save() {
    setState(() => _submitted = true);
    var goal = const RunSessionGoal.defaults();
    if (_kind != _GoalKind.none) {
      final value = _effectiveValue;
      if (value == null) return;
      goal = goal.copyWith(
        enabled: true,
        metric: _kind == _GoalKind.time
            ? RunIntervalMetric.time
            : RunIntervalMetric.distance,
        value: value,
      );
    }
    if (_paceOn) {
      final pace = _paceValue;
      if (pace == null) return;
      goal = goal.copyWith(
        paceTargetSecPerKm: pace,
        paceTolerancePercent: _tolerance,
      );
    }
    Navigator.pop(context, goal);
  }

  String _distanceLabel(int meters) =>
      '${RunFormatters.decimal(meters / 1000, meters % 1000 == 0 ? 0 : 1)} km';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final presets = _kind == _GoalKind.distance
        ? _distancePresets
        : _timePresets;
    final customError = _usingCustom && _customValue == null
        ? loc.runRecordGoalInvalid
        : null;
    final paceError =
        _paceOn &&
            (_submitted || _paceController.text.isNotEmpty) &&
            _paceValue == null
        ? loc.runRecordGoalPaceInvalid
        : null;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                loc.runRecordGoalPickTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              AppSegmentedTabs<_GoalKind>(
                values: _GoalKind.values,
                selected: _kind,
                labelOf: (kind) => switch (kind) {
                  _GoalKind.none => loc.runRecordGoalNone,
                  _GoalKind.distance => loc.runIntervalMetricDistance,
                  _GoalKind.time => loc.runIntervalMetricTime,
                },
                onChanged: (kind) => setState(() {
                  _kind = kind;
                  _customController.clear();
                }),
              ),
              if (_kind != _GoalKind.none) ...[
                AppSectionHeader(
                  loc.runRecordGoalPresets,
                  padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final value in presets)
                      ChoiceChip(
                        label: Text(
                          _kind == _GoalKind.distance
                              ? _distanceLabel(value)
                              : RunFormatters.durationHoursMinutes(value),
                        ),
                        selected:
                            !_usingCustom &&
                            value ==
                                (_kind == _GoalKind.distance
                                    ? _distanceMeters
                                    : _timeSeconds),
                        onSelected: (_) => setState(() {
                          _customController.clear();
                          if (_kind == _GoalKind.distance) {
                            _distanceMeters = value;
                          } else {
                            _timeSeconds = value;
                          }
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _customController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,:]')),
                  ],
                  decoration: InputDecoration(
                    labelText: _kind == _GoalKind.distance
                        ? loc.runRecordGoalCustomDistance
                        : loc.runRecordGoalCustomTime,
                    errorText: customError,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
              AppSectionHeader(
                loc.runRecordGoalPace,
                padding: const EdgeInsets.fromLTRB(4, 20, 0, 0),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(loc.runRecordGoalPaceSubtitle),
                value: _paceOn,
                onChanged: (value) => setState(() => _paceOn = value),
              ),
              if (_paceOn) ...[
                TextField(
                  controller: _paceController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9:]')),
                  ],
                  decoration: InputDecoration(
                    labelText: loc.runRecordGoalPaceTarget,
                    hintText: '5:30',
                    errorText: paceError,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  loc.runRecordGoalPaceTolerance,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final tolerance in _tolerances)
                      ChoiceChip(
                        label: Text(loc.runRecordGoalToleranceValue(tolerance)),
                        selected: _tolerance == tolerance,
                        onSelected: (_) =>
                            setState(() => _tolerance = tolerance),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: TextButton(
                      onPressed: () => Navigator.pop(
                        context,
                        const RunSessionGoal.defaults(),
                      ),
                      child: Text(
                        loc.runRecordGoalClearAll,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(onPressed: _save, child: Text(loc.commonSave)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
