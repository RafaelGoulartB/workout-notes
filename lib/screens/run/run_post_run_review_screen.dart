import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_completion_policy.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';
import 'package:workout_notes/widgets/run/run_splits_list.dart';

class RunPostRunReviewScreen extends StatefulWidget {
  final RunReviewDraft draft;

  const RunPostRunReviewScreen({super.key, required this.draft});

  @override
  State<RunPostRunReviewScreen> createState() => _RunPostRunReviewScreenState();
}

class _RunPostRunReviewScreenState extends State<RunPostRunReviewScreen> {
  final _runRepository = RunRepository();
  final _planRepository = RunPlanRepository();
  final _trackingService = RunTrackingService.instance;
  late final TextEditingController _titleController;
  late final TextEditingController _notesController;

  RunPlanWorkout? _planWorkout;
  List<RunAchievementPlacement> _newAchievements = const [];
  double? _rpe;
  int? _feelingRating;
  bool _completePlannedWorkout = false;
  bool _loading = true;
  bool _saving = false;

  bool get _hasPlannedWorkout => widget.draft.planWorkoutId != null;
  bool get _isTooShort => RunCompletionPolicy.isTooShort(widget.draft.activity);

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.draft.activity.title ?? '',
    );
    _notesController = TextEditingController(
      text: widget.draft.activity.notes ?? '',
    );
    _rpe = widget.draft.activity.rpe;
    _feelingRating = widget.draft.activity.feelingRating;
    _completePlannedWorkout = _hasPlannedWorkout && !_isTooShort;
    _loadContext();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadContext() async {
    ScheduledRun? scheduled;
    RunPlanWorkout? workout;
    final scheduledId = widget.draft.scheduledRunId;
    if (scheduledId != null) {
      scheduled = await _planRepository.getScheduledRun(scheduledId);
      workout = scheduled?.workout;
    }
    final workoutId = widget.draft.planWorkoutId;
    if (workout == null && workoutId != null) {
      workout = await _planRepository.getWorkout(workoutId);
    }
    final existing = await _runRepository.listActivities(limit: 500);
    final board = RunAchievementEngine.build([
      ...existing.where((item) => item.id != widget.draft.id),
      widget.draft.activity,
    ]);
    if (!mounted) return;
    setState(() {
      _planWorkout = workout;
      _newAchievements = board.forActivity(widget.draft.id);
      if (_titleController.text.trim().isEmpty && workout != null) {
        _titleController.text = workout.name;
      }
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await _trackingService.saveReviewedRun(
      draft: widget.draft,
      completePlannedWorkout:
          _hasPlannedWorkout && !_isTooShort && _completePlannedWorkout,
      title: _titleController.text,
      notes: _notesController.text,
      rpe: _rpe,
      feelingRating: _feelingRating,
    );
    if (!mounted) return;
    if (saved == null) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.runReviewSaveError),
        ),
      );
      return;
    }
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => RunDetailScreen(activityId: saved.id)),
    );
  }

  Future<void> _discard() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.runReviewDiscardTitle),
        content: Text(loc.runReviewDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.runReviewDiscard),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    await _trackingService.discardReview(widget.draft);
    if (mounted) Navigator.pop(context);
  }

  Widget _sectionLabel(String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.35,
        ),
      ),
    );
  }

  Widget _card(Widget child) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _summary(AppLocalizations loc) {
    final activity = widget.draft.activity;
    return _card(
      LayoutBuilder(
        builder: (context, constraints) {
          final width = (constraints.maxWidth - 10) / 2;
          return Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ReviewMetric(
                width: width,
                label: loc.runReviewDistance,
                value: RunFormatters.distanceWithUnit(activity.distanceMeters),
                icon: Icons.straighten_rounded,
              ),
              _ReviewMetric(
                width: width,
                label: loc.runReviewTime,
                value: RunFormatters.duration(activity.durationSeconds),
                icon: Icons.timer_outlined,
              ),
              _ReviewMetric(
                width: width,
                label: loc.runReviewPace,
                value: RunFormatters.paceWithUnit(activity.avgPaceSecPerKm),
                icon: Icons.speed_rounded,
              ),
              _ReviewMetric(
                width: width,
                label: loc.runReviewSplits,
                value: '${widget.draft.splits.length}',
                icon: Icons.flag_outlined,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _planComparison(AppLocalizations loc) {
    final workout = _planWorkout;
    if (!_hasPlannedWorkout || workout == null) {
      return const SizedBox.shrink();
    }
    final activity = widget.draft.activity;
    final outline = RunPlanUi.stepsOutline(loc, workout);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            workout.name,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            RunPlanUi.sessionSummary(loc, workout),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (outline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(outline, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ComparisonColumn(
                  label: loc.runReviewPlanned,
                  distanceMeters: workout.plannedDistanceMeters,
                  durationSeconds: workout.plannedDurationSeconds,
                  paceSecPerKm: workout.targetPaceSecPerKm,
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Icon(Icons.arrow_forward_rounded),
              ),
              Expanded(
                child: _ComparisonColumn(
                  label: loc.runReviewActual,
                  distanceMeters: activity.distanceMeters,
                  durationSeconds: activity.durationSeconds,
                  paceSecPerKm: activity.avgPaceSecPerKm,
                ),
              ),
            ],
          ),
          if (widget.draft.stepResults.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Divider(),
            for (final step in widget.draft.stepResults)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${RunPlanUi.roleLabel(loc, RunStepRole.fromString(step.role))} ${step.repIndex}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      step.actualDistanceMeters != null &&
                              step.actualDistanceMeters! >= 1
                          ? RunFormatters.distanceWithUnit(
                              step.actualDistanceMeters!,
                            )
                          : RunFormatters.duration(
                              step.actualDurationSeconds ?? 0,
                            ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      RunFormatters.pace(step.actualPaceSecPerKm),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 12),
          if (_isTooShort)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.runReviewShortTitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    loc.runReviewShortBody,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ],
              ),
            )
          else
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _completePlannedWorkout,
              onChanged: (value) =>
                  setState(() => _completePlannedWorkout = value ?? true),
              title: Text(loc.runReviewCompletePlan),
              controlAffinity: ListTileControlAffinity.leading,
            ),
        ],
      ),
    );
  }

  Widget _effort(AppLocalizations loc) => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          loc.runReviewEffortBody,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var value = 1; value <= 10; value++) ...[
              if (value > 1) const SizedBox(width: 3),
              Expanded(child: _effortOption(value)),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _effortOption(int value) {
    final theme = Theme.of(context);
    final selected = _rpe == value.toDouble();
    return Semantics(
      label: '$value',
      selected: selected,
      button: true,
      child: SizedBox(
        key: ValueKey('run-review-rpe-$value'),
        height: 40,
        child: Material(
          color: selected
              ? theme.colorScheme.primaryContainer
              : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: BorderSide(
              color: selected
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => setState(() => _rpe = value.toDouble()),
            child: Center(
              child: Text(
                '$value',
                maxLines: 1,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimaryContainer
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _feeling(AppLocalizations loc) {
    final theme = Theme.of(context);
    final ratingColor = Colors.amber.shade700;
    final labels = [
      loc.runReviewFeelingVeryBad,
      loc.runReviewFeelingBad,
      loc.runReviewFeelingNeutral,
      loc.runReviewFeelingGood,
      loc.runReviewFeelingGreat,
    ];
    return _card(
      Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(5, (index) {
            final isSelected = index < (_feelingRating ?? 0);
            return IconButton(
              key: ValueKey('run-review-feeling-${index + 1}'),
              tooltip: labels[index],
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
              onPressed: () => setState(() {
                _feelingRating = isSelected && _feelingRating == index + 1
                    ? 0
                    : index + 1;
              }),
              icon: Icon(
                isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                size: 24,
                color: isSelected
                    ? ratingColor
                    : theme.colorScheme.onSurfaceVariant,
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _details(AppLocalizations loc) => _card(
    Column(
      children: [
        TextField(
          controller: _titleController,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: loc.runDetailTitleLabel),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(labelText: loc.runDetailNotes),
        ),
      ],
    ),
  );

  Widget _achievements(AppLocalizations loc) => _card(
    _loading
        ? const Center(child: CircularProgressIndicator())
        : _newAchievements.isEmpty
        ? Text(
            loc.runReviewNoAchievements,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          )
        : RunMedalBadgeRow(
            placements: _newAchievements,
            maxVisible: 10,
            labelFor: (kind) => runAchievementKindShortLabel(loc, kind),
          ),
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runReviewTitle),
        actions: [
          IconButton(
            onPressed: null,
            tooltip: loc.runReviewShareSoon,
            icon: const Icon(Icons.ios_share_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
        children: [
          _sectionLabel(loc.runReviewSummary),
          _summary(loc),
          if (_hasPlannedWorkout && _planWorkout != null) ...[
            _sectionLabel(loc.runReviewPlanComparison),
            _planComparison(loc),
          ],
          if (widget.draft.splits.isNotEmpty) ...[
            _sectionLabel(loc.runReviewSplits),
            _card(RunSplitsList(splits: widget.draft.splits)),
          ],
          _sectionLabel(loc.runReviewEffortTitle),
          _effort(loc),
          _sectionLabel(loc.runReviewFeelingTitle),
          _feeling(loc),
          _sectionLabel(loc.runReviewDetailsTitle),
          _details(loc),
          _sectionLabel(loc.runReviewAchievementsTitle),
          _achievements(loc),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _saving ? null : _discard,
                  child: Text(
                    loc.runReviewDiscard,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(loc.runReviewSave, maxLines: 1, softWrap: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  final double width;
  final String label;
  final String value;
  final IconData icon;

  const _ReviewMetric({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18),
            const SizedBox(height: 8),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ComparisonColumn extends StatelessWidget {
  final String label;
  final double distanceMeters;
  final int durationSeconds;
  final double? paceSecPerKm;

  const _ComparisonColumn({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecPerKm,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 5),
      Text(RunFormatters.distanceWithUnit(distanceMeters)),
      Text(RunFormatters.duration(durationSeconds)),
      Text(RunFormatters.paceWithUnit(paceSecPerKm)),
    ],
  );
}
