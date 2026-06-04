import 'package:flutter/material.dart';
import '../../database/database_helper.dart';
import '../../widgets/exercise_picker_sheet.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _routines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _routines = await _db.getRoutines();
    setState(() => _isLoading = false);
  }

  void _createRoutine() {
    final ctl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova Rotina'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome da Rotina',
            border: OutlineInputBorder(),
            hintText: 'Ex: Push Pull Legs',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            if (ctl.text.trim().isNotEmpty) {
              await _db.createRoutine(ctl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            }
          }, child: const Text('Criar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotinas'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _routines.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.repeat, size: 80, color: theme.colorScheme.primary.withAlpha(80)),
                        const SizedBox(height: 24),
                        Text('Nenhuma rotina ainda', style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text('Crie uma rotina para treinar mais rápido',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _createRoutine,
                          icon: const Icon(Icons.add),
                          label: const Text('Criar Rotina'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
                    itemCount: _routines.length,
                    itemBuilder: (ctx, i) {
                      final routine = _routines[i];
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
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
                                builder: (_) => RoutineFormScreen(routineId: routine['id'] as String),
                              ),
                            );
                            if (result == true) _load();
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.secondaryContainer,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.repeat, color: theme.colorScheme.onSecondaryContainer),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(routine['name'] as String, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                      if (routine['notes'] != null && (routine['notes'] as String).isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(routine['notes'] as String, style: theme.textTheme.bodySmall),
                                      ],
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createRoutine,
        icon: const Icon(Icons.add),
        label: const Text('Nova Rotina'),
      ),
    );
  }
}

class RoutineFormScreen extends StatefulWidget {
  final String routineId;
  const RoutineFormScreen({super.key, required this.routineId});

  @override
  State<RoutineFormScreen> createState() => _RoutineFormScreenState();
}

class _RoutineFormScreenState extends State<RoutineFormScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, dynamic>? _routine;
  List<Map<String, dynamic>> _days = [];
  bool _isLoading = true;
  int _refreshKey = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _routine = await _db.getRoutine(widget.routineId);
    _days = await _db.getRoutineDays(widget.routineId);
    setState(() {
      _isLoading = false;
      _refreshKey++;
    });
  }

  void _addDay() {
    final ctl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo Dia'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Nome do Dia',
            border: OutlineInputBorder(),
            hintText: 'Ex: Push Day, Segunda-Feira',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            if (ctl.text.trim().isNotEmpty) {
              await _db.addRoutineDay(widget.routineId, ctl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            }
          }, child: const Text('Adicionar')),
        ],
      ),
    );
  }

  void _addExerciseToDay(String dayId) async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const ExercisePickerSheet(),
    );
    if (selected != null) {
      await _db.addRoutineExercise(dayId, selected['id'] as String);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_routine?['name'] as String? ?? 'Rotina'),
        centerTitle: true,
        actions: [
          PopupMenuButton(
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'rename', child: Text('Renomear')),
              const PopupMenuItem(value: 'delete', child: Text('Excluir Rotina')),
            ],
            onSelected: (v) async {
              if (v == 'rename') {
                final ctl = TextEditingController(text: _routine?['name'] as String? ?? '');
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Renomear'),
                    content: TextField(
                      controller: ctl, autofocus: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Salvar')),
                    ],
                  ),
                );
                if (name != null && name.isNotEmpty) {
                  await _db.updateRoutine(widget.routineId, name: name);
                  _load();
                }
              } else if (v == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Excluir Rotina?'),
                    content: const Text('Esta ação não pode ser desfeita.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _db.deleteRoutine(widget.routineId);
                  if (mounted) Navigator.pop(context, true);
                }
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _days.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.today, size: 64, color: theme.colorScheme.primary.withAlpha(80)),
                        const SizedBox(height: 16),
                        Text('Nenhum dia ainda', style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('Adicione dias para sua rotina', style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 100),
                    itemCount: _days.length,
                    itemBuilder: (ctx, i) => _DayCard(
                      key: ValueKey('day_${_days[i]['id']}_$_refreshKey'),
                      day: _days[i],
                      db: _db,
                      onAddExercise: () => _addExerciseToDay(_days[i]['id'] as String),
                      onChanged: _load,
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDay,
        icon: const Icon(Icons.add),
        label: const Text('Adicionar Dia'),
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  final Map<String, dynamic> day;
  final DatabaseHelper db;
  final VoidCallback onAddExercise;
  final VoidCallback onChanged;

  const _DayCard({
    super.key,
    required this.day, required this.db,
    required this.onAddExercise, required this.onChanged,
  });

  @override
  State<_DayCard> createState() => _DayCardState();
}

class _DayCardState extends State<_DayCard> {
  List<Map<String, dynamic>> _exercises = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _exercises = await widget.db.getRoutineExercises(widget.day['id'] as String);
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.day['name'] as String? ?? 'Dia', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                PopupMenuButton(
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: 'rename', child: Text('Renomear')),
                    const PopupMenuItem(value: 'delete', child: Text('Excluir Dia')),
                  ],
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final ctl = TextEditingController(text: widget.day['name'] as String? ?? '');
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Renomear'),
                          content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
                            FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Salvar')),
                          ],
                        ),
                      );
                      if (name != null && name.isNotEmpty) {
                        await widget.db.updateRoutine(widget.day['routine_id'] as String, name: name);
                        widget.onChanged();
                      }
                    } else if (v == 'delete') {
                      await widget.db.deleteRoutineDay(widget.day['id'] as String);
                      widget.onChanged();
                    }
                  },
                ),
              ],
            ),
            if (_isLoading)
              const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
            else if (_exercises.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Nenhum exercício adicionado', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              )
            else ...[
              ..._exercises.map((ex) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(width: 4, height: 16, decoration: BoxDecoration(
                      color: Color(ex['category_color'] as int? ?? 0xFF757575),
                      borderRadius: BorderRadius.circular(2),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: Text(ex['exercise_name'] as String? ?? '', style: theme.textTheme.bodyMedium)),
                    GestureDetector(
                      onTap: () async {
                        await widget.db.removeRoutineExercise(ex['id'] as String);
                        _load();
                      },
                      child: Icon(Icons.close, size: 16, color: theme.colorScheme.error.withAlpha(180)),
                    ),
                  ],
                ),
              )),
            ],
            TextButton.icon(
              onPressed: widget.onAddExercise,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar Exercício'),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }
}
