import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../database/database_helper.dart';

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});

  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  final _db = DatabaseHelper.instance;
  final _searchCtl = TextEditingController();
  
  bool _isLoading = true;
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _exercisesWithData = [];
  Map<String, dynamic>? _selectedHistory;
  int _selectedChartType = 0;

  static const _chartTypes = ['1RM', 'Peso Máx.', 'Volume', 'Total Reps'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _allExercises = await _db.getExercises();

    // Find exercises that have recorded data
    final withData = <Map<String, dynamic>>[];
    for (final ex in _allExercises) {
      final data = await _db.getExerciseHistory(ex['id'] as String, limit: 1);
      final history = data['history'] as List? ?? [];
      if (history.isNotEmpty) {
        withData.add(ex);
      }
    }
    _exercisesWithData = withData;

    // Auto-select first exercise with data
    if (withData.isNotEmpty) {
      await _loadHistory(withData.first['id'] as String);
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadHistory(String exerciseId) async {
    final data = await _db.getExerciseHistory(exerciseId, limit: 30);
    setState(() => _selectedHistory = data);
  }

  List<Map<String, dynamic>> get _filteredExercises {
    final query = _searchCtl.text.toLowerCase();
    if (query.isEmpty) return _exercisesWithData;
    return _exercisesWithData.where((e) =>
      (e['name'] as String).toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Progresso'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _exercisesWithData.isEmpty
              ? _buildNoDataState(theme)
              : Column(
                  children: [
                    // Exercise search
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: TextField(
                        controller: _searchCtl,
                        decoration: InputDecoration(
                          hintText: 'Buscar exercício...',
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),

                    // Selected exercise + chart type
                    if (_selectedHistory != null) ...[
                      _buildExerciseSelector(theme),
                      const SizedBox(height: 4),
                      _buildChartTypeSelector(theme),
                    ],

                    // Content
                    Expanded(
                      child: _selectedHistory == null
                          ? _buildExerciseList(theme)
                          : SingleChildScrollView(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildRecords(theme),
                                  const SizedBox(height: 16),
                                  _buildChart(theme),
                                  const SizedBox(height: 16),
                                  _buildHistorySection(theme),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildNoDataState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.trending_up, size: 80, color: theme.colorScheme.primary.withAlpha(80)),
            const SizedBox(height: 24),
            Text('Nenhum dado ainda', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Text(
              'Registre alguns treinos para ver\ngráficos de progresso e estatísticas',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseSelector(ThemeData theme) {
    final selectedEx = _allExercises.firstWhere(
      (e) => e['id'] == (_selectedHistory?['exercise_id']),
      orElse: () => <String, dynamic>{},
    );
    final currName = selectedEx['name'] as String? ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              value: selectedEx['id'] as String?,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              isExpanded: true,
              items: _allExercises.map((ex) => DropdownMenuItem(
                value: ex['id'] as String,
                child: Row(
                  children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(
                      color: Color(ex['category_color'] as int? ?? 0xFF757575),
                      shape: BoxShape.circle,
                    )),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        ex['name'] as String? ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: _exercisesWithData.any((d) => d['id'] == ex['id'])
                              ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              )).toList(),
              onChanged: (id) {
                if (id != null) _loadHistory(id);
              },
            ),
          ),
          if (_selectedHistory != null) ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () {
                setState(() => _selectedHistory = null);
                _searchCtl.clear();
              },
              tooltip: 'Voltar para lista',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChartTypeSelector(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: 36,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: List.generate(_chartTypes.length, (i) {
            final isSelected = _selectedChartType == i;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_chartTypes[i], style: TextStyle(fontSize: 12)),
                selected: isSelected,
                onSelected: (_) => setState(() => _selectedChartType = i),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildExerciseList(ThemeData theme) {
    final filtered = _filteredExercises;

    if (filtered.isEmpty) {
      return Center(
        child: Text('Nenhum exercício encontrado',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
      itemCount: filtered.length,
      itemBuilder: (ctx, i) {
        final ex = filtered[i];
        final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 3),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _loadHistory(ex['id'] as String),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(width: 6, height: 40, decoration: BoxDecoration(
                    color: catColor, borderRadius: BorderRadius.circular(3),
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(ex['name'] as String, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        Text(ex['category_name'] as String? ?? '', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
    );
  }

  Widget _buildRecords(ThemeData theme) {
    final bestWeight = (_selectedHistory!['best_weight'] as double?) ?? 0;
    final bestVolume = (_selectedHistory!['best_volume'] as double?) ?? 0;
    final best1RM = (_selectedHistory!['best_1rm'] as double?) ?? 0;

    return Row(
      children: [
        Expanded(
          child: _RecordCard(
            label: 'Peso Máx', value: bestWeight > 0 ? '${bestWeight.toStringAsFixed(1)} kg' : '--',
            icon: Icons.monitor_weight, color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RecordCard(
            label: 'Volume', value: bestVolume > 0 ? '${bestVolume.toStringAsFixed(0)} kg' : '--',
            icon: Icons.auto_graph, color: theme.colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _RecordCard(
            label: '1RM', value: best1RM > 0 ? '${best1RM.toStringAsFixed(1)} kg' : '--',
            icon: Icons.emoji_events, color: Colors.amber,
          ),
        ),
      ],
    );
  }

  Widget _buildChart(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.length < 2) return const SizedBox.shrink();

    String title;
    String Function(int idx) tooltipFn;
    List<double> values;

    switch (_selectedChartType) {
      case 0: // 1RM
        title = 'Evolução do 1RM Estimado';
        values = history.map((h) => (h['estimated_1rm'] as double?) ?? 0).toList();
        break;
      case 1: // Max Weight
        title = 'Evolução do Peso Máximo';
        values = history.map((h) => (h['max_weight'] as double?) ?? 0).toList();
        break;
      case 2: // Volume
        title = 'Volume por Treino';
        values = history.map((h) => (h['total_volume'] as double?) ?? 0).toList();
        break;
      case 3: // Total Reps
        title = 'Repetições por Treino';
        values = history.map((h) => (h['total_reps'] as int?)?.toDouble() ?? 0).toList();
        break;
      default:
        return const SizedBox.shrink();
    }

    final maxVal = values.fold<double>(0, (a, b) => a > b ? a : b);
    final minVal = values.fold<double>(values.isNotEmpty ? values.first : 0, (a, b) => a < b ? a : b);
    final range = maxVal - minVal;
    final interval = range > 0 ? (range / 5).ceilToDouble().clamp(0.5, double.infinity) : 1.0;

    return Card(
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
              height: 220,
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
                        getTitlesWidget: (v, _) {
                          final numVal = v is double ? v : v.toDouble();
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _selectedChartType == 3 ? '${numVal.toInt()}' : '${numVal.toStringAsFixed(1)}',
                              style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                            ),
                          );
                        },
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
                      color: _selectedChartType == 0
                          ? Colors.amber
                          : _selectedChartType == 2
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(
                        show: history.length <= 30,
                        getDotPainter: (spot, percent, bar, index) =>
                            FlDotCirclePainter(
                              radius: 4,
                              color: _selectedChartType == 0
                                  ? Colors.amber
                                  : _selectedChartType == 2
                                      ? theme.colorScheme.secondary
                                      : theme.colorScheme.primary,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: (_selectedChartType == 0
                            ? Colors.amber
                            : _selectedChartType == 2
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
    );
  }

  Widget _buildHistorySection(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Histórico de Treinos', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),

        // Table header
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

        // History rows (most recent first)
        ...history.reversed.map((h) {
          final date = h['date'] as String? ?? '';
          final maxW = (h['max_weight'] as double?) ?? 0;
          final vol = (h['total_volume'] as double?) ?? 0;
          final sets = (h['total_sets'] as int?) ?? 0;
          final reps = (h['total_reps'] as int?) ?? 0;
          final est1RM = (h['estimated_1rm'] as double?);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
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
          );
        }),
      ],
    );
  }
}

class _RecordCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _RecordCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color.withAlpha(15),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 13)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
