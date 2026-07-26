import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../repositories/exercise_repository.dart';
import 'exercise_form_screen.dart';
import 'exercise_detail_tabs_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _exerciseRepo = ExerciseRepository();
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _exercises = [];
  String? _selectedCategoryId;
  String _search = '';
  bool _isLoading = true;
  bool _showFavorites = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _categories = await _exerciseRepo.getCategories();
    _exercises = await _exerciseRepo.getExercises(
      favorites: _showFavorites ? true : null,
    );
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    return _exercises.where((e) {
      if (_selectedCategoryId != null &&
          e['category_id'] != _selectedCategoryId) {
        return false;
      }
      if (_search.isNotEmpty &&
          !(e['name'] as String)
              .toLowerCase()
              .contains(_search.toLowerCase())) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _toggleFavorite(String id) async {
    await _exerciseRepo.toggleFavorite(id);
    _load();
  }

  IconData _iconForType(String? type) {
    switch (type) {
      case 'distanceTime':
      case 'distanceOnly':
        return Icons.straighten_rounded;
      case 'weightDistance':
      case 'weightOnly':
        return Icons.monitor_weight_rounded;
      case 'weightTime':
      case 'timeOnly':
        return Icons.timer_rounded;
      case 'repsDistance':
      case 'repsOnly':
        return Icons.repeat_rounded;
      case 'repsTime':
      case 'weightReps':
      default:
        return Icons.fitness_center_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.exerciseLibraryTitle),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(
              _showFavorites ? Icons.star_rounded : Icons.star_outline_rounded,
            ),
            onPressed: () {
              setState(() => _showFavorites = !_showFavorites);
              _load();
            },
            tooltip: AppLocalizations.of(context)!.exerciseLibraryFavorites,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: AppLocalizations.of(context)!.exerciseLibrarySearch,
                prefixIcon: const Icon(Icons.search_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withAlpha(80),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              children: [
                FilterChip(
                  label: Text(
                    AppLocalizations.of(context)!.exerciseLibraryAll,
                  ),
                  selected: _selectedCategoryId == null,
                  onSelected: (_) =>
                      setState(() => _selectedCategoryId = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map(
                  (cat) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(
                        ExerciseLocaleHelper.categoryName(
                          AppLocalizations.of(context)!,
                          cat,
                        ),
                      ),
                      selected: _selectedCategoryId == cat['id'],
                      onSelected: (_) => setState(
                        () => _selectedCategoryId =
                            _selectedCategoryId == cat['id']
                                ? null
                                : cat['id'] as String,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? _buildEmptyState(theme)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) =>
                              _buildExerciseCard(filtered[i], theme),
                        ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ExerciseFormScreen()),
          );
          if (result == true) _load();
        },
        icon: const Icon(Icons.add_rounded),
        label: Text(AppLocalizations.of(context)!.exerciseLibraryNew),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 80,
              color: theme.colorScheme.primary.withAlpha(80),
            ),
            const SizedBox(height: 24),
            Text(loc.exerciseLibraryNoResults, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              loc.exerciseLibraryNoResultsHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseCard(Map<String, dynamic> ex, ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
    final isFav = (ex['is_favorite'] as int?) == 1;
    final equipment = ex['equipment'] as String?;
    final exerciseName = ExerciseLocaleHelper.exerciseName(loc, ex);
    final categoryName = ExerciseLocaleHelper.categoryName(loc, ex);
    final hasNotes = ExerciseLocaleHelper.exerciseNotes(loc, ex).isNotEmpty;
    final muted = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExerciseDetailTabsScreen(
                  exerciseId: ex['id'] as String,
                  exerciseName: exerciseName,
                ),
              ),
            );
            if (result == true) _load();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: catColor.withAlpha(25),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconForType(ex['type'] as String?),
                    color: catColor,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exerciseName,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: muted,
                          ),
                          children: [
                            TextSpan(text: categoryName),
                            if (equipment != null && equipment.isNotEmpty) ...[
                              const WidgetSpan(child: SizedBox(width: 6)),
                              const TextSpan(text: '·'),
                              const WidgetSpan(child: SizedBox(width: 6)),
                              TextSpan(text: equipment),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasNotes)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, right: 2),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: muted.withAlpha(150),
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    isFav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: isFav
                        ? Colors.amber.shade600
                        : muted.withAlpha(120),
                    size: 22,
                  ),
                  onPressed: () => _toggleFavorite(ex['id'] as String),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 36,
                    minHeight: 36,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
