import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../database/database_helper.dart';
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
  final _db = DatabaseHelper.instance;
  late TabController _tabCtl;

  // Edit form state
  List<Map<String, dynamic>> _categories = [];
  final _nameCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  String _categoryId = 'chest';
  String _type = 'weightReps';
  String _equipment = '';
  double? _weightIncrement;
  int? _defaultRestTime;
  bool _formLoading = true;
  bool _isSaving = false;

  // History & charts state
  Map<String, dynamic>? _history;
  bool _historyLoading = true;
  int _chartType = 0;
  static const _chartTypes = ['1RM', 'Max Weight', 'Volume', 'Total Reps'];

  final _types = [
    {'id': 'weightReps', 'name': 'Peso × Repetições', 'icon': Icons.fitness_center},
    {'id': 'distanceTime', 'name': 'Distância × Tempo', 'icon': Icons.straighten},
    {'id': 'weightDistance', 'name': 'Peso × Distância', 'icon': Icons.monitor_weight},
    {'id': 'weightTime', 'name': 'Peso × Tempo', 'icon': Icons.timer},
    {'id': 'repsDistance', 'name': 'Repetições × Distância', 'icon': Icons.repeat},
    {'id': 'repsTime', 'name': 'Repetições × Tempo', 'icon': Icons.repeat_one},
    {'id': 'weightOnly', 'name': 'Apenas Peso', 'icon': Icons.monitor_weight_outlined},
    {'id': 'repsOnly', 'name': 'Apenas Repetições', 'icon': Icons.repeat_one_on},
    {'id': 'distanceOnly', 'name': 'Apenas Distância', 'icon': Icons.straighten},
    {'id': 'timeOnly', 'name': 'Apenas Tempo', 'icon': Icons.timer_outlined},
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
    super.dispose();
  }

  Future<void> _loadForm() async {
    _categories = await _db.getCategories();
    final ex = await _db.getExercise(widget.exerciseId);
    if (ex != null && mounted) {
      _nameCtl.text = ex['name'] as String? ?? '';
      _categoryId = ex['category_id'] as String? ?? 'chest';
      _type = ex['type'] as String? ?? 'weightReps';
      _notesCtl.text = ex['notes'] as String? ?? '';
      _equipment = ex['equipment'] as String? ?? '';
      _weightIncrement = (ex['weight_increment'] as num?)?.toDouble();
      _defaultRestTime = ex['default_rest_time'] as int?;
    }
    setState(() => _formLoading = false);
  }

  Future<void> _loadHistory() async {
    final data = await _db.getExerciseHistory(widget.exerciseId, limit: 30);
    if (!mounted) return;
    setState(() {
      _history = data;
      _historyLoading = false;
    });
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
      await _db.updateExercise(widget.exerciseId,
        name: _nameCtl.text.trim(),
        categoryId: _categoryId,
        type: _type,
        notes: _notesCtl.text.trim(),
        equipment: _equipment.isEmpty ? null : _equipment,
        weightIncrement: _weightIncrement,
        defaultRestTime: _defaultRestTime,
      );
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
      await _db.deleteExercise(widget.exerciseId);
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
    if (temp <= 1) temp = 1;
    else if (temp <= 2) temp = 2;
    else if (temp <= 5) temp = 5;
    else temp = 10;
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
    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameCtl,
                decoration: const InputDecoration(
                  labelText: 'Nome do Exercício',
                  border: OutlineInputBorder(),
                  hintText: 'Ex: Supino Inclinado',
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 16),
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
                      Text(ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, cat)),
                    ],
                  ),
                )).toList(),
                onChanged: (v) => setState(() => _categoryId = v ?? _categoryId),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _types.any((t) => t['id'] == _type) ? _type : 'weightReps',
                decoration: const InputDecoration(
                  labelText: 'Tipo',
                  border: OutlineInputBorder(),
                ),
                items: _types.map((t) => DropdownMenuItem<String>(
                  value: t['id'] as String,
                  child: Row(
                    children: [
                      Icon(t['icon'] as IconData, size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(t['name'] as String),
                    ],
                  ),
                )).toList(),
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 16),
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
              TextField(
                controller: _notesCtl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Instruções / Dicas (opcional)',
                  border: OutlineInputBorder(),
                  hintText: 'Dicas de execução, forma correta...',
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save),
                  label: Text(_isSaving ? 'Salvando...' : 'Salvar Alterações'),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ],
    );
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
                      Expanded(flex: 2, child: Text(maxW > 0 ? '${maxW.toStringAsFixed(1)}' : '-',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text(vol > 0 ? '${vol.toStringAsFixed(0)}' : '-',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text('$sets×$reps',
                          style: theme.textTheme.bodySmall)),
                      Expanded(flex: 2, child: Text(est1RM != null ? '${est1RM.toStringAsFixed(1)}' : '-',
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
                              _chartType == 3 ? '${v.toInt()}' : '${v.toStringAsFixed(1)}',
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
