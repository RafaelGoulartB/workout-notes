import 'package:flutter/material.dart';
import '../../database/database_helper.dart';

class ExerciseFormScreen extends StatefulWidget {
  final String? exerciseId;
  const ExerciseFormScreen({super.key, this.exerciseId});

  @override
  State<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends State<ExerciseFormScreen> {
  final _db = DatabaseHelper.instance;
  final _nameCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  String _categoryId = 'chest';
  String _type = 'weightReps';
  String _equipment = '';
  double? _weightIncrement;
  int? _defaultRestTime;
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool get _isEditing => widget.exerciseId != null;

  final _types = [
    {'id': 'weightReps', 'name': 'Peso × Repetições'},
    {'id': 'distanceTime', 'name': 'Distância × Tempo'},
    {'id': 'weightOnly', 'name': 'Apenas Peso'},
    {'id': 'repsOnly', 'name': 'Apenas Repetições'},
    {'id': 'timed', 'name': 'Cronometrado'},
  ];

  final _equipmentOptions = ['Barbell', 'Dumbbell', 'Cable', 'Machine', 'Bodyweight', 'Treadmill', 'Stationary', 'Kettlebell', 'Band'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _categories = await _db.getCategories();
    if (_isEditing) {
      final ex = await _db.getExercise(widget.exerciseId!);
      if (ex != null) {
        _nameCtl.text = ex['name'] as String? ?? '';
        _categoryId = ex['category_id'] as String? ?? 'chest';
        _type = ex['type'] as String? ?? 'weightReps';
        _notesCtl.text = ex['notes'] as String? ?? '';
        _equipment = ex['equipment'] as String? ?? '';
        _weightIncrement = (ex['weight_increment'] as num?)?.toDouble();
        _defaultRestTime = ex['default_rest_time'] as int?;
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (_nameCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nome é obrigatório'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await _db.updateExercise(widget.exerciseId!, name: _nameCtl.text.trim(),
          categoryId: _categoryId, type: _type, notes: _notesCtl.text.trim(),
          equipment: _equipment.isEmpty ? null : _equipment,
          weightIncrement: _weightIncrement, defaultRestTime: _defaultRestTime);
      } else {
        await _db.addExercise(name: _nameCtl.text.trim(), categoryId: _categoryId,
          type: _type, notes: _notesCtl.text.trim(),
          equipment: _equipment.isEmpty ? null : _equipment,
          weightIncrement: _weightIncrement, defaultRestTime: _defaultRestTime);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Editar Exercício' : 'Novo Exercício'),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  TextField(
                    controller: _nameCtl,
                    decoration: const InputDecoration(
                      labelText: 'Nome do Exercício',
                      border: OutlineInputBorder(),
                      hintText: 'Ex: Supino Inclinado',
                    ),
                    textCapitalization: TextCapitalization.words,
                    autofocus: !_isEditing,
                  ),
                  const SizedBox(height: 16),

                  // Category
                  DropdownButtonFormField<String>(
                    value: _categoryId,
                    decoration: const InputDecoration(
                      labelText: 'Grupo Muscular',
                      border: OutlineInputBorder(),
                    ),
                    items: _categories.map((cat) => DropdownMenuItem(
                      value: cat['id'] as String,
                      child: Row(
                        children: [
                          Container(width: 12, height: 12, decoration: BoxDecoration(
                            color: Color(cat['color'] as int), shape: BoxShape.circle,
                          )),
                          const SizedBox(width: 8),
                          Text(cat['name'] as String),
                        ],
                      ),
                    )).toList(),
                    onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
                  ),
                  const SizedBox(height: 16),

                  // Type
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: _types.map((t) => DropdownMenuItem(
                      value: t['id'],
                      child: Text(t['name'] as String),
                    )).toList(),
                    onChanged: (v) => setState(() => _type = v ?? _type),
                  ),
                  const SizedBox(height: 16),

                  // Equipment
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return _equipmentOptions;
                      return _equipmentOptions.where((opt) =>
                        opt.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    initialValue: TextEditingValue(text: _equipment),
                    onSelected: (v) => _equipment = v,
                    fieldViewBuilder: (ctx, ctl, focusNode, onSubmit) => TextField(
                      controller: ctl,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Equipamento (opcional)',
                        border: OutlineInputBorder(),
                        hintText: 'Barbell, Dumbbell, Machine...',
                      ),
                      onSubmitted: (_) => onSubmit(),
                      onChanged: (v) => _equipment = v,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Weight increment
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Incremento de Peso (kg)',
                      border: OutlineInputBorder(),
                      hintText: 'Ex: 2.5',
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _weightIncrement?.toStringAsFixed(1) ?? ''),
                    onChanged: (v) => _weightIncrement = double.tryParse(v.replaceAll(',', '.')),
                  ),
                  const SizedBox(height: 16),

                  // Default rest time
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Descanso Padrão (segundos)',
                      border: OutlineInputBorder(),
                      hintText: 'Ex: 90',
                    ),
                    keyboardType: TextInputType.number,
                    controller: TextEditingController(
                      text: _defaultRestTime?.toString() ?? ''),
                    onChanged: (v) => _defaultRestTime = int.tryParse(v),
                  ),
                  const SizedBox(height: 16),

                  // Notes
                  TextField(
                    controller: _notesCtl,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Instruções / Dicas (opcional)',
                      border: OutlineInputBorder(),
                      hintText: 'Dicas de execução, forma correta...',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
