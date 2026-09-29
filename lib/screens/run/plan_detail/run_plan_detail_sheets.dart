import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// Values chosen in the plan edit sheet.
class RunPlanEditResult {
  final String? name;
  final String notes;
  final RunPlanGoalKind goal;
  final DateTime? raceDate;
  final int? weeks;

  const RunPlanEditResult({
    required this.name,
    required this.notes,
    required this.goal,
    required this.raceDate,
    required this.weeks,
  });
}

/// Bottom sheet to edit the plan header. Shrinking the plan asks for
/// confirmation first, since it drops sessions. Null when cancelled.
Future<RunPlanEditResult?> showRunPlanEditSheet(
  BuildContext context,
  RunPlan plan,
) async {
  final loc = AppLocalizations.of(context)!;
  final nameCtl = TextEditingController(text: plan.name);
  final notesCtl = TextEditingController(text: plan.notes ?? '');
  final weeksCtl = TextEditingController(text: plan.weeks.toString());
  var goal = plan.goalKind;
  var raceDate = plan.raceDate;

  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.runPlanEditTitle,
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: nameCtl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: loc.runPlanName,
                  hintText: loc.runPlanNameHint,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<RunPlanGoalKind>(
                initialValue: goal,
                decoration: InputDecoration(
                  labelText: loc.runPlanGoalKind,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  for (final kind in RunPlanGoalKind.values)
                    DropdownMenuItem(
                      value: kind,
                      child: Text(RunPlanUi.goalLabel(loc, kind)),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setSheetState(() => goal = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: weeksCtl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: loc.runPlanWeeks,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.flag_outlined),
                title: Text(loc.runPlanRaceDate),
                subtitle: Text(
                  raceDate == null
                      ? loc.runPlanRaceDateNone
                      : DateFormat(
                          'd MMM y',
                          Intl.defaultLocale,
                        ).format(raceDate!),
                ),
                trailing: raceDate == null
                    ? const Icon(Icons.event_outlined)
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () => setSheetState(() => raceDate = null),
                      ),
                onTap: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: raceDate ?? now,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 5),
                  );
                  if (picked != null) setSheetState(() => raceDate = picked);
                },
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notesCtl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: loc.runPlanNotes,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(loc.commonSave),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    ),
  );
  if (saved != true) return null;

  final weeks = int.tryParse(weeksCtl.text.trim());
  // Shrinking the horizon drops sessions, so confirm before losing them.
  if (weeks != null && weeks < plan.weeks) {
    final dropped = plan.workouts
        .where((workout) => workout.weekIndex >= weeks)
        .length;
    if (dropped > 0 && context.mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.commonConfirmDelete),
          content: Text(loc.commonActionCannotBeUndone),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.commonSave),
            ),
          ],
        ),
      );
      if (confirmed != true) return null;
    }
  }

  final result = RunPlanEditResult(
    name: nameCtl.text.trim().isEmpty ? null : nameCtl.text.trim(),
    notes: notesCtl.text.trim(),
    goal: goal,
    raceDate: raceDate,
    weeks: weeks,
  );
  nameCtl.dispose();
  notesCtl.dispose();
  weeksCtl.dispose();
  return result;
}

/// Asks which week to move a session to. Null when cancelled.
Future<int?> showRunPlanMoveWeekSheet(
  BuildContext context,
  RunPlan plan, {
  required int fromWeek,
}) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<int>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              loc.runPlanMoveWeekTitle,
              style: Theme.of(ctx).textTheme.titleMedium,
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (var week = 0; week < plan.weeks; week++)
                  if (week != fromWeek)
                    ListTile(
                      title: Text(loc.runPlanWeekLabel(week + 1)),
                      subtitle: Text(
                        loc.runPlanWeekSummary(
                          RunPlanUi.kmValue(plan.weeklyDistanceMeters(week)),
                          plan.workoutsForWeek(week).length,
                        ),
                      ),
                      onTap: () => Navigator.pop(ctx, week),
                    ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// Asks which weeks receive a copy of [sourceWeek]. Null / empty when
/// cancelled.
Future<Set<int>?> showRunPlanCopyWeekSheet(
  BuildContext context,
  RunPlan plan, {
  required int sourceWeek,
}) async {
  final loc = AppLocalizations.of(context)!;
  final selected = <int>{};
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheetState) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                loc.runPlanCopyWeekTitle(sourceWeek + 1),
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (var i = 0; i < plan.weeks; i++)
                    if (i != sourceWeek)
                      CheckboxListTile(
                        value: selected.contains(i),
                        title: Text(loc.runPlanWeekLabel(i + 1)),
                        subtitle: Text(
                          loc.runPlanWeekSummary(
                            RunPlanUi.kmValue(plan.weeklyDistanceMeters(i)),
                            plan.workoutsForWeek(i).length,
                          ),
                        ),
                        onChanged: (checked) => setSheetState(() {
                          if (checked == true) {
                            selected.add(i);
                          } else {
                            selected.remove(i);
                          }
                        }),
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: selected.isEmpty
                      ? null
                      : () => Navigator.pop(ctx, true),
                  child: Text(loc.runPlanCopyWeek),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (confirmed != true || selected.isEmpty) return null;
  return selected;
}
