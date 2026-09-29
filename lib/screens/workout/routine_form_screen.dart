import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/routine_day_editor_screen.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/routines/routine_day_card.dart';
import 'package:workout_notes/widgets/strength/routines/routine_muscle_widgets.dart';
import 'package:workout_notes/widgets/strength/routines/routine_sheets.dart';

/// One routine: summary hero, sets per muscle against the recommended range
/// and its training days.
class RoutineFormScreen extends StatefulWidget {
  final String routineId;
  const RoutineFormScreen({super.key, required this.routineId});

  @override
  State<RoutineFormScreen> createState() => _RoutineFormScreenState();
}

class _RoutineFormScreenState extends State<RoutineFormScreen> {
  final _repo = RoutineRepository();
  RoutineSummary? _routine;
  String? _nextDayId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    RoutineSummary? routine;
    try {
      routine = await _repo.getRoutineSummary(widget.routineId);
    } catch (_) {
      // Shown as an empty screen; the routine may have been deleted.
    }
    String? nextDayId;
    if (routine != null) {
      try {
        final suggestion = await PeriodizationRepository().getRoutineSuggestion(
          DateTime.now(),
        );
        if (suggestion?.routineId == widget.routineId) {
          nextDayId = suggestion?.routineDayId;
        }
      } catch (_) {
        // Planning tables may not exist on older databases.
      }
      nextDayId ??= pickNextDayId(routine);
    }
    if (!mounted) return;
    setState(() {
      _routine = routine;
      _nextDayId = nextDayId;
      _loading = false;
    });
  }

  Future<void> _addDay() async {
    final loc = AppLocalizations.of(context)!;
    final details = await showRoutineDetailsSheet(
      context,
      title: loc.routinesNewDay,
      nameLabel: loc.routinesDayName,
      nameHint: loc.routinesDayNameHint,
      submitLabel: loc.routinesAddDay,
    );
    if (details == null) return;
    await _repo.addRoutineDay(widget.routineId, details.name);
    if (mounted) _load();
  }

  Future<void> _editDetails() async {
    final loc = AppLocalizations.of(context)!;
    final routine = _routine;
    if (routine == null) return;
    final details = await showRoutineDetailsSheet(
      context,
      title: loc.routinesEdit,
      nameLabel: loc.routinesName,
      submitLabel: loc.commonSave,
      initialName: routine.name,
      withNotes: true,
      initialNotes: routine.notes ?? '',
      notesLabel: loc.routinesNotes,
      notesHint: loc.routinesNotesHint,
    );
    if (details == null) return;
    await _repo.updateRoutine(
      widget.routineId,
      name: details.name,
      notes: details.notes,
    );
    if (mounted) _load();
  }

  Future<void> _deleteRoutine() async {
    final loc = AppLocalizations.of(context)!;
    final routine = _routine;
    if (routine == null) return;
    final confirmed = await confirmRoutineDestructive(
      context,
      title: loc.routinesDeleteConfirm(routine.name),
      content: loc.routinesDeleteRoutineContent,
    );
    if (!confirmed) return;
    await _repo.deleteRoutine(widget.routineId);
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _openDay(RoutineDaySummary day, int index) async {
    final loc = AppLocalizations.of(context)!;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineDayEditorScreen(
          routineDayId: day.id,
          routineId: widget.routineId,
          dayName: day.name.isEmpty
              ? loc.routineDayDefaultName(index + 1)
              : day.name,
          dayNotes: day.notes,
        ),
      ),
    );
    // Exercises and sets may have changed inside the editor.
    if (mounted) _load();
  }

  Future<void> _startDay(RoutineDaySummary day) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ActiveWorkoutScreen(
          routineId: widget.routineId,
          routineDayId: day.id,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final routine = _routine;

    return Scaffold(
      appBar: AppBar(
        title: Text(routine?.name ?? loc.routinesTitle),
        centerTitle: true,
        actions: [
          if (routine != null)
            PopupMenuButton<String>(
              tooltip: loc.commonMoreOptions,
              onSelected: (value) {
                if (value == 'edit') _editDetails();
                if (value == 'delete') _deleteRoutine();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(loc.routineEditDetails),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    loc.routinesDelete,
                    style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                  ),
                ),
              ],
            ),
        ],
      ),
      // The empty state carries its own "add day" button.
      floatingActionButton: routine == null || routine.days.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _addDay,
              icon: const Icon(Icons.add),
              label: Text(loc.routinesAddDay),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : routine == null
          ? const SizedBox.shrink()
          : routine.days.isEmpty
          ? _buildEmptyDays(context, loc, routine)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppUi.screenPadding.copyWith(top: 8),
                children: [
                  RoutineHero(routine: routine),
                  const SizedBox(height: 12),
                  RoutineWeeklyMusclesCard(muscles: routine.muscles),
                  AppSectionHeader(
                    loc.routineDaysSection,
                    padding: const EdgeInsets.fromLTRB(4, 20, 0, 10),
                  ),
                  for (var i = 0; i < routine.days.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: RoutineDayCard(
                        day: routine.days[i],
                        index: i,
                        isNext: routine.days[i].id == _nextDayId,
                        onOpen: () => _openDay(routine.days[i], i),
                        onStart: () => _startDay(routine.days[i]),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildEmptyDays(
    BuildContext context,
    AppLocalizations loc,
    RoutineSummary routine,
  ) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_view_week_rounded,
              size: 72,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 20),
            Text(
              loc.routinesDayEmpty,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              loc.routinesDayEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addDay,
              icon: const Icon(Icons.add),
              label: Text(loc.routinesAddDay),
            ),
          ],
        ),
      ),
    );
  }
}
