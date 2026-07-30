import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/widgets/form_section_card.dart';
import '../../repositories/exercise_repository.dart';
import '../../repositories/analytics_repository.dart';
import 'workout_detail_screen.dart';

/// Tabbed detail screen for an exercise: Edit | History | Charts
class ExerciseDetailTabsScreen extends StatefulWidget {
  final String exerciseId;
  final String exerciseName;

  const ExerciseDetailTabsScreen({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
  });

  @override
  State<ExerciseDetailTabsScreen> createState() => _ExerciseDetailTabsScreenState();
}

class _ExerciseDetailTabsScreenState extends State<ExerciseDetailTabsScreen>
    with SingleTickerProviderStateMixin {
  final _exerciseRepo = ExerciseRepository();
  final _analyticsRepo = AnalyticsRepository();
  late TabController _tabCtl;

  // Edit form state
  List<Map<String, dynamic>> _categories = [];
  final _nameCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _weightIncrementCtl = TextEditingController();
  final _defaultRestCtl = TextEditingController();
  String _categoryId = 'chest';
  String _type = 'weightReps';
  String _equipment = '';
  bool _formLoading = true;
  bool _isSaving = false;

  // History & charts state
  Map<String, dynamic>? _history;
  bool _historyLoading = true;
  int _chartType = 0;
  static const _chartTypes = ['1RM', 'Max Weight', 'Volume', 'Total Reps'];

  final _types = [
    {'id': 'weightReps', 'icon': Icons.fitness_center_rounded},
    {'id': 'distanceTime', 'icon': Icons.straighten_rounded},
    {'id': 'weightDistance', 'icon': Icons.monitor_weight_rounded},
    {'id': 'weightTime', 'icon': Icons.timer_rounded},
    {'id': 'repsDistance', 'icon': Icons.repeat_rounded},
    {'id': 'repsTime', 'icon': Icons.repeat_one_rounded},
    {'id': 'weightOnly', 'icon': Icons.monitor_weight_outlined},
    {'id': 'repsOnly', 'icon': Icons.repeat_one_on_outlined},
    {'id': 'distanceOnly', 'icon': Icons.straighten_outlined},
    {'id': 'timeOnly', 'icon': Icons.timer_outlined},
  ];

  final _equipmentOptions = ['Barbell', 'Dumbbell', 'Cable', 'Machine', 'Bodyweight', 'Treadmill', 'Stationary', 'Kettlebell', 'Band'];

  @override
  void initState() {
    super.initState();
    _tabCtl = TabController(length: 3, vsync: this);
    _tabCtl.addListener(() {
      if (_tabCtl.indexIsChanging && _tabCtl.index == 1 && _historyLoading) {
        _loadHistory();
      }
      if (_tabCtl.indexIsChanging && _tabCtl.index == 2 && _historyLoading) {
        _loadHistory();
      }
    });
    _loadForm();
  }

  @override
  void dispose() {
    _tabCtl.dispose();
    _nameCtl.dispose();
    _notesCtl.dispose();
    _weightIncrementCtl.dispose();
    _defaultRestCtl.dispose();
    super.dispose();
  }

  Future<void> _loadForm() async {
    _categories = await _exerciseRepo.getCategories();
    final ex = await _exerciseRepo.getExercise(widget.exerciseId);
    if (ex != null && mounted) {
      _nameCtl.text = ex['name'] as String? ?? '';
      _categoryId = ex['category_id'] as String? ?? 'chest';
      _type = ex['type'] as String? ?? 'weightReps';
      _notesCtl.text = ex['notes'] as String? ?? '';
      _equipment = ex['equipment'] as String? ?? '';
      final wi = (ex['weight_increment'] as num?)?.toDouble();
      _weightIncrementCtl.text =
          wi != null ? wi.toStringAsFixed(wi.truncateToDouble() == wi ? 0 : 1) : '';
      final drt = ex['default_rest_time'] as int?;
      _defaultRestCtl.text = drt?.toString() ?? '';
    }
    setState(() => _formLoading = false);
  }

  Future<void> _loadHistory() async {
    final data = await _analyticsRepo.getExerciseHistory(widget.exerciseId, limit: 30);
    if (!mounted) return;
    setState(() {
      _history = data;
      _historyLoading = false;
    });
  }

  Future<void> _save() async {
    if (_nameCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.exerciseFormNameRequired,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final weightInc = double.tryParse(
        _weightIncrementCtl.text.replaceAll(',', '.'),
      );
      final restTime = int.tryParse(_defaultRestCtl.text);
      await _exerciseRepo.updateExercise(
        widget.exerciseId,
        name: _nameCtl.text.trim(),
        categoryId: _categoryId,
        type: _type,
        notes: _notesCtl.text.trim(),
        equipment: _equipment.isEmpty ? null : _equipment,
        weightIncrement: weightInc,
        defaultRestTime: restTime,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonError(e.toString()),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteExercise() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Exercício'),
        content: Text('Tem certeza que deseja excluir "${widget.exerciseName}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await _exerciseRepo.deleteExercise(widget.exerciseId);
      if (mounted) Navigator.pop(context, true);
    }
  }

  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  double _niceInterval(double range) {
    if (range <= 0) return 1;
    final rough = range / 5;
    double magnitude = 1;
    double temp = rough;
    while (temp >= 10) { temp /= 10; magnitude *= 10; }
    while (temp < 1) { temp *= 10; magnitude /= 10; }
    if (temp <= 1) {
      temp = 1;
    } else if (temp <= 2) {
      temp = 2;
    } else if (temp <= 5) {
      temp = 5;
    } else {
      temp = 10;
    }
    return temp * magnitude;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.exerciseName),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteExercise,
            tooltip: 'Excluir',
          ),
        ],
        bottom: TabBar(
          controller: _tabCtl,
          tabs: const [
            Tab(icon: Icon(Icons.edit_outlined), text: 'Editar'),
            Tab(icon: Icon(Icons.history), text: 'Histórico'),
            Tab(icon: Icon(Icons.bar_chart_outlined), text: 'Gráficos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtl,
        children: [
          // Tab 1: Edit Form
          _buildEditTab(theme),
          // Tab 2: History
          _buildHistoryTab(theme),
          // Tab 3: Charts
          _buildChartsTab(theme),
        ],
      ),
    );
  }

  // ===================== TAB 1: EDIT =====================

  Widget _buildEditTab(ThemeData theme) {
    if (_formLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final loc = AppLocalizations.of(context)!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        FormSectionCard(
          icon: Icons.fitness_center_rounded,
          title: loc.exerciseFormSectionBasic,
          children: [
            FormFieldLabel(text: loc.exerciseFormName),
            TextField(
              controller: _nameCtl,
              decoration: InputDecoration(
                hintText: loc.exerciseFormNameHint,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.exerciseFormCategory),
            _buildCategoryPicker(theme),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.exerciseFormType),
            _buildTypePicker(theme),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.exerciseFormEquipment),
            Autocomplete<String>(
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return _equipmentOptions;
                return _equipmentOptions.where(
                  (opt) => opt.toLowerCase().contains(
                        textEditingValue.text.toLowerCase(),
                      ),
                );
              },
              initialValue: TextEditingValue(text: _equipment),
              onSelected: (v) => _equipment = v,
              fieldViewBuilder: (ctx, ctl, focusNode, onSubmit) => TextField(
                controller: ctl,
                focusNode: focusNode,
                decoration: InputDecoration(
                  hintText: loc.exerciseFormEquipmentHint,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor:
                      theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                ),
                onSubmitted: (_) => onSubmit(),
                onChanged: (v) => _equipment = v,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        FormSectionCard(
          icon: Icons.tune_rounded,
          title: loc.exerciseFormSectionDefaults,
          children: [
            FormFieldLabel(text: loc.exerciseFormWeightIncrement),
            TextField(
              controller: _weightIncrementCtl,
              decoration: InputDecoration(
                hintText: loc.exerciseFormWeightIncrementHint,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.exerciseFormDefaultRest),
            TextField(
              controller: _defaultRestCtl,
              decoration: InputDecoration(
                hintText: loc.exerciseFormDefaultRestHint,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            FormFieldLabel(text: loc.exerciseFormNotes),
            TextField(
              controller: _notesCtl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: loc.exerciseFormNotesHint,
                border: const OutlineInputBorder(),
                filled: true,
                fillColor:
                    theme.colorScheme.surfaceContainerHighest.withAlpha(60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _isSaving ? null : _save,
            icon: _isSaving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded),
            label: Text(_isSaving ? 'Salvando...' : loc.exerciseFormSave),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPicker(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final current = _categories.firstWhere(
      (c) => c['id'] == _categoryId,
      orElse: () =>
          {'id': _categoryId, 'name': _categoryId, 'color': 0xFF757575},
    );
    final currentName = ExerciseLocaleHelper.categoryName(loc, current);
    final currentColor = Color(current['color'] as int? ?? 0xFF757575);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: _categories.length,
                itemBuilder: (ctx, i) {
                  final cat = _categories[i];
                  final color = Color(cat['color'] as int? ?? 0xFF757575);
                  final isSelected = cat['id'] == _categoryId;
                  return ListTile(
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      ExerciseLocaleHelper.categoryName(loc, cat),
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, cat['id'] as String),
                  );
                },
              ),
            );
          },
        );
        if (selected != null) {
          setState(() => _categoryId = selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(currentName)),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypePicker(ThemeData theme) {
    final current = _types.firstWhere(
      (t) => t['id'] == _type,
      orElse: () => _types.first,
    );
    final currentName = _exerciseTypeName(current['id'] as String);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: _types.length,
                itemBuilder: (ctx, i) {
                  final t = _types[i];
                  final isSelected = t['id'] == _type;
                  return ListTile(
                    leading: Icon(
                      t['icon'] as IconData,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(_exerciseTypeName(t['id'] as String)),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, t['id'] as String),
                  );
                },
              ),
            );
          },
        );
        if (selected != null) {
          setState(() => _type = selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        ),
        child: Row(
          children: [
            Icon(
              current['icon'] as IconData,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(currentName)),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _exerciseTypeName(String typeId) {
    final loc = AppLocalizations.of(context)!;
    switch (typeId) {
      case 'weightReps':
        return loc.exerciseFormTypeWeightReps;
      case 'distanceTime':
        return loc.exerciseFormTypeDistanceTime;
      case 'weightDistance':
        return loc.exerciseFormTypeWeightDistance;
      case 'weightTime':
        return loc.exerciseFormTypeWeightTime;
      case 'repsDistance':
        return loc.exerciseFormTypeRepsDistance;
      case 'repsTime':
        return loc.exerciseFormTypeRepsTime;
      case 'weightOnly':
        return loc.exerciseFormTypeWeightOnly;
      case 'repsOnly':
        return loc.exerciseFormTypeRepsOnly;
      case 'distanceOnly':
        return loc.exerciseFormTypeDistanceOnly;
      case 'timeOnly':
        return loc.exerciseFormTypeTimeOnly;
      default:
        return typeId;
    }
  }

  // ===================== TAB 2: HISTORY =====================

  Widget _buildHistoryTab(ThemeData theme) {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final history = _history?['history'] as List? ?? [];
    if (history.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
            const SizedBox(height: 16),
            Text('Nenhum treino registrado', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Os treinos com este exercício aparecerão aqui',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final bestWeight = (_history!['best_weight'] as double?) ?? 0;
    final bestVolume = (_history!['best_volume'] as double?) ?? 0;
    final best1RM = (_history!['best_1rm'] as double?) ?? 0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Records cards
          Row(
            children: [
              Expanded(child: _buildRecCard('Peso Máx', bestWeight > 0 ? '${bestWeight.toStringAsFixed(1)} kg' : '--', Icons.monitor_weight, theme.colorScheme.primary, theme)),
              const SizedBox(width: 8),
              Expanded(child: _buildRecCard('Volume', bestVolume > 0 ? '${_formatVolume(bestVolume)} kg' : '--', Icons.auto_graph, theme.colorScheme.secondary, theme)),
              const SizedBox(width: 8),
              Expanded(child: _buildRecCard('1RM', best1RM > 0 ? '${best1RM.toStringAsFixed(1)} kg' : '--', Icons.emoji_events, Colors.amber, theme)),
            ],
          ),
          const SizedBox(height: 20),

          // History table
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('Data', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Peso', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Volume', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('Sets×Reps', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
                Expanded(flex: 2, child: Text('1RM', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold))),
              ],
            ),
          ),
          ...history.reversed.map((h) {
            final date = h['date'] as String? ?? '';
            final maxW = (h['max_weight'] as double?) ?? 0;
            final vol = (h['total_volume'] as double?) ?? 0;
            final sets = (h['total_sets'] as int?) ?? 0;
            final reps = (h['total_reps'] as int?) ?? 0;
            final est1RM = (h['estimated_1rm'] as double?);
            final workoutId = h['workout_id'] as String?;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: InkWell(
                onTap: workoutId != null
                    ? () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => WorkoutDetailScreen(workoutId: workoutId),
                        ),
                      )
                    : null,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text(date.length >= 10 ? date.substring(5) : date,
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                      Expanded(flex: 2, child: Text(maxW > 0 ? maxW.toStringAsFixed(1) : '-',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text(vol > 0 ? vol.toStringAsFixed(0) : '-',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text('$sets×$reps',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text(est1RM != null ? est1RM.toStringAsFixed(1) : '-',
                          style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.amber[700]))),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildRecCard(String label, String value, IconData icon, Color color, ThemeData theme) {
    return Card(
      elevation: 0,
      color: color.withAlpha(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 11)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 9, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ===================== TAB 3: CHARTS =====================

  Widget _buildChartsTab(ThemeData theme) {
    if (_historyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Column(
      children: [
        // Chart type selector
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: List.generate(_chartTypes.length, (i) {
                final isSelected = _chartType == i;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(_chartTypes[i], style: TextStyle(fontSize: 12)),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _chartType = i),
                  ),
                );
              }),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildChartContent(theme)),
      ],
    );
  }

  Widget _buildChartContent(ThemeData theme) {
    final history = _history?['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_chartType) {
      case 0:
        title = 'Evolução do 1RM Estimado';
        values = history.map((h) => (h['estimated_1rm'] as double?) ?? 0).toList();
        break;
      case 1:
        title = 'Evolução do Peso Máximo';
        values = history.map((h) => (h['max_weight'] as double?) ?? 0).toList();
        break;
      case 2:
        title = 'Volume por Treino';
        values = history.map((h) => (h['total_volume'] as double?) ?? 0).toList();
        break;
      case 3:
        title = 'Repetições por Treino';
        values = history.map((h) => (h['total_reps'] as int?)?.toDouble() ?? 0).toList();
        break;
      default:
        return const SizedBox.shrink();
    }

    final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
    final minVal = values.isNotEmpty
        ? values.fold<double>(values.first, (a, b) => a < b ? a : b)
        : 0;

    if (history.isEmpty || maxVal <= 0) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
            const SizedBox(height: 16),
            Text('Nenhum dado disponível', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('Registre treinos com este exercício para ver os gráficos',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      );
    }

    final range = maxVal - minVal;
    final interval = _niceInterval(range);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  Text('${history.length} treinos', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 280,
                child: LineChart(
                  LineChartData(
                    minY: minVal > 0 ? minVal * 0.9 : 0,
                    maxY: maxVal * 1.05,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval: interval,
                      getDrawingHorizontalLine: (value) => FlLine(
                        color: theme.colorScheme.outlineVariant.withAlpha(60),
                        strokeWidth: 1,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 44,
                          interval: interval,
                          getTitlesWidget: (v, _) => Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _chartType == 3 ? v.toInt().toString() : v.toStringAsFixed(1),
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: history.length > 15 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                            final date = history[idx]['date'] as String? ?? '';
                            return Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                date.length >= 10 ? date.substring(5) : date,
                                style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: values.asMap().entries.map((e) =>
                          FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: _chartType == 0
                            ? Colors.amber
                            : _chartType == 2
                                ? theme.colorScheme.secondary
                                : theme.colorScheme.primary,
                        barWidth: 3,
                        dotData: FlDotData(
                          show: history.length <= 30,
                          getDotPainter: (spot, percent, bar, index) =>
                              FlDotCirclePainter(
                                radius: 4,
                                color: _chartType == 0
                                    ? Colors.amber
                                    : _chartType == 2
                                        ? theme.colorScheme.secondary
                                        : theme.colorScheme.primary,
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          color: (_chartType == 0
                              ? Colors.amber
                              : _chartType == 2
                                  ? theme.colorScheme.secondary
                                  : theme.colorScheme.primary).withAlpha(30),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (touchedSpots) => touchedSpots.map((spot) {
                          final idx = spot.spotIndex;
                          final date = idx < history.length
                              ? (history[idx]['date'] as String? ?? '')
                              : '';
                          return LineTooltipItem(
                            '$date\n${spot.y.toStringAsFixed(1)}',
                            TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
