import 'package:uuid/uuid.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';

/// Test fixture: puts a planned run on the calendar for [date], optionally
/// linked to a plan session. Production schedules runs through
/// `materializeWeek` / `scheduleRunPlanForPhase`.
Future<ScheduledRun> scheduleRunFixture(
  RunPlanRepository repository, {
  required DateTime date,
  String? runPlanId,
  String? runPlanWorkoutId,
  String? notes,
}) async {
  final database = await repository.db;
  final now = DateTime.now();
  final scheduled = ScheduledRun(
    id: const Uuid().v4(),
    date: DateTime(date.year, date.month, date.day),
    runPlanId: runPlanId,
    runPlanWorkoutId: runPlanWorkoutId,
    status: ScheduledRunStatus.planned,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
  await database.insert('scheduled_runs', scheduled.toMap());
  return scheduled;
}
