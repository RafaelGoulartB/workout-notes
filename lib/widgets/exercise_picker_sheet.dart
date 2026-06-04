import 'package:flutter/material.dart';
import '../../database/database_helper.dart';

class ExercisePickerSheet extends StatefulWidget {
  const ExercisePickerSheet({super.key});

  @override
  State<ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<ExercisePickerSheet> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _categories = [];
  Map<String, List<Map<String, dynamic>>> _exercisesByCategory = {};
  String? _selectedCategoryId;
  String _search = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _categories = await _db.getCategories();
    
    // Load all exercises grouped by category
    final allExercises = await _db.getExercises();
    for (final cat in _categories) {
      final catId = cat['id'] as String;
      _exercisesByCategory[catId] = allExercises
          .where((e) => e['category_id'] == catId)
          .toList();
    }
    
    setState(() => _isLoading = false);
  }

  List<Map<String, dynamic>> get _filteredExercises {
    if (_selectedCategoryId == null) return [];
    
    final exercises = _exercisesByCategory[_selectedCategoryId] ?? [];
    if (_search.isEmpty) return exercises;
    
    return exercises.where((e) {
      final name = (e['name'] as String? ?? '').toLowerCase();
      return name.contains(_search.toLowerCase());
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredExercises;
    final selectedCategory = _categories.firstWhere(
      (c) => c['id'] == _selectedCategoryId,
      orElse: () => {},
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, scrollCtrl) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Text(
                  'Adicionar Exercício',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_selectedCategoryId != null)
                  TextButton.icon(
                    onPressed: () => setState(() {
                      _selectedCategoryId = null;
                      _search = '';
                    }),
                    icon: const Icon(Icons.arrow_back, size: 18),
                    label: const Text('Voltar'),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            if (_isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_selectedCategoryId == null)
              // Show categories
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _categories.length,
                  itemBuilder: (ctx, i) {
                    final cat = _categories[i];
                    final catId = cat['id'] as String;
                    final exercises = _exercisesByCategory[catId] ?? [];
                    final color = Color(cat['color'] as int? ?? 0xFF757575);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant.withAlpha(80),
                        ),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => setState(() {
                          _selectedCategoryId = catId;
                          _search = '';
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: color.withAlpha(30),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  Icons.fitness_center,
                                  color: color,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      cat['name'] as String? ?? '',
                                      style: theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${exercises.length} exercícios',
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.chevron_right,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              )
            else
              // Show exercises of selected category
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Color(selectedCategory['color'] as int? ?? 0xFF757575).withAlpha(20),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        selectedCategory['name'] as String? ?? '',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Color(selectedCategory['color'] as int? ?? 0xFF757575),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Search
                    TextField(
                      decoration: InputDecoration(
                        hintText: 'Buscar exercício...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                      ),
                      onChanged: (v) => setState(() => _search = v),
                    ),
                    const SizedBox(height: 12),

                    // Exercise list
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                _search.isEmpty
                                    ? 'Nenhum exercício nesta categoria'
                                    : 'Nenhum exercício encontrado',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollCtrl,
                              itemCount: filtered.length,
                              itemBuilder: (ctx, i) {
                                final ex = filtered[i];
                                final catColor = Color(selectedCategory['color'] as int? ?? 0xFF757575);
                                return ListTile(
                                  leading: Container(
                                    width: 8,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: catColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  title: Text(ex['name'] as String),
                                  subtitle: ex['equipment'] != null && (ex['equipment'] as String).isNotEmpty
                                      ? Text(ex['equipment'] as String)
                                      : null,
                                  trailing: Icon(
                                    Icons.add_circle_outline,
                                    color: theme.colorScheme.primary,
                                  ),
                                  onTap: () => Navigator.pop(context, ex),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
