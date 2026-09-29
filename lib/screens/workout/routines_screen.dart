import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/routine_day_editor_screen.dart';
import 'package:workout_notes/screens/workout/routine_form_screen.dart';
import 'package:workout_notes/utils/strength_routine_summary.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/routines/routine_list_cards.dart';
import 'package:workout_notes/widgets/strength/routines/routine_sheets.dart';

export 'package:workout_notes/screens/workout/routine_form_screen.dart';

/// Library of routines: the one in use is pinned on top with a start button
/// per day, the rest of the library sits below it.
class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  final _repo = RoutineRepository();
  List<RoutineSummary> _routines = const [];
  String? _activeId;
  RoutineInUseReason _reason = RoutineInUseReason.recent;
  String? _nextDayId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final routines = await _repo.getRoutineSummaries();
    String? plannedRoutineId;
    String? plannedDayId;
    try {
      final suggestion = await PeriodizationRepository().getRoutineSuggestion(
        DateTime.now(),
      );
      plannedRoutineId = suggestion?.routineId;
      plannedDayId = suggestion?.routineDayId;
    } catch (_) {
      // Planning tables may not exist on older databases.
    }
    final activeId = pickActiveRoutineId(
      routines: routines,
      plannedRoutineId: plannedRoutineId,
    );
    final planned = activeId != null && activeId == plannedRoutineId;
    final active = routines.where((r) => r.id == activeId).firstOrNull;
    if (!mounted) return;
    setState(() {
      _routines = routines;
      _activeId = activeId;
      _reason = planned
          ? RoutineInUseReason.planned
          : RoutineInUseReason.recent;
      _nextDayId = planned
          ? plannedDayId
          : (active == null ? null : pickNextDayId(active));
      _loading = false;
    });
  }

  Future<void> _openRoutine(RoutineSummary routine) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoutineFormScreen(routineId: routine.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _openDay(RoutineSummary routine, RoutineDaySummary day) async {
    final loc = AppLocalizations.of(context)!;
    await Navigator.push(
      context,
      AiCoachNavigation.route(
        kind: AiCoachRouteKind.normalWithFab,
        builder: (_) => RoutineDayEditorScreen(
          routineDayId: day.id,
          routineId: routine.id,
          dayName: day.name.isEmpty
              ? loc.routineDayDefaultName(day.orderIndex + 1)
              : day.name,
          dayNotes: day.notes,
        ),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _startDay(RoutineSummary routine, RoutineDaySummary day) async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) =>
            ActiveWorkoutScreen(routineId: routine.id, routineDayId: day.id),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _createRoutine() async {
    final loc = AppLocalizations.of(context)!;
    final details = await showRoutineDetailsSheet(
      context,
      title: loc.routinesNew,
      nameLabel: loc.routinesName,
      nameHint: loc.routinesNameHint,
      submitLabel: loc.routinesCreate,
      withNotes: true,
      notesLabel: loc.routinesNotes,
      notesHint: loc.routinesNotesHint,
    );
    if (details == null) return;
    final id = await _repo.createRoutine(
      details.name,
      notes: details.notes.isEmpty ? null : details.notes,
    );
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RoutineFormScreen(routineId: id)),
    );
    if (mounted) _load();
  }

  Future<void> _duplicate(RoutineSummary routine) async {
    final loc = AppLocalizations.of(context)!;
    await _repo.duplicateRoutine(
      routine.id,
      loc.routinesDuplicateSuffix(routine.name),
    );
    if (mounted) _load();
  }

  Future<void> _delete(RoutineSummary routine) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await confirmRoutineDestructive(
      context,
      title: loc.routinesDeleteConfirm(routine.name),
      content: loc.routinesDeleteRoutineContent,
    );
    if (!confirmed) return;
    await _repo.deleteRoutine(routine.id);
    if (mounted) _load();
  }

  RoutineCardActions _actionsFor(RoutineSummary routine) => RoutineCardActions(
    onOpen: () => _openRoutine(routine),
    onDuplicate: () => _duplicate(routine),
    onDelete: () => _delete(routine),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final active = _routines.where((r) => r.id == _activeId).firstOrNull;
    final others = [
      for (final routine in _routines)
        if (routine.id != _activeId) routine,
    ];

    return Scaffold(
      appBar: AppBar(title: Text(loc.routinesTitle), centerTitle: true),
      floatingActionButton: _routines.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createRoutine,
              icon: const Icon(Icons.add),
              label: Text(loc.routinesNewRoutine),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _routines.isEmpty
          ? _buildEmpty(theme, loc)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: RunUi.screenPadding.copyWith(top: 8),
                children: [
                  if (active != null) ...[
                    RunSectionHeader(
                      loc.routinesInUseSection,
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                      trailing: Text(
                        _reason == RoutineInUseReason.planned
                            ? loc.routinesInUsePlanned
                            : loc.routinesInUseRecent,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    RoutineInUseCard(
                      routine: active,
                      actions: _actionsFor(active),
                      nextDayId: _nextDayId,
                      onStartDay: (day) => _startDay(active, day),
                      onOpenDay: (day) => _openDay(active, day),
                    ),
                  ],
                  if (others.isNotEmpty) ...[
                    RunSectionHeader(
                      loc.routinesOthersSection,
                      padding: EdgeInsets.fromLTRB(
                        4,
                        active == null ? 8 : 22,
                        0,
                        8,
                      ),
                    ),
                    RoutineLibraryList(
                      routines: others,
                      actionsFor: _actionsFor,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildEmpty(ThemeData theme, AppLocalizations loc) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.repeat_rounded,
            size: 80,
            color: theme.colorScheme.primary.withAlpha(80),
          ),
          const SizedBox(height: 24),
          Text(
            loc.routinesEmptyTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            loc.routinesEmptySubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createRoutine,
            icon: const Icon(Icons.add),
            label: Text(loc.routinesNewRoutine),
          ),
        ],
      ),
    ),
  );
}
