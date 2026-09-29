import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_data_field.dart';
import 'package:workout_notes/models/run_interval_snapshot.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_step_snapshot.dart';
import 'package:workout_notes/models/run_tracking_state.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/widgets/run/record/measure_height.dart';
import 'package:workout_notes/widgets/run/record/run_data_fields_grid.dart';
import 'package:workout_notes/widgets/run/record/run_record_activity_picker.dart';
import 'package:workout_notes/widgets/run/record/run_record_controls.dart';
import 'package:workout_notes/widgets/run/record/run_record_indoor.dart';
import 'package:workout_notes/widgets/run/record/run_record_session_card.dart';
import 'package:workout_notes/widgets/run/record/run_record_splits.dart';
import 'package:workout_notes/widgets/run/record/run_record_step_card.dart';
import 'package:workout_notes/widgets/run/record/run_today_workout_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// The bottom sheet of the record screen. Before the start it configures the
/// run (exercise, today's workout, goal, voice); while recording it shows the
/// live data fields, the workout step, splits/laps and the controls.
class RunRecordSheet extends StatelessWidget {
  final ScrollController scrollController;

  /// Reports the height of the collapsed content so the sheet can hug it.
  final ValueChanged<double> onContentHeight;
  final RunTrackingState state;
  final CardioActivityType activityType;
  final bool busy;
  final bool expanded;
  final bool showDebugSimulate;

  // Live data fields.
  final List<RunDataField> fields;
  final double bodyWeightKg;
  final VoidCallback? onCustomizeFields;
  final ValueChanged<int>? onFieldLongPress;

  // This run.
  final bool intervalsOn;
  final RunIntervalSnapshot intervalSnapshot;
  final RunIntervalPreset intervalPreset;
  final RunPlanWorkout? planWorkout;
  final VoidCallback? onDetachPlan;
  final RunPlanWorkout? todayWorkout;
  final VoidCallback? onUseTodayWorkout;
  final RunStepSnapshot stepSnapshot;
  final RunSessionGoal goal;
  final RunGoalSnapshot goalSnapshot;
  final VoidCallback? onEditGoal;
  final VoidCallback? onClearGoal;
  final ValueChanged<bool>? onIntervalsChanged;
  final bool voiceEnabled;
  final bool headphonesOnly;
  final bool headsetConnected;
  final bool notificationsNeedAttention;

  // Actions.
  final ValueChanged<CardioActivityType>? onActivityTypeChanged;
  final VoidCallback onOpenVoiceSettings;
  final VoidCallback onOpenPermissions;
  final VoidCallback onStart;
  final VoidCallback onDebugSimulate;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onLap;
  final VoidCallback onFinish;
  final VoidCallback onSkipStep;

  const RunRecordSheet({
    super.key,
    required this.scrollController,
    required this.onContentHeight,
    required this.state,
    required this.activityType,
    required this.busy,
    required this.expanded,
    required this.showDebugSimulate,
    required this.fields,
    required this.bodyWeightKg,
    required this.onCustomizeFields,
    required this.onFieldLongPress,
    required this.intervalsOn,
    required this.intervalSnapshot,
    required this.intervalPreset,
    required this.planWorkout,
    required this.onDetachPlan,
    required this.todayWorkout,
    required this.onUseTodayWorkout,
    required this.stepSnapshot,
    required this.goal,
    required this.goalSnapshot,
    required this.onEditGoal,
    required this.onClearGoal,
    required this.onIntervalsChanged,
    required this.voiceEnabled,
    required this.headphonesOnly,
    required this.headsetConnected,
    required this.notificationsNeedAttention,
    required this.onActivityTypeChanged,
    required this.onOpenVoiceSettings,
    required this.onOpenPermissions,
    required this.onStart,
    required this.onDebugSimulate,
    required this.onPause,
    required this.onResume,
    required this.onLap,
    required this.onFinish,
    required this.onSkipStep,
  });

  bool get _indoor => activityType.isIndoor;

  RunSplit? get _lastCompleted =>
      state.splits.isEmpty ? null : state.splits.last;

  RunSplit? get _bestCompleted {
    RunSplit? best;
    for (final split in state.splits) {
      final pace = split.paceSecPerKm;
      if (pace == null || !pace.isFinite) continue;
      if (best == null || pace < (best.paceSecPerKm ?? double.infinity)) {
        best = split;
      }
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final systemBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad = (systemBottom > 0 ? systemBottom : 16.0) + 16.0;
    final active = state.isActive;
    final now = DateTime.now();
    final fixedFields = RunDataFieldLayout.fixedFor(activityType);

    final header = <Widget>[
      _handle(theme),
      if (!_indoor && !active) _permissionBanner(context, loc, theme),
      if (active) ...[
        _statusRow(context, loc),
        RunDataFieldsGrid(
          fields: fixedFields ?? fields,
          state: state,
          activityType: activityType,
          now: now,
          bodyWeightKg: bodyWeightKg,
          onFieldLongPress: fixedFields == null ? onFieldLongPress : null,
          onCustomize: fixedFields == null ? onCustomizeFields : null,
        ),
        const SizedBox(height: 12),
      ] else ...[
        RunActivityTypeSelector(
          value: activityType,
          onChanged: onActivityTypeChanged,
          // With a workout attached it is a run: outdoors or on the treadmill.
          allowed: planWorkout == null
              ? CardioActivityType.values
              : const [
                  CardioActivityType.running,
                  CardioActivityType.treadmill,
                ],
        ),
        const SizedBox(height: 12),
      ],
      if (!active && todayWorkout != null && planWorkout == null) ...[
        RunTodayWorkoutCard(
          workout: todayWorkout!,
          onUse: onUseTodayWorkout ?? () {},
        ),
        const SizedBox(height: 12),
      ],
      if (_indoor) ...[
        if (planWorkout != null) ...[
          RunSectionCard(
            padding: EdgeInsets.zero,
            child: RunRecordPlanTile(
              plan: planWorkout!,
              onDetach: active ? null : onDetachPlan,
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!active) RunIndoorInfoCard(type: activityType),
      ] else ...[
        if (active &&
            RunRecordStepCard.isVisible(
              stepSnapshot,
              intervalSnapshot,
              intervalsOn,
            )) ...[
          RunRecordStepCard(
            stepSnapshot: stepSnapshot,
            intervalSnapshot: intervalSnapshot,
            intervalsOn: intervalsOn,
            onSkip: busy ? null : onSkipStep,
          ),
          const SizedBox(height: 12),
        ],
        RunRecordSessionCard(
          goal: goal,
          goalSnapshot: goalSnapshot,
          active: active,
          planWorkout: planWorkout,
          onDetachPlan: onDetachPlan,
          intervalsOn: intervalsOn,
          intervalPreset: intervalPreset,
          onIntervalsChanged: onIntervalsChanged,
          onEditGoal: onEditGoal,
          onClearGoal: onClearGoal,
          voiceEnabled: voiceEnabled,
          headphonesOnly: headphonesOnly,
          headsetConnected: headsetConnected,
          onOpenVoiceSettings: onOpenVoiceSettings,
        ),
      ],
    ];

    final last = _lastCompleted;
    final best = _bestCompleted;
    final splitSummary = !_indoor && (last != null || best != null)
        ? Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RunSplitSummary(
              last: last,
              best: best,
              canExpand: state.splits.length > 1 || state.laps.isNotEmpty,
            ),
          )
        : const SizedBox.shrink();

    final expandedBody = <Widget>[
      if (active || state.laps.isNotEmpty) ...[
        RunSectionHeader(
          loc.runLapTitle,
          padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
        ),
        RunLapsTable(laps: state.laps, currentLap: state.currentLap),
      ],
      RunSectionHeader(
        loc.runRecordSplitsTitle,
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
      ),
      RunSplitsTable(splits: state.displaySplits),
      const SizedBox(height: 12),
    ];

    final controls = RunRecordControls(
      state: state,
      busy: busy,
      showLap: !_indoor,
      showDebugSimulate: showDebugSimulate,
      onStart: onStart,
      onPause: onPause,
      onResume: onResume,
      onLap: onLap,
      onFinish: onFinish,
      onDebugSimulate: onDebugSimulate,
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.98),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      // One scrollable, driven by the DraggableScrollableSheet controller, so
      // a drag anywhere on the sheet expands it and, at the top, collapses it.
      child: SingleChildScrollView(
        controller: scrollController,
        physics: const ClampingScrollPhysics(),
        // Measured only while collapsed: the expanded content is the full
        // laps/splits lists, which must not drive the collapsed height.
        child: MeasureHeight(
          onHeight: expanded ? null : onContentHeight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, bottomPad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ...header,
                if (expanded && !_indoor) ...expandedBody else splitSummary,
                const SizedBox(height: 12),
                controls,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _handle(ThemeData theme) {
    return Center(
      child: Container(
        width: 44,
        height: 5,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }

  /// "Auto-paused" / "Paused" pill above the numbers.
  Widget _statusRow(BuildContext context, AppLocalizations loc) {
    final theme = Theme.of(context);
    if (!state.isAutoPaused && !state.isPaused) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          RunPill(
            key: const ValueKey('run-paused-pill'),
            icon: Icons.pause_circle_outline_rounded,
            color: theme.colorScheme.tertiary,
            label: state.isAutoPaused
                ? loc.runAutoPauseActive
                : (_indoor && activityType == CardioActivityType.treadmill
                      ? loc.runTreadmillPaused
                      : loc.runRecordPaused),
          ),
          if (state.isAutoPaused) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                loc.runAutoPauseHint,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _permissionBanner(
    BuildContext context,
    AppLocalizations loc,
    ThemeData theme,
  ) {
    final locationMissing = !state.locationGranted;
    if (!state.supported || (!locationMissing && !notificationsNeedAttention)) {
      return const SizedBox.shrink();
    }
    final background = locationMissing
        ? theme.colorScheme.errorContainer
        : theme.colorScheme.secondaryContainer;
    final foreground = locationMissing
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.onSecondaryContainer;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: background.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              locationMissing
                  ? loc.runRecordPermissionNeeded
                  : loc.runPermissionsNotificationsBanner,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: onOpenPermissions,
              style: TextButton.styleFrom(foregroundColor: foreground),
              child: Text(loc.runPermissionsSetupAction),
            ),
          ],
        ),
      ),
    );
  }
}
