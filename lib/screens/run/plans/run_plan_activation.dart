import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';

/// Starts following [plan], confirming first when another plan is active:
/// only one plan can drive "which run is due today". Returns true when the
/// plan is now followed.
Future<bool> followRunPlan(
  BuildContext context,
  RunPlanRepository repo,
  RunPlan plan,
) async {
  final loc = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  final current = await repo.getActivatedPlan(hydrate: false);
  if (!context.mounted) return false;
  if (current != null && current.id != plan.id) {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runPlanReplaceActiveTitle),
        content: Text(loc.runPlanReplaceActiveBody(current.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.runPlanActivate),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return false;
  }
  final created = await repo.activatePlan(plan.id);
  messenger.showSnackBar(
    SnackBar(content: Text(loc.runPlanActivatedMessage(created))),
  );
  return true;
}

/// Stops following [plan] and tells the user.
Future<void> unfollowRunPlan(
  BuildContext context,
  RunPlanRepository repo,
  RunPlan plan,
) async {
  final loc = AppLocalizations.of(context)!;
  final messenger = ScaffoldMessenger.of(context);
  await repo.deactivatePlan(plan.id);
  messenger.showSnackBar(
    SnackBar(content: Text(loc.runPlanDeactivatedMessage)),
  );
}

/// Opens the recorder on [view]'s session, attached to its calendar row when
/// it has one, so finishing the run ticks the session off.
Future<void> startRunPlanSession(
  BuildContext context,
  RunPlanRepository repo,
  RunPlanSessionView view,
) async {
  final scheduledId = view.ledger?.scheduledRunId;
  final scheduled = scheduledId == null
      ? null
      : await repo.getScheduledRun(scheduledId);
  if (!context.mounted) return;
  await Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) =>
          RunRecordScreen(planWorkout: view.workout, scheduledRun: scheduled),
    ),
  );
}
