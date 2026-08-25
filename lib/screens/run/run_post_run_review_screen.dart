import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
  late final List<Offset> _route;

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
    _route = _RouteSketch.parse(widget.draft.activity.polylineSummary);
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

  // ---------------------------------------------------------------- chrome

  Widget _sectionLabel(IconData icon, String label) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Row(
        children: [
          Icon(icon, size: 15, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(Widget child, {EdgeInsets? padding}) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }

  // ------------------------------------------------------------------ hero

  Widget _hero(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final activity = widget.draft.activity;
    final dateLabel = DateFormat.MMMEd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());
    final hasRoute = _RouteSketch.hasShape(_route);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.primaryContainer.withValues(alpha: 0.55),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.directions_run_rounded,
                  size: 20,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runReviewHeroHeadline,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.runReviewDistance.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        RunFormatters.distanceWithUnit(activity.distanceMeters),
                        maxLines: 1,
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.05,
                          letterSpacing: -1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasRoute)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surface.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: _RouteSketch(
                      points: _route,
                      size: 76,
                      color: colors.primary,
                      endColor: colors.tertiary,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.timer_outlined,
                    label: loc.runReviewTime,
                    value: RunFormatters.duration(activity.durationSeconds),
                  ),
                ),
                _HeroDivider(color: colors.outlineVariant),
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.speed_rounded,
                    label: loc.runReviewPace,
                    value: RunFormatters.paceWithUnit(activity.avgPaceSecPerKm),
                  ),
                ),
                _HeroDivider(color: colors.outlineVariant),
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.local_fire_department_outlined,
                    label: loc.runDetailCalories,
                    value: '${activity.calories ?? 0}',
                  ),
                ),
              ],
            ),
          ),
          if (activity.bestSplitPaceSecPerKm != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.bolt_rounded, size: 15, color: colors.tertiary),
                const SizedBox(width: 6),
                Text(
                  '${loc.runDetailBestPace}: '
                  '${RunFormatters.paceWithUnit(activity.bestSplitPaceSecPerKm)}',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------- plan comparison

  Widget _planComparison(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            RunPlanUi.sessionSummary(loc, workout),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (outline.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(outline, style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: 14),
          // IntrinsicHeight bounds the cross axis so the two panels can match
          // heights: a bare stretch Row inside this scrolling Column gets an
          // unbounded height and lays out garbage.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _ComparisonPanel(
                    label: loc.runReviewPlanned,
                    distanceMeters: workout.plannedDistanceMeters,
                    durationSeconds: workout.plannedDurationSeconds,
                    paceSecPerKm: workout.targetPaceSecPerKm,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _ComparisonPanel(
                    label: loc.runReviewActual,
                    distanceMeters: activity.distanceMeters,
                    durationSeconds: activity.durationSeconds,
                    paceSecPerKm: activity.avgPaceSecPerKm,
                    highlight: true,
                  ),
                ),
              ],
            ),
          ),
          if (widget.draft.stepResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final step in widget.draft.stepResults)
              _StepResultRow(step: step),
          ],
          const SizedBox(height: 12),
          if (_isTooShort)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.errorContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: colors.onErrorContainer,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.runReviewShortTitle,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: colors.onErrorContainer,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          loc.runReviewShortBody,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          else
            _ToggleRow(
              value: _completePlannedWorkout,
              label: loc.runReviewCompletePlan,
              onChanged: (value) =>
                  setState(() => _completePlannedWorkout = value),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- effort

  Widget _effort(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _rpe?.round();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (var value = 1; value <= 10; value++) ...[
                if (value > 1) const SizedBox(width: 4),
                Expanded(child: _effortOption(value)),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                loc.runReviewEffortScaleMin,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                loc.runReviewEffortScaleMax,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSize(
            duration: const Duration(milliseconds: 140),
            alignment: Alignment.centerLeft,
            child: selected == null
                ? Text(
                    loc.runReviewEffortEmpty,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  )
                : Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: _effortColor(selected),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '$selected/10 · ${_effortZoneLabel(loc, selected)}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// Green through red, so the scale reads as intensity and not just numbers.
  Color _effortColor(int value) {
    if (value <= 3) return const Color(0xFF4CAF50);
    if (value <= 6) return const Color(0xFFFFB300);
    if (value <= 8) return const Color(0xFFFB8C00);
    return const Color(0xFFE53935);
  }

  String _effortZoneLabel(AppLocalizations loc, int value) {
    if (value <= 3) return loc.runReviewEffortZoneEasy;
    if (value <= 6) return loc.runReviewEffortZoneModerate;
    if (value <= 8) return loc.runReviewEffortZoneHard;
    return loc.runReviewEffortZoneMax;
  }

  Widget _effortOption(int value) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = _rpe == value.toDouble();
    final zoneColor = _effortColor(value);
    final foreground = selected
        ? (ThemeData.estimateBrightnessForColor(zoneColor) == Brightness.dark
              ? Colors.white
              : Colors.black87)
        : colors.onSurfaceVariant;
    return Semantics(
      label: '$value',
      selected: selected,
      button: true,
      child: SizedBox(
        key: ValueKey('run-review-rpe-$value'),
        height: 44,
        child: Material(
          color: selected ? zoneColor : colors.surfaceContainerHighest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: selected
                  ? zoneColor
                  : colors.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() => _rpe = value.toDouble());
            },
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Text(
                    '$value',
                    maxLines: 1,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- feeling

  Widget _feeling(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ratingColor = Colors.amber.shade600;
    final labels = [
      loc.runReviewFeelingVeryBad,
      loc.runReviewFeelingBad,
      loc.runReviewFeelingNeutral,
      loc.runReviewFeelingGood,
      loc.runReviewFeelingGreat,
    ];
    final rating = _feelingRating ?? 0;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (index) {
              final isSelected = index < rating;
              return IconButton(
                key: ValueKey('run-review-feeling-${index + 1}'),
                tooltip: labels[index],
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _feelingRating = isSelected && rating == index + 1
                        ? 0
                        : index + 1;
                  });
                },
                icon: Icon(
                  isSelected ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 32,
                  color: isSelected
                      ? ratingColor
                      : colors.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              rating >= 1 && rating <= 5
                  ? labels[rating - 1]
                  : loc.runReviewFeelingEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: rating >= 1 ? FontWeight.w700 : FontWeight.w400,
                color: rating >= 1 ? colors.onSurface : colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- details

  Widget _details(AppLocalizations loc) => _card(
    Column(
      children: [
        TextField(
          controller: _titleController,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.next,
          decoration: InputDecoration(
            labelText: loc.runDetailTitleLabel,
            hintText: loc.runReviewTitleHint,
            prefixIcon: const Icon(Icons.edit_outlined, size: 20),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesController,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            labelText: loc.runDetailNotes,
            hintText: loc.runReviewNotesHint,
            alignLabelWithHint: true,
          ),
        ),
      ],
    ),
  );

  // ---------------------------------------------------------- achievements

  Widget _achievements(AppLocalizations loc) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_loading) {
      return _card(
        const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox.square(
              dimension: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }
    if (_newAchievements.isEmpty) {
      return _card(
        Row(
          children: [
            Icon(
              Icons.workspace_premium_outlined,
              size: 20,
              color: colors.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loc.runReviewNoAchievements,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return _card(
      RunMedalBadgeRow(
        placements: _newAchievements,
        maxVisible: 10,
        labelFor: (kind) => runAchievementKindShortLabel(loc, kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _hero(loc),
          if (_hasPlannedWorkout && _planWorkout != null) ...[
            _sectionLabel(Icons.flag_outlined, loc.runReviewPlanComparison),
            _planComparison(loc),
          ],
          if (widget.draft.splits.isNotEmpty) ...[
            _sectionLabel(Icons.timeline_rounded, loc.runReviewSplits),
            _card(RunSplitsList(splits: widget.draft.splits)),
          ],
          _sectionLabel(Icons.whatshot_outlined, loc.runReviewEffortTitle),
          _effort(loc),
          _sectionLabel(
            Icons.sentiment_satisfied_outlined,
            loc.runReviewFeelingTitle,
          ),
          _feeling(loc),
          _sectionLabel(Icons.notes_rounded, loc.runReviewDetailsTitle),
          _details(loc),
          _sectionLabel(
            Icons.emoji_events_outlined,
            loc.runReviewAchievementsTitle,
          ),
          _achievements(loc),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _saving ? null : _discard,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                        side: BorderSide(
                          color: theme.colorScheme.error.withValues(alpha: 0.5),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        loc.runReviewDiscard,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: _saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check_rounded),
                      label: Text(
                        loc.runReviewSave,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.fade,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _HeroMetric({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final Color color;

  const _HeroDivider({required this.color});

  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 42, color: color.withValues(alpha: 0.4));
}

/// Minimal GPS trail drawn from the polyline summary — no tiles, no network.
class _RouteSketch extends StatelessWidget {
  final List<Offset> points;
  final double size;
  final Color color;
  final Color endColor;

  const _RouteSketch({
    required this.points,
    required this.size,
    required this.color,
    required this.endColor,
  });

  /// `lat,lng;lat,lng;…` as produced by `RunRepository._buildPolylineSummary`.
  static List<Offset> parse(String? summary) {
    if (summary == null || summary.isEmpty) return const [];
    final parsed = <Offset>[];
    for (final chunk in summary.split(';')) {
      final parts = chunk.split(',');
      if (parts.length != 2) continue;
      final lat = double.tryParse(parts[0]);
      final lng = double.tryParse(parts[1]);
      if (lat == null || lng == null) continue;
      parsed.add(Offset(lng, lat));
    }
    return parsed;
  }

  /// A trail worth drawing: at least two points spanning ~11 m or more.
  static bool hasShape(List<Offset> points) {
    if (points.length < 2) return false;
    var minX = points.first.dx;
    var maxX = points.first.dx;
    var minY = points.first.dy;
    var maxY = points.first.dy;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      maxX = math.max(maxX, p.dx);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    return (maxX - minX) >= 1e-4 || (maxY - minY) >= 1e-4;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _RoutePainter(points: points, color: color, endColor: endColor),
    ),
  );
}

class _RoutePainter extends CustomPainter {
  final List<Offset> points;
  final Color color;
  final Color endColor;

  const _RoutePainter({
    required this.points,
    required this.color,
    required this.endColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    // Longitude degrees shrink with latitude; scale so the shape is not skewed.
    final meanLat =
        points.map((p) => p.dy).reduce((a, b) => a + b) / points.length;
    final lngScale = math.cos(meanLat * math.pi / 180).abs().clamp(0.05, 1.0);

    var minX = double.infinity;
    var maxX = -double.infinity;
    var minY = double.infinity;
    var maxY = -double.infinity;
    for (final p in points) {
      final x = p.dx * lngScale;
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, p.dy);
      maxY = math.max(maxY, p.dy);
    }
    final spanX = math.max(maxX - minX, 1e-9);
    final spanY = math.max(maxY - minY, 1e-9);
    const padding = 8.0;
    final scale = math.min(
      (size.width - padding * 2) / spanX,
      (size.height - padding * 2) / spanY,
    );
    final offsetX = (size.width - spanX * scale) / 2;
    final offsetY = (size.height - spanY * scale) / 2;

    Offset project(Offset p) => Offset(
      offsetX + (p.dx * lngScale - minX) * scale,
      // Flip Y so north points up.
      size.height - offsetY - (p.dy - minY) * scale,
    );

    final path = Path()
      ..moveTo(project(points.first).dx, project(points.first).dy);
    for (final p in points.skip(1)) {
      final projected = project(p);
      path.lineTo(projected.dx, projected.dy);
    }

    // Soft halo under the trail keeps it legible over the hero gradient.
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color.withValues(alpha: 0.18),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    canvas.drawCircle(project(points.first), 3.6, Paint()..color = color);
    canvas.drawCircle(project(points.last), 4.4, Paint()..color = endColor);
    canvas.drawCircle(
      project(points.last),
      2,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
  }

  @override
  bool shouldRepaint(_RoutePainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.color != color ||
      oldDelegate.endColor != endColor;
}

class _ComparisonPanel extends StatelessWidget {
  final String label;
  final double distanceMeters;
  final int durationSeconds;
  final double? paceSecPerKm;
  final bool highlight;

  const _ComparisonPanel({
    required this.label,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.paceSecPerKm,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer.withValues(alpha: 0.45)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            // A planned session may target only time, or only distance.
            distanceMeters >= 1
                ? RunFormatters.distanceWithUnit(distanceMeters)
                : '—',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            durationSeconds > 0 ? RunFormatters.duration(durationSeconds) : '—',
            style: theme.textTheme.bodySmall,
          ),
          Text(
            RunFormatters.paceWithUnit(paceSecPerKm),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepResultRow extends StatelessWidget {
  final RunActivityStep step;

  const _StepResultRow({required this.step});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final role = RunStepRole.fromString(step.role);
    final color = RunPlanUi.roleColor(theme.colorScheme, role);
    final done =
        step.actualDistanceMeters != null && step.actualDistanceMeters! >= 1
        ? RunFormatters.distanceWithUnit(step.actualDistanceMeters!)
        : RunFormatters.duration(step.actualDurationSeconds ?? 0);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${RunPlanUi.roleLabel(loc, role)} ${step.repIndex}',
              style: theme.textTheme.bodySmall,
            ),
          ),
          Text(
            done,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            RunFormatters.pace(step.actualPaceSecPerKm),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: value
          ? colors.primaryContainer.withValues(alpha: 0.4)
          : colors.surfaceContainerHighest.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!value),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 4, 14, 4),
          child: Row(
            children: [
              Checkbox(
                value: value,
                visualDensity: VisualDensity.compact,
                onChanged: (next) => onChanged(next ?? true),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: value ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
