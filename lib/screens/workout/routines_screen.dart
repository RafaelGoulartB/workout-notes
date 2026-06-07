import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../repositories/routine_repository.dart';
import 'routine_day_editor_screen.dart';

class RoutinesScreen extends StatefulWidget {
  const RoutinesScreen({super.key});

  @override
  State<RoutinesScreen> createState() => _RoutinesScreenState();
}

class _RoutinesScreenState extends State<RoutinesScreen> {
  final _routineRepo = RoutineRepository();
  List<Map<String, dynamic>> _routines = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _routines = await _routineRepo.getRoutines();
    setState(() => _isLoading = false);
  }

  void _createRoutine() {
    final nameCtl = TextEditingController();
    final notesCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.routinesNew),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.routinesName,
                border: OutlineInputBorder(),
                hintText: AppLocalizations.of(context)!.routinesNameHint,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notesCtl,
              decoration: InputDecoration(
                labelText: AppLocalizations.of(context)!.routinesNotes,
                border: OutlineInputBorder(),
                hintText: AppLocalizations.of(context)!.routinesNotesHint,
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
          FilledButton(onPressed: () async {
            if (nameCtl.text.trim().isNotEmpty) {
              await _routineRepo.createRoutine(nameCtl.text.trim(), notes: notesCtl.text.trim().isEmpty ? null : notesCtl.text.trim());
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
  final _routineRepo = RoutineRepository();
  Map<String, dynamic>? _routine;
  List<Map<String, dynamic>> _days = [];
  bool _isLoading = true;
  bool _dashboardLoading = false;
  _RoutineDashboardData? _dashboard;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _routine = await _routineRepo.getRoutine(widget.routineId);
      _days = await _routineRepo.getRoutineDays(widget.routineId);
    } catch (_) {
      // Gracefully handle errors
    }
    setState(() {
      _isLoading = false;
    });
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    if (_days.isEmpty) {
      setState(() => _dashboard = null);
      return;
    }
    setState(() => _dashboardLoading = true);

    try {
      final loc = AppLocalizations.of(context)!;
      final perDay = <String, List<_DayStat>>{};
      final perCategory = <String, _RoutineCatStat>{};

      for (final day in _days) {
        final dayId = day['id'] as String;
        final exercises =
            await _routineRepo.getRoutineExercises(dayId);
        final dayStats = <_DayStat>[];

        for (final ex in exercises) {
          final catId =
              ex['category_id'] as String? ?? '';
          final catName = ExerciseLocaleHelper.categoryName(loc, ex);
          final colorVal =
              ex['category_color'] as int? ?? 0xFF757575;
          final exerciseType =
              ex['exercise_type'] as String? ?? 'weightReps';
          final sets = await _routineRepo.getPredefinedSets(
              ex['id'] as String);

          int catSets = 0;
          double catVolume = 0;
          for (final s in sets) {
            if ((s['is_warmup'] as int?) == 1) continue;
            catSets++;
            dayStats.add(_DayStat(
              categoryId: catId,
              categoryName: catName,
              color: Color(colorVal),
              sets: 1,
              volume: exerciseType == 'weightReps'
                  ? ((s['weight'] as num?)?.toDouble() ?? 0) *
                      ((s['reps'] as int?) ?? 0)
                  : 0,
            ));
          }

          perCategory.putIfAbsent(
              catId,
              () => _RoutineCatStat(
                  name: catName, color: Color(colorVal)));
          perCategory[catId]!.sets += catSets;
          perCategory[catId]!.volume += catVolume;
        }

        perDay[dayId] = dayStats;
      }

      setState(() {
        _dashboard = _RoutineDashboardData(
          perDay: perDay,
          perCategory: perCategory,
        );
        _dashboardLoading = false;
      });
    } catch (_) {
      setState(() {
        _dashboard = null;
        _dashboardLoading = false;
      });
    }
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
              await _routineRepo.addRoutineDay(widget.routineId, ctl.text.trim());
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
              PopupMenuItem(value: 'edit', child: Text(AppLocalizations.of(context)!.routinesEdit)),
              PopupMenuItem(value: 'delete', child: Text(AppLocalizations.of(context)!.routinesDelete)),
            ],
            onSelected: (v) async {
              if (v == 'edit') {
                final nameCtl = TextEditingController(text: _routine?['name'] as String? ?? '');
                final notesCtl = TextEditingController(text: _routine?['notes'] as String? ?? '');
                final result = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(AppLocalizations.of(context)!.routinesEdit),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: nameCtl, autofocus: true,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.routinesName,
                            border: const OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: notesCtl,
                          decoration: InputDecoration(
                            labelText: AppLocalizations.of(context)!.routinesNotes,
                            border: OutlineInputBorder(),
                            hintText: AppLocalizations.of(context)!.routinesNotesHint,
                          ),
                          maxLines: 3,
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: Text(AppLocalizations.of(context)!.commonCancel)),
                      FilledButton(onPressed: () {
                        final name = nameCtl.text.trim();
                        if (name.isNotEmpty) {
                          Navigator.pop(ctx, {'name': name, 'notes': notesCtl.text.trim()});
                        }
                      }, child: Text(AppLocalizations.of(context)!.commonSave)),
                    ],
                  ),
                );
                if (result != null) {
                  await _routineRepo.updateRoutine(widget.routineId, name: result['name'], notes: result['notes']);
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
                      TextButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        label: Text(AppLocalizations.of(context)!.commonDelete),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _routineRepo.deleteRoutine(widget.routineId);
                  if (!mounted) return;
                  if (!context.mounted) return;
                  Navigator.pop(context, true);
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
                    itemCount: _days.length + 1,
                    itemBuilder: (ctx, i) {
                      if (i == 0) return _buildRoutineDashboard(theme);
                      return _buildDayCard(_days[i - 1], theme);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addDay,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.routinesAddDay),
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> day, ThemeData theme) {
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
              builder: (_) => RoutineDayEditorScreen(
                routineDayId: day['id'] as String,
                routineId: widget.routineId,
                dayName: day['name'] as String? ?? 'Dia',
              ),
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
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.today, color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(day['name'] as String? ?? 'Dia',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoutineDashboard(ThemeData theme) {
    if (_dashboardLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    final dash = _dashboard;
    if (dash == null) return const SizedBox.shrink();

    final cats = dash.perCategory.values.toList()..sort((a, b) => b.sets.compareTo(a.sets));
    final totalSets = cats.fold<int>(0, (a, c) => a + c.sets);
    final totalVolume = cats.fold<double>(0, (a, c) => a + c.volume);
    final daysCount = _days.length;
    final maxSets = cats.isEmpty ? 1 : cats.first.sets;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.analytics_outlined, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(AppLocalizations.of(context)!.routinesWeeklyView,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (_dashboardLoading)
                    const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 4),
              Text('${AppLocalizations.of(context)!.routinesWeeklyDays(daysCount)} · '
                  '${AppLocalizations.of(context)!.routinesDaySets(totalSets)}' +
                  (totalVolume > 0
                      ? ' · ${AppLocalizations.of(context)!.routinesWeeklyVolume(totalVolume.toStringAsFixed(0))}'
                      : ''),
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),

              // Per-category bars
              ...cats.map((cat) {
                final pct = maxSets > 0 ? cat.sets / maxSets : 0.0;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(width: 10, height: 10,
                              decoration: BoxDecoration(color: cat.color, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Expanded(child: Text(cat.name,
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                          Text('${cat.sets}s',
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                          if (cat.volume > 0) ...[
                            const SizedBox(width: 4),
                            Text('${cat.volume.toStringAsFixed(0)}kg',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                          const SizedBox(width: 4),
                          Text('${(cat.sets / totalSets * 100).round()}%',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.primary, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: pct.clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                          valueColor: AlwaysStoppedAnimation<Color>(cat.color.withAlpha(200)),
                        ),
                      ),
                    ],
                  ),
                );
              }),

              // Per-day mini summary
              if (_days.length > 1) ...[
                const Divider(height: 16),
                Text(AppLocalizations.of(context)!.routinesPerDay,
                    style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                ..._days.map((day) {
                  final dayId = day['id'] as String;
                  final dayName = day['name'] as String? ?? 'Dia';
                  final dayStats = dash.perDay[dayId] ?? [];
                  final daySets = dayStats.fold<int>(0, (a, s) => a + s.sets);
                  final dayVol = dayStats.fold<double>(0, (a, s) => a + s.volume);
                  // Unique categories
                  final dayCats = dayStats.map((s) => s.categoryName).toSet().length;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Icon(Icons.today, size: 12, color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(dayName,
                              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                        ),
                        Text(AppLocalizations.of(context)!.routinesDaySets(daySets),
                            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                        if (dayVol > 0) ...[
                          const SizedBox(width: 4),
                          Text('· ${dayVol.toStringAsFixed(0)}kg',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant)),
                        ],
                        const SizedBox(width: 4),
                        Text(AppLocalizations.of(context)!.routinesDayGroups(dayCats),
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Data for the weekly routine dashboard.
class _RoutineDashboardData {
  final Map<String, List<_DayStat>> perDay;
  final Map<String, _RoutineCatStat> perCategory;

  _RoutineDashboardData({required this.perDay, required this.perCategory});
}

/// Per-category stat for the routine dashboard.
class _RoutineCatStat {
  final String name;
  final Color color;
  int sets = 0;
  double volume = 0;

  _RoutineCatStat({required this.name, required this.color});
}

/// Stat for a single exercise entry within a day.
class _DayStat {
  final String categoryId;
  final String categoryName;
  final Color color;
  final int sets;
  final double volume;

  _DayStat({
    required this.categoryId,
    required this.categoryName,
    required this.color,
    required this.sets,
    required this.volume,
  });
}