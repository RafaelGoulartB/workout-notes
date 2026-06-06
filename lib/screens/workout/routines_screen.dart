import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
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
        title: Text(AppLocalizations.of(context)!.routinesNew),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.routinesName,
            border: OutlineInputBorder(),
            hintText: AppLocalizations.of(context)!.routinesNameHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () async {
            if (ctl.text.trim().isNotEmpty) {
              await _db.createRoutine(ctl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            }
          }, child: Text(AppLocalizations.of(context)!.routinesCreate)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.routinesTitle),
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
                        Text(AppLocalizations.of(context)!.routinesEmptyTitle, style: theme.textTheme.titleLarge),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.routinesEmptySubtitle,
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: _createRoutine,
                          icon: const Icon(Icons.add),
                          label: Text(AppLocalizations.of(context)!.routinesCreate),
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
        label: Text(AppLocalizations.of(context)!.routinesNew),
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
        title: Text(AppLocalizations.of(context)!.routinesNewDay),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.routinesDayName,
            border: const OutlineInputBorder(),
            hintText: AppLocalizations.of(context)!.routinesDayNameHint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () async {
            if (ctl.text.trim().isNotEmpty) {
              await _db.addRoutineDay(widget.routineId, ctl.text.trim());
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            }
          }, child: Text(AppLocalizations.of(context)!.routinesAddDay)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_routine?['name'] as String? ?? AppLocalizations.of(context)!.routinesTitle),
        centerTitle: true,
        actions: [
          PopupMenuButton(
            itemBuilder: (ctx) => [
              PopupMenuItem(value: 'rename', child: Text(AppLocalizations.of(context)!.routinesRename)),
              PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context)!.routinesDelete)),
            ],
            onSelected: (v) async {
              if (v == 'rename') {
                final ctl = TextEditingController(text: _routine?['name'] as String? ?? '');
                final name = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.routinesRename),
                    content: TextField(
                      controller: ctl, autofocus: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
                      FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(AppLocalizations.of(context)!.commonSave)),
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
                    title: Text(AppLocalizations.of(context)!.routinesDeleteConfirm(_routine?['name'] ?? '')),
                    content: Text(AppLocalizations.of(context)!.commonActionCannotBeUndone),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(AppLocalizations.of(context)!.commonCancel)),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(AppLocalizations.of(context)!.commonDelete), style: TextButton.styleFrom(foregroundColor: Colors.red)),
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
                        Text(AppLocalizations.of(context)!.routinesDayEmpty, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(AppLocalizations.of(context)!.routinesDayEmptySubtitle, style: theme.textTheme.bodySmall),
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
                      onChanged: _load,
                    ),
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDay,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.routinesAddDay),
      ),
    );
  }
}

class _DayCard extends StatefulWidget {
  final Map<String, dynamic> day;
  final DatabaseHelper db;
  final VoidCallback onChanged;

  const _DayCard({
    super.key,
    required this.day, required this.db,
    required this.onChanged,
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

  void _changeRestTime(Map<String, dynamic> exercise) {
    final currentRest = (exercise['rest_time_seconds'] as int?) ?? 90;
    final exId = exercise['id'] as String;
    final presets = [30, 60, 90, 120, 180];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(80),
              borderRadius: BorderRadius.circular(2),
            ))),
            const SizedBox(height: 16),
            Text(AppLocalizations.of(context)!.routinesRestTimeTitle, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...presets.map((sec) => ChoiceChip(
                  label: Text(sec >= 60 ? '${sec ~/ 60}min${sec % 60}s' : '${sec}s'),
                  selected: currentRest == sec,
                  onSelected: (_) {
                    widget.db.updateRoutineExerciseRestTime(exId, sec);
                    _load();
                    Navigator.pop(ctx);
                  },
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExercisePicker() async {
    final currentExerciseIds = _exercises.map((e) => e['exercise_id'] as String).toSet();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      useSafeArea: true,
      builder: (_) => ExercisePickerSheet(
        currentExerciseIds: currentExerciseIds,
        onExerciseAdded: (exercise) async {
          await widget.db.addRoutineExercise(
            widget.day['id'] as String,
            exercise['id'] as String,
            restTimeSeconds: (exercise['default_rest_time'] as int?),
          );
          _load();
        },
        onExerciseRemoved: (exercise) async {
          final exerciseId = exercise['id'] as String;
          // Find the routine exercise entry and remove it
          final routineExercise = _exercises.firstWhere(
            (e) => e['exercise_id'] == exerciseId,
            orElse: () => <String, dynamic>{},
          );
          if (routineExercise.isNotEmpty) {
            await widget.db.removeRoutineExercise(routineExercise['id'] as String);
            _load();
          }
        },
      ),
    );
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
                    PopupMenuItem(value: 'rename', child: Text(AppLocalizations.of(context)!.routinesRename)),
                    PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context)!.routinesDeleteDay)),
                  ],
                  onSelected: (v) async {
                    if (v == 'rename') {
                      final ctl = TextEditingController(text: widget.day['name'] as String? ?? '');
                      final name = await showDialog<String>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(AppLocalizations.of(context)!.routinesRename),
                          content: TextField(controller: ctl, autofocus: true, decoration: const InputDecoration(border: OutlineInputBorder())),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
                            FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(AppLocalizations.of(context)!.commonSave)),
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
                child: Text(AppLocalizations.of(context)!.routinesNoExercises, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
                      onTap: () => _changeRestTime(ex),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.timer_outlined, size: 12, color: theme.colorScheme.primary),
                            const SizedBox(width: 2),
                            Text('${ex['rest_time_seconds'] ?? 90}s',
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 11)),
                          ],
                        ),
                      ),
                    ),
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
              onPressed: _openExercisePicker,
              icon: const Icon(Icons.add, size: 18),
              label: Text(AppLocalizations.of(context)!.routinesAddExercise),
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
            ),
          ],
        ),
      ),
    );
  }
}
