import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/screens/workout/exercise_form_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/exercise/exercise_charts_card.dart';
import 'package:workout_notes/widgets/strength/exercise/exercise_detail_header.dart';
import 'package:workout_notes/widgets/strength/exercise/exercise_history_list.dart';

enum _DetailTab { history, charts }

/// Detail of one exercise: muscle group and equipment, its personal records,
/// the workouts it appeared in (History) and progress charts. Editing opens
/// the regular exercise form. Pops with `true` when the exercise was edited or
/// deleted so the caller can refresh.
class ExerciseDetailTabsScreen extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;

  const ExerciseDetailTabsScreen({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
  });

  @override
  State<ExerciseDetailTabsScreen> createState() =>
      _ExerciseDetailTabsScreenState();
}

class _ExerciseDetailTabsScreenState extends State<ExerciseDetailTabsScreen> {
  final _exerciseRepo = ExerciseRepository();
  final _analyticsRepo = DatabaseHelper.instance.analyticsRepo;
  final _recordsRepo = StrengthRecordsRepository();

  bool _loading = true;
  bool _failed = false;
  bool _changed = false;
  _DetailTab _tab = _DetailTab.history;

  Map<String, dynamic>? _exercise;
  List<ExerciseSession> _sessions = const [];
  StrengthRecord? _record;
  Set<String> _recordWorkoutIds = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _exerciseRepo.getExercise(widget.exerciseId),
        _analyticsRepo.getExerciseHistory(widget.exerciseId),
        _recordsRepo.loadSets(exerciseId: widget.exerciseId),
      ]);
      if (!mounted) return;
      final history = results[1] as Map<String, dynamic>;
      final sets = results[2] as List<StrengthSetSample>;
      final records = StrengthRecordsCalculator.records(sets);
      setState(() {
        _exercise = results[0] as Map<String, dynamic>?;
        _sessions = [
          for (final row in (history['history'] as List))
            ExerciseSession.fromRow(row as Map<String, dynamic>),
        ];
        _record = records.isEmpty ? null : records.first;
        _recordWorkoutIds = {
          for (final e in StrengthRecordsCalculator.events(sets)) e.workoutId,
        };
        _failed = false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _edit() async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseFormScreen(exerciseId: widget.exerciseId),
      ),
    );
    if (saved == true && mounted) {
      _changed = true;
      _load();
    }
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final name = _displayName(loc);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.exerciseDetailDeleteTitle),
        content: Text(loc.exerciseDetailDeleteBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _exerciseRepo.deleteExercise(widget.exerciseId);
    if (mounted) Navigator.pop(context, true);
  }

  String _displayName(AppLocalizations loc) {
    final row = _exercise;
    if (row == null) return widget.exerciseName;
    final name = ExerciseLocaleHelper.exerciseName(loc, row);
    return name.isEmpty ? widget.exerciseName : name;
  }

  Future<void> _openWorkout(ExerciseSession session) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(workoutId: session.workoutId),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return PopScope<Object?>(
      canPop: !_changed,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, true);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_displayName(loc)),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: loc.exerciseDetailEdit,
              onPressed: _exercise == null ? null : _edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: loc.commonDelete,
              onPressed: _delete,
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(60),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: RunSegmentedTabs<_DetailTab>(
                values: _DetailTab.values,
                selected: _tab,
                labelOf: (tab) => tab == _DetailTab.history
                    ? loc.commonHistory
                    : loc.commonCharts,
                onChanged: (tab) => setState(() => _tab = tab),
              ),
            ),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed || _exercise == null
            ? EmptyStatePlaceholder(
                icon: Icons.error_outline_rounded,
                title: loc.strengthInsightsLoadError,
                subtitle: '',
              )
            : _buildBody(loc),
      ),
    );
  }

  Widget _buildBody(AppLocalizations loc) {
    final row = _exercise!;
    final categoryId = row['category_id'] as String? ?? '';
    final categoryRow = {
      'category_id': categoryId,
      'category_name': row['category_name'],
    };
    final content = _sessions.isEmpty
        ? Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Column(
              children: [
                Icon(
                  Icons.history_rounded,
                  size: 56,
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  loc.exerciseDetailNoWorkouts,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  loc.exerciseDetailNoWorkoutsBody,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        : _tab == _DetailTab.history
        ? ExerciseHistoryList(
            sessions: _sessions,
            recordWorkoutIds: _recordWorkoutIds,
            onOpen: _openWorkout,
          )
        : ExerciseChartsCard(sessions: _sessions);

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: RunUi.screenPadding.copyWith(top: 8, bottom: 40),
        children: [
          ExerciseDetailHeader(
            name: _displayName(loc),
            categoryName: ExerciseLocaleHelper.categoryName(loc, categoryRow),
            categoryColor: Color((row['category_color'] as int?) ?? 0xFF757575),
            equipment: row['equipment'] as String?,
            notes: ExerciseLocaleHelper.exerciseNotes(loc, row),
            sessions: _sessions.length,
          ),
          if (_sessions.isNotEmpty) ...[
            const SizedBox(height: 12),
            ExerciseRecordsRow(record: _record),
          ],
          const SizedBox(height: 12),
          content,
        ],
      ),
    );
  }
}
