import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';
import 'package:workout_notes/repositories/strength_history_repository.dart';
import 'package:workout_notes/screens/workout/active_workout_screen.dart';
import 'package:workout_notes/screens/workout/workout_detail_screen.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/strength/history/strength_history_filter_bar.dart';
import 'package:workout_notes/widgets/strength/history/strength_history_row.dart';

/// Searchable, filterable history of finished gym workouts.
class StrengthHistoryScreen extends StatefulWidget {
  const StrengthHistoryScreen({super.key});

  @override
  State<StrengthHistoryScreen> createState() => _StrengthHistoryScreenState();
}

/// One line of the history list: a month header or a workout.
sealed class _Entry {
  const _Entry();
}

class _MonthEntry extends _Entry {
  final DateTime month;
  const _MonthEntry(this.month);
}

class _WorkoutEntry extends _Entry {
  final StrengthHistoryWorkout workout;
  const _WorkoutEntry(this.workout);
}

class _StrengthHistoryScreenState extends State<StrengthHistoryScreen> {
  static const _pageSize = 30;

  StrengthHistoryRepository? _repoInstance;
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  StrengthHistoryFilter _filter = const StrengthHistoryFilter();
  final List<StrengthHistoryWorkout> _workouts = [];
  List<_Entry> _entries = const [];
  StrengthHistoryTotals _totals = StrengthHistoryTotals.empty;
  Map<String, StrengthHistoryTotals> _monthTotals = const {};
  Map<String, int> _recordCounts = const {};
  List<StrengthRoutineOption> _routines = const [];
  List<StrengthCategoryOption> _categories = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _optionsLoaded = false;
  int _generation = 0;

  StrengthHistoryRepository get _repo => _repoInstance!;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = AppLocalizations.of(context)!;
    final first = _repoInstance == null;
    _repoInstance = StrengthHistoryRepository(
      exerciseMatcher: (row, query) =>
          ExerciseLocaleHelper.exerciseMatchesSearch(loc, row, query),
    );
    if (first) _initialLoad();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Names older workouts (one-off) before the first query only, so
  /// searching and filtering never wait on it.
  Future<void> _initialLoad() async {
    await StrengthRoutineDayInference.runOnce();
    if (mounted) await _load();
  }

  Future<void> _load({bool showSpinner = true}) async {
    final generation = ++_generation;
    if (showSpinner && _workouts.isEmpty) setState(() => _loading = true);
    final filter = _filter;
    final results = await Future.wait<Object>([
      _repo.search(filter, limit: _pageSize),
      _repo.summarize(filter),
      _repo.monthlyTotals(filter),
      _repo.recordCounts(),
      _repo.routineOptions(),
      if (!_optionsLoaded) _repo.categoryOptions(),
    ]);
    if (!mounted || generation != _generation) return;
    final page = results[0] as List<StrengthHistoryWorkout>;
    setState(() {
      _workouts
        ..clear()
        ..addAll(page);
      _totals = results[1] as StrengthHistoryTotals;
      _monthTotals = results[2] as Map<String, StrengthHistoryTotals>;
      _recordCounts = results[3] as Map<String, int>;
      _routines = results[4] as List<StrengthRoutineOption>;
      if (!_optionsLoaded) {
        _categories = results[5] as List<StrengthCategoryOption>;
        _optionsLoaded = true;
      }
      _hasMore = page.length >= _pageSize;
      _entries = _buildEntries();
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final page = await _repo.search(
      _filter,
      limit: _pageSize,
      offset: _workouts.length,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _workouts.addAll(page);
      _hasMore = page.length >= _pageSize;
      _loadingMore = false;
      _entries = _buildEntries();
    });
  }

  void _onScroll() {
    if (_scroll.hasClients && _scroll.position.extentAfter < 500) {
      _loadMore();
    }
  }

  List<_Entry> _buildEntries() {
    final entries = <_Entry>[];
    String? lastKey;
    for (final workout in _workouts) {
      final key = _monthKey(workout.day);
      if (key != lastKey) {
        entries.add(_MonthEntry(DateTime(workout.day.year, workout.day.month)));
        lastKey = key;
      }
      entries.add(_WorkoutEntry(workout));
    }
    return entries;
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  void _setFilter(StrengthHistoryFilter filter) {
    setState(() => _filter = filter);
    _load(showSpinner: false);
  }

  void _onQueryChanged(String text) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      _setFilter(_filter.copyWith(query: text));
    });
  }

  void _clearFilters() {
    _searchController.clear();
    _setFilter(const StrengthHistoryFilter());
  }

  Future<void> _startWorkout() async {
    await Navigator.push(
      context,
      AiCoachNavigation.route(
        kind: AiCoachRouteKind.activeWorkout,
        builder: (_) => const ActiveWorkoutScreen(),
      ),
    );
    if (mounted) _load(showSpinner: false);
  }

  Future<void> _openDetail(StrengthHistoryWorkout workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkoutDetailScreen(workoutId: workout.id),
      ),
    );
    if (mounted) _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isEmptyHistory = !_loading && !_filter.isActive && _totals.count == 0;

    return Scaffold(
      appBar: AppBar(title: Text(loc.strengthHistoryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _startWorkout,
        icon: const Icon(Icons.fitness_center_rounded),
        label: Text(loc.strengthHistoryStart),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isEmptyHistory
          ? EmptyStatePlaceholder(
              icon: Icons.fitness_center_rounded,
              title: loc.strengthHistoryEmptyTitle,
              subtitle: loc.strengthHistoryEmptySubtitle,
              actionLabel: loc.strengthHistoryEmptyCta,
              onAction: _startWorkout,
            )
          : Column(
              children: [
                StrengthHistoryFilterBar(
                  filter: _filter,
                  searchController: _searchController,
                  routines: _routines,
                  categories: _categories,
                  onQueryChanged: _onQueryChanged,
                  onChanged: _setFilter,
                ),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _load(showSpinner: false),
                    child: _buildList(loc),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildList(AppLocalizations loc) {
    if (_workouts.isEmpty) {
      // Scrollable so pull-to-refresh keeps working.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          EmptyStatePlaceholder(
            icon: Icons.search_off_rounded,
            title: loc.strengthHistoryNoResultsTitle,
            subtitle: loc.strengthHistoryNoResultsSubtitle,
            actionLabel: loc.strengthHistoryClearFilters,
            onAction: _clearFilters,
          ),
        ],
      );
    }
    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 104),
      // Summary line + entries + optional loading spinner.
      itemCount: _entries.length + 2,
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SummaryLine(
            totals: _totals,
            filter: _filter,
            onClear: _clearFilters,
          );
        }
        final entryIndex = index - 1;
        if (entryIndex == _entries.length) {
          return _loadingMore
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                )
              : const SizedBox.shrink();
        }
        return switch (_entries[entryIndex]) {
          _MonthEntry(:final month) => StrengthHistoryMonthHeader(
            month: month,
            totals: _monthTotals[_monthKey(month)],
          ),
          _WorkoutEntry(:final workout) => StrengthHistoryRow(
            workout: workout.withRecordCount(_recordCounts[workout.id] ?? 0),
            onTap: () => _openDetail(workout),
          ),
        };
      },
    );
  }
}

/// One-line result of the current filter.
class _SummaryLine extends StatelessWidget {
  final StrengthHistoryTotals totals;
  final StrengthHistoryFilter filter;
  final VoidCallback onClear;

  const _SummaryLine({
    required this.totals,
    required this.filter,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 0, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              loc.strengthHistorySummary(
                totals.count,
                StrengthWorkoutFormat.volume(totals.volume),
                RunFormatters.durationHoursMinutes(totals.durationSeconds),
              ),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (filter.isActive)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: Text(loc.strengthHistoryClearFilters),
            ),
        ],
      ),
    );
  }
}
