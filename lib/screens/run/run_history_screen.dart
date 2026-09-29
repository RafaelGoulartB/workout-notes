import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_activity_filter.dart';
import 'package:workout_notes/screens/run/run_detail_screen.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';
import 'package:workout_notes/widgets/run/history/run_history_filter_bar.dart';
import 'package:workout_notes/widgets/run/history/run_history_row.dart';
import 'package:workout_notes/database/database_helper.dart';

class RunHistoryScreen extends StatefulWidget {
  const RunHistoryScreen({super.key});

  @override
  State<RunHistoryScreen> createState() => _RunHistoryScreenState();
}

/// One line of the history list: a month header or an activity.
sealed class _Entry {
  const _Entry();
}

class _MonthEntry extends _Entry {
  final DateTime month;
  const _MonthEntry(this.month);
}

class _ActivityEntry extends _Entry {
  final RunActivity activity;
  const _ActivityEntry(this.activity);
}

class _RunHistoryScreenState extends State<RunHistoryScreen> {
  static const _pageSize = 30;

  final _repo = DatabaseHelper.instance.runRepo;
  final _scroll = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

  RunHistoryFilter _filter = const RunHistoryFilter();
  final List<RunActivity> _activities = [];
  List<_Entry> _entries = const [];
  RunActivityTotals _totals = RunActivityTotals.empty;
  Map<String, RunActivityTotals> _monthTotals = const {};
  RunAchievementBoard _board = RunAchievementBoard.empty;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  bool _backfilled = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  RunActivityFilter get _query => _filter.toQuery(DateTime.now());

  Future<void> _load({bool showSpinner = true}) async {
    final generation = ++_generation;
    if (showSpinner && _activities.isEmpty) setState(() => _loading = true);
    if (!_backfilled) {
      _backfilled = true;
      await _repo.backfillMissingEfforts(limit: 40);
    }
    final query = _query;
    final results = await Future.wait<Object>([
      _repo.searchActivities(query, limit: _pageSize),
      _repo.summarizeActivities(query),
      _repo.monthlyTotals(query),
      _repo.listActivities(limit: null),
    ]);
    if (!mounted || generation != _generation) return;
    final page = results[0] as List<RunActivity>;
    setState(() {
      _activities
        ..clear()
        ..addAll(page);
      _totals = results[1] as RunActivityTotals;
      _monthTotals = results[2] as Map<String, RunActivityTotals>;
      _board = RunAchievementEngine.build(results[3] as List<RunActivity>);
      _hasMore = page.length >= _pageSize;
      _entries = _buildEntries();
      _loading = false;
    });
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading) return;
    final generation = _generation;
    setState(() => _loadingMore = true);
    final page = await _repo.searchActivities(
      _query,
      limit: _pageSize,
      offset: _activities.length,
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      _activities.addAll(page);
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
    for (final activity in _activities) {
      final local = activity.startedAt.toLocal();
      final key = _monthKey(local);
      if (key != lastKey) {
        entries.add(_MonthEntry(DateTime(local.year, local.month)));
        lastKey = key;
      }
      entries.add(_ActivityEntry(activity));
    }
    return entries;
  }

  static String _monthKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}';

  void _setFilter(RunHistoryFilter filter) {
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
    _setFilter(const RunHistoryFilter());
  }

  Future<void> _openRecord() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RunRecordScreen()),
    );
    if (mounted) _load(showSpinner: false);
  }

  Future<void> _openDetail(RunActivity activity) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RunDetailScreen(activityId: activity.id),
      ),
    );
    if (mounted) _load(showSpinner: false);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final isEmptyHistory = !_loading && !_filter.isActive && _totals.count == 0;

    return Scaffold(
      appBar: AppBar(title: Text(loc.runHistoryTitle)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRecord,
        icon: const Icon(Icons.directions_run),
        label: Text(loc.runRecordStart),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : isEmptyHistory
          ? EmptyStatePlaceholder(
              icon: Icons.directions_run,
              title: loc.runHistoryEmptyTitle,
              subtitle: loc.runHistoryEmptySubtitle,
              actionLabel: loc.runHistoryEmptyCta,
              onAction: _openRecord,
            )
          : Column(
              children: [
                RunHistoryFilterBar(
                  filter: _filter,
                  searchController: _searchController,
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
    if (_activities.isEmpty) {
      // Scrollable so pull-to-refresh keeps working.
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 48),
          EmptyStatePlaceholder(
            icon: Icons.search_off_rounded,
            title: loc.runHistoryNoResultsTitle,
            subtitle: loc.runHistoryNoResultsSubtitle,
            actionLabel: loc.runHistoryClearFilters,
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
          _MonthEntry(:final month) => RunHistoryMonthHeader(
            month: month,
            totals: _monthTotals[_monthKey(month)],
          ),
          _ActivityEntry(:final activity) => RunHistoryRow(
            activity: activity,
            medals: _board.forActivity(activity.id),
            onTap: () => _openDetail(activity),
          ),
        };
      },
    );
  }
}

/// One-line result of the current filter (replaces the old duplicate hero).
class _SummaryLine extends StatelessWidget {
  final RunActivityTotals totals;
  final RunHistoryFilter filter;
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
              loc.runHistorySummary(
                totals.count,
                RunFormatters.distanceWithUnit(totals.distanceMeters),
                RunFormatters.durationHoursMinutes(totals.movingTimeSeconds),
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
              child: Text(loc.runHistoryClearFilters),
            ),
        ],
      ),
    );
  }
}
