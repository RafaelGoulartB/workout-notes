import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import 'exercise_form_screen.dart';
import 'exercise_detail_tabs_screen.dart';

class ExerciseLibraryScreen extends StatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  State<ExerciseLibraryScreen> createState() => _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends State<ExerciseLibraryScreen> {
  final _db = DatabaseHelper.instance;
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
    _categories = await _db.getCategories();
    _exercises = await _db.getExercises(favorites: _showFavorites ? true : null);
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filtered {
    return _exercises.where((e) {
      if (_selectedCategoryId != null && e['category_id'] != _selectedCategoryId) return false;
      if (_search.isNotEmpty && !(e['name'] as String).toLowerCase().contains(_search.toLowerCase())) return false;
      return true;
    }).toList();
  }

  Future<void> _toggleFavorite(String id) async {
    await _db.toggleFavorite(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercícios'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(_showFavorites ? Icons.star : Icons.star_outline),
            onPressed: () {
              setState(() => _showFavorites = !_showFavorites);
              _load();
            },
            tooltip: 'Favoritos',
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Buscar exercício...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),

          // Category filters
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              children: [
                FilterChip(
                  label: const Text('Todos'),
                  selected: _selectedCategoryId == null,
                  onSelected: (_) => setState(() => _selectedCategoryId = null),
                ),
                const SizedBox(width: 8),
                ..._categories.map((cat) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(cat['name'] as String),
                    selected: _selectedCategoryId == cat['id'],
                    onSelected: (_) => setState(
                      () => _selectedCategoryId = _selectedCategoryId == cat['id'] ? null : cat['id'] as String),
                  ),
                )),
              ],
            ),
          ),

          const Divider(height: 1),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 64, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                              const SizedBox(height: 16),
                              Text('Nenhum exercício encontrado', style: theme.textTheme.titleMedium),
                              const SizedBox(height: 8),
                              Text('Tente alterar a busca ou adicione um novo', style: theme.textTheme.bodySmall),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                          itemCount: filtered.length,
                          itemBuilder: (ctx, i) {
                            final ex = filtered[i];
                            final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
                            final isFav = (ex['is_favorite'] as int?) == 1;
                            final equipment = ex['equipment'] as String?;

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => ExerciseDetailTabsScreen(
                                        exerciseId: ex['id'] as String,
                                        exerciseName: ex['name'] as String,
                                      ),
                                    ),
                                  );
                                  if (result == true) _load();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 6, height: 48,
                                        decoration: BoxDecoration(
                                          color: catColor,
                                          borderRadius: BorderRadius.circular(3),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(ex['name'] as String, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                            const SizedBox(height: 2),
                                            Row(
                                              children: [
                                                Text(ex['category_name'] as String? ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                                const SizedBox(width: 6),
                                                _buildEnergyChip(ex['category_energy'] as String? ?? 'anaerobic', theme),
                                                if (equipment != null && equipment.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                    decoration: BoxDecoration(
                                                      color: theme.colorScheme.surfaceContainerHighest,
                                                      borderRadius: BorderRadius.circular(4),
                                                    ),
                                                    child: Text(equipment, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (ex['notes'] != null && (ex['notes'] as String).isNotEmpty)
                                        Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                                      IconButton(
                                        icon: Icon(
                                          isFav ? Icons.star : Icons.star_border,
                                          color: isFav ? Colors.amber : theme.colorScheme.onSurfaceVariant.withAlpha(80),
                                          size: 22,
                                        ),
                                        onPressed: () => _toggleFavorite(ex['id'] as String),
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
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
        icon: const Icon(Icons.add),
        label: const Text('Novo Exercício'),
      ),
    );
  }

  Widget _buildEnergyChip(String energy, ThemeData theme) {
    final isAerobic = energy == 'aerobic';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: (isAerobic ? Colors.red : Colors.blue).withAlpha(30),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isAerobic ? Icons.favorite : Icons.fitness_center,
            size: 10,
            color: isAerobic ? Colors.red[400] : Colors.blue[400],
          ),
          const SizedBox(width: 2),
          Text(
            isAerobic ? 'Aeróbico' : 'Anaeróbico',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9,
              color: isAerobic ? Colors.red[400] : Colors.blue[400],
            ),
          ),
        ],
      ),
    );
  }
}
