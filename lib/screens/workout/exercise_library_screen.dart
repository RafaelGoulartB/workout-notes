import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/screens/workout/exercise_form_screen.dart';
import 'package:workout_notes/utils/exercise_equipment.dart';
import 'package:workout_notes/utils/strength_exercise_library.dart';
import 'package:workout_notes/widgets/strength/exercises/exercise_library_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Every exercise, dense and searchable. Grouped by muscle when "All" is
/// selected and sorted A-Z; other sorts give one flat ranking.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _exerciseRepo = DatabaseHelper.instance.exerciseRepo;
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _exercises = [];
  Map<String, ExerciseUsage> _usage = const {};
  Map<String, double> _bestE1rm = const {};
  String? _selectedCategoryId;
  String _search = '';
  bool _isLoading = true;
  bool _favoritesOnly = false;
  ExerciseLibrarySort _sort = ExerciseLibrarySort.az;
  Timer? _searchDebounce;

  // What the list shows. Filtering and sorting run when their inputs change
  // (a search, a chip, a sort, a load), not on every rebuild.
  AppLocalizations? _loc;
  List<ExerciseLibraryEntry> _entries = const [];
  List<ExerciseLibrarySection> _sections = const [];

  bool get _grouped =>
      _selectedCategoryId == null && _sort == ExerciseLibrarySort.az;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final loc = AppLocalizations.of(context)!;
    final localeChanged = _loc != null && _loc!.localeName != loc.localeName;
    _loc = loc;
    if (localeChanged) _recompute();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final categories = await _exerciseRepo.getCategories();
    // Query rows are read-only; the favorite star is toggled in place.
    final exercises = [
      for (final row in await _exerciseRepo.getExercises())
        Map<String, dynamic>.of(row),
    ];
    var usage = const <String, ExerciseUsage>{};
    var e1rm = const <String, double>{};
    try {
      usage = await _exerciseRepo.getExerciseUsage();
      final records = await DatabaseHelper.instance.strengthRecordsRepo.listRecords();
      e1rm = {
        for (final record in records)
          if (record.bestE1rm != null) record.exerciseId: record.bestE1rm!,
      };
    } catch (_) {
      // Older schemas may lack the history tables; the list still works.
    }
    if (!mounted) return;
    setState(() {
      _categories = categories;
      _exercises = exercises;
      _usage = usage;
      _bestE1rm = e1rm;
      _isLoading = false;
      _recompute();
    });
  }

  /// Filters and sorts the exercises into [_entries] (and [_sections] for the
  /// grouped view). Call inside `setState` whenever an input changed.
  void _recompute() {
    final loc = _loc;
    if (loc == null) return;
    _entries = _filterAndSort(loc);
    _sections = _grouped
        ? StrengthExerciseLibrary.grouped(_entries, [
            for (final c in _categories) c['id'] as String,
          ])
        : const [];
  }

  List<ExerciseLibraryEntry> _filterAndSort(AppLocalizations loc) {
    final query = _search.trim();
    final result = <ExerciseLibraryEntry>[];
    for (final row in _exercises) {
      if (_selectedCategoryId != null &&
          row['category_id'] != _selectedCategoryId) {
        continue;
      }
      if (_favoritesOnly && (row['is_favorite'] as int?) != 1) continue;
      if (query.isNotEmpty &&
          !ExerciseLocaleHelper.exerciseMatchesSearch(loc, row, query) &&
          !ExerciseLocaleHelper.categoryName(
            loc,
            row,
          ).toLowerCase().contains(query.toLowerCase()) &&
          !ExerciseEquipment.matches(loc, row['equipment'] as String?, query)) {
        continue;
      }
      final id = row['id'] as String;
      result.add(
        ExerciseLibraryEntry(
          row: row,
          name: ExerciseLocaleHelper.exerciseName(loc, row),
          usage: _usage[id],
          bestE1rm: _bestE1rm[id],
        ),
      );
    }
    return StrengthExerciseLibrary.sorted(result, _sort);
  }

  Future<void> _toggleFavorite(ExerciseLibraryEntry entry) async {
    // Update in place so the list does not jump while the user is scrolling.
    final wasFavorite = entry.isFavorite;
    setState(() {
      entry.row['is_favorite'] = wasFavorite ? 0 : 1;
      _recompute();
    });
    try {
      await _exerciseRepo.toggleFavorite(entry.id);
    } catch (_) {
      if (mounted) {
        setState(() {
          entry.row['is_favorite'] = wasFavorite ? 1 : 0;
          _recompute();
        });
      }
    }
  }

  Future<void> _openExercise(ExerciseLibraryEntry entry) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseDetailTabsScreen(
          exerciseId: entry.id,
          exerciseName: entry.name,
        ),
      ),
    );
    if (result == true || mounted) await _load();
  }

  Future<void> _createExercise() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseFormScreen()),
    );
    if (result == true && mounted) await _load();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _selectedCategoryId = null;
      _favoritesOnly = false;
      _recompute();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final entries = _isLoading ? const <ExerciseLibraryEntry>[] : _entries;
    final categoryById = {for (final c in _categories) c['id'] as String: c};

    return Scaffold(
      appBar: AppBar(title: Text(loc.exerciseLibraryTitle), centerTitle: true),
      body: Column(
        children: [
          ExerciseLibraryFilterBar(
            searchController: _searchController,
            onSearchChanged: (value) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 200), () {
                if (!mounted) return;
                setState(() {
                  _search = value;
                  _recompute();
                });
              });
            },
            categories: _categories,
            selectedCategoryId: _selectedCategoryId,
            onCategoryChanged: (id) => setState(() {
              _selectedCategoryId = id;
              _recompute();
            }),
            favoritesOnly: _favoritesOnly,
            onFavoritesChanged: (value) => setState(() {
              _favoritesOnly = value;
              _recompute();
            }),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? _buildEmptyState(theme, loc)
                : RefreshIndicator(
                    onRefresh: _load,
                    // Rows are built lazily: the "All" view has ~130 of them.
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          sliver: SliverMainAxisGroup(
                            slivers: [
                              SliverToBoxAdapter(
                                child: ExerciseLibraryListHeader(
                                  count: entries.length,
                                  sort: _sort,
                                  onSortChanged: (value) => setState(() {
                                    _sort = value;
                                    _recompute();
                                  }),
                                ),
                              ),
                              if (_grouped)
                                for (final section in _sections) ...[
                                  SliverToBoxAdapter(
                                    child: ExerciseLibrarySectionHeader(
                                      category:
                                          categoryById[section.categoryId] ??
                                          {
                                            'id': section.categoryId,
                                            'name': section.categoryId,
                                          },
                                      count: section.entries.length,
                                    ),
                                  ),
                                  _rowsSliver(
                                    section.entries,
                                    showCategory: false,
                                  ),
                                ]
                              else
                                _rowsSliver(entries, showCategory: true),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createExercise,
        icon: const Icon(Icons.add_rounded),
        label: Text(loc.exerciseLibraryNew),
      ),
    );
  }

  /// The rows of one card (a muscle group, or the flat ranking) as a lazy
  /// list drawn on the same bordered surface as `AppSectionCard`.
  Widget _rowsSliver(
    List<ExerciseLibraryEntry> entries, {
    required bool showCategory,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dividerColor = colors.outlineVariant.withAlpha(70);
    const radius = Radius.circular(AppUi.cardRadius);
    return DecoratedSliver(
      decoration: BoxDecoration(
        color: theme.cardTheme.color ?? colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(AppUi.cardRadius),
        border: Border.all(color: AppUi.divider(colors)),
      ),
      sliver: SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => Divider(height: 1, color: dividerColor),
        itemBuilder: (context, index) {
          final entry = entries[index];
          Widget row = ExerciseLibraryRow(
            key: ValueKey(entry.id),
            entry: entry,
            showCategory: showCategory,
            onTap: () => _openExercise(entry),
            onToggleFavorite: () => _toggleFavorite(entry),
          );
          // The card clips its rows to the rounded corners.
          final first = index == 0;
          final last = index == entries.length - 1;
          if (first || last) {
            row = ClipRRect(
              borderRadius: BorderRadius.vertical(
                top: first ? radius : Radius.zero,
                bottom: last ? radius : Radius.zero,
              ),
              child: row,
            );
          }
          return row;
        },
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    final onlyFavorites =
        _favoritesOnly && _search.isEmpty && _selectedCategoryId == null;
    final hasFilters =
        _search.isNotEmpty || _selectedCategoryId != null || _favoritesOnly;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              onlyFavorites
                  ? Icons.star_outline_rounded
                  : Icons.search_off_rounded,
              size: 72,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 20),
            Text(
              onlyFavorites
                  ? loc.exerciseLibraryNoFavorites
                  : loc.exerciseLibraryNoResults,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              onlyFavorites
                  ? loc.exerciseLibraryNoFavoritesHint
                  : loc.exerciseLibraryNoResultsHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (hasFilters) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: _clearFilters,
                child: Text(loc.exerciseLibraryClearFilters),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
