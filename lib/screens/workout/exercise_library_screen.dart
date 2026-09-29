import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/screens/workout/exercise_form_screen.dart';
import 'package:workout_notes/utils/exercise_equipment.dart';
import 'package:workout_notes/utils/strength_exercise_library.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/exercises/exercise_library_widgets.dart';

/// Every exercise, dense and searchable. Grouped by muscle when "All" is
/// selected and sorted A-Z; other sorts give one flat ranking.
class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _exerciseRepo = ExerciseRepository();
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

  @override
  void initState() {
    super.initState();
    _load();
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
      final records = await StrengthRecordsRepository().listRecords();
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
    });
  }

  List<ExerciseLibraryEntry> _entries(AppLocalizations loc) {
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
    setState(() => entry.row['is_favorite'] = wasFavorite ? 0 : 1);
    try {
      await _exerciseRepo.toggleFavorite(entry.id);
    } catch (_) {
      if (mounted) {
        setState(() => entry.row['is_favorite'] = wasFavorite ? 1 : 0);
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
    if (result == true || mounted) _load();
  }

  Future<void> _createExercise() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ExerciseFormScreen()),
    );
    if (result == true && mounted) _load();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _search = '';
      _selectedCategoryId = null;
      _favoritesOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final entries = _isLoading ? const <ExerciseLibraryEntry>[] : _entries(loc);
    final grouped =
        _selectedCategoryId == null && _sort == ExerciseLibrarySort.az;
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
                if (mounted) setState(() => _search = value);
              });
            },
            categories: _categories,
            selectedCategoryId: _selectedCategoryId,
            onCategoryChanged: (id) => setState(() => _selectedCategoryId = id),
            favoritesOnly: _favoritesOnly,
            onFavoritesChanged: (value) =>
                setState(() => _favoritesOnly = value),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                ? _buildEmptyState(theme, loc)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                      children: [
                        ExerciseLibraryListHeader(
                          count: entries.length,
                          sort: _sort,
                          onSortChanged: (value) =>
                              setState(() => _sort = value),
                        ),
                        if (grouped)
                          ..._buildSections(entries, categoryById)
                        else
                          RunSectionCard(
                            padding: EdgeInsets.zero,
                            child: _rows(entries, showCategory: true),
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

  List<Widget> _buildSections(
    List<ExerciseLibraryEntry> entries,
    Map<String, Map<String, dynamic>> categoryById,
  ) {
    final sections = StrengthExerciseLibrary.grouped(entries, [
      for (final c in _categories) c['id'] as String,
    ]);
    return [
      for (final section in sections) ...[
        ExerciseLibrarySectionHeader(
          category:
              categoryById[section.categoryId] ??
              {'id': section.categoryId, 'name': section.categoryId},
          count: section.entries.length,
        ),
        RunSectionCard(
          padding: EdgeInsets.zero,
          child: _rows(section.entries, showCategory: false),
        ),
      ],
    ];
  }

  Widget _rows(
    List<ExerciseLibraryEntry> entries, {
    required bool showCategory,
  }) => RunDividedList(
    children: [
      for (final entry in entries)
        ExerciseLibraryRow(
          key: ValueKey(entry.id),
          entry: entry,
          showCategory: showCategory,
          onTap: () => _openExercise(entry),
          onToggleFavorite: () => _toggleFavorite(entry),
        ),
    ],
  );

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
