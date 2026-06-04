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
  
  // Overview data
  Map<String, dynamic>? _overviewStats;
  List<Map<String, dynamic>> _monthlyVolume = [];
  
  // Exercise detail data
  List<Map<String, dynamic>> _allExercises = [];
  List<Map<String, dynamic>> _exercisesWithData = [];
  Map<String, dynamic>? _selectedHistory;
  int _selectedChartType = 0;

  bool _showingOverview = true;

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
    _overviewStats = await _db.getWorkoutOverviewStats();
    _monthlyVolume = await _db.getMonthlyVolume();
    _exercisesWithData = [];

    // Find exercises that have recorded data
    for (final ex in _allExercises) {
      final data = await _db.getExerciseHistory(ex['id'] as String, limit: 1);
      final history = data['history'] as List? ?? [];
      if (history.isNotEmpty) {
        _exercisesWithData.add(ex);
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _loadHistory(String exerciseId) async {
    final data = await _db.getExerciseHistory(exerciseId, limit: 30);
    setState(() {
      _selectedHistory = data;
      _showingOverview = false;
    });
  }

  /// Calculates a "nice" interval for chart grid lines.
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
    final result = temp * magnitude;
    return result < 0.5 ? 0.5 : result;
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
        title: Text(_showingOverview ? 'Progresso' : (_selectedHistory?['exercise_name'] as String? ?? 'Progresso')),
        centerTitle: true,
        leading: _showingOverview
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() => _showingOverview = true),
              ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showingOverview
              ? _buildOverview(theme)
              : _buildExerciseDetail(theme),
    );
  }

  // ======================= OVERVIEW =======================

  Widget _buildOverview(ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats cards
          _buildStatsRow(theme),
          const SizedBox(height: 16),

          // Monthly volume chart
          if (_monthlyVolume.isNotEmpty) ...[
            Text('Volume por Mês', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _buildMonthlyVolumeChart(theme),
            const SizedBox(height: 20),
          ],

          // Exercises section header
          Row(
            children: [
              Text('Exercícios', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_exercisesWithData.length}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Search
          TextField(
            controller: _searchCtl,
            decoration: InputDecoration(
              hintText: 'Buscar exercício...',
              prefixIcon: const Icon(Icons.search, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),

          // Exercise list
          if (_exercisesWithData.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.fitness_center_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                    const SizedBox(height: 12),
                    Text('Nenhum exercício com dados registrados',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
            )
          else
            ..._buildExerciseCards(theme),
        ],
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme) {
    final stats = _overviewStats;
    final totalWorkouts = (stats?['total_workouts'] as int?) ?? 0;
    final totalSets = (stats?['total_sets'] as int?) ?? 0;
    final totalVolume = (stats?['total_volume'] as int?) ?? 0;
    final streak = (stats?['current_streak'] as int?) ?? 0;

    return Row(
      children: [
        Expanded(child: _StatCard(
          label: 'Treinos', value: '$totalWorkouts',
          icon: Icons.fitness_center, color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: 'Séries', value: '$totalSets',
          icon: Icons.repeat, color: theme.colorScheme.secondary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: 'Volume', value: totalVolume >= 1000
              ? '${(totalVolume / 1000).toStringAsFixed(1)}k'
              : '$totalVolume',
          icon: Icons.auto_graph, color: Colors.teal,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: 'Sequência', value: '$streak ${streak == 1 ? 'dia' : 'dias'}',
          icon: Icons.local_fire_department, color: Colors.orange,
        )),
      ],
    );
  }

  Widget _buildMonthlyVolumeChart(ThemeData theme) {
    final volumes = _monthlyVolume.map((m) => (m['volume'] as double?) ?? 0).toList();
    final maxVol = volumes.fold<double>(0, (a, b) => a > b ? a : b);
    if (maxVol <= 0) return const SizedBox.shrink();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxVol * 1.15,
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final m = _monthlyVolume[groupIndex];
                    final month = m['month'] as String? ?? '';
                    final vol = (m['volume'] as double?) ?? 0;
                    final wo = (m['workouts'] as int?) ?? 0;
                    return BarTooltipItem(
                      '${_monthLabel(month)}\n${_formatVolume(vol)}\n${wo} treinos',
                      TextStyle(color: theme.colorScheme.onSurface, fontWeight: FontWeight.bold, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= _monthlyVolume.length) return const SizedBox.shrink();
                      final month = _monthlyVolume[idx]['month'] as String? ?? '';
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          month.length >= 7 ? month.substring(5, 7) : '',
                          style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
                        ),
                      );
                    },
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 36,
                    getTitlesWidget: (v, _) {
                      if (v == 0) return const SizedBox.shrink();
                      return Text(
                        _formatVolume(v),
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 9),
                      );
                    },
                  ),
                ),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxVol > 0 ? _niceInterval(maxVol / 4) : 1,
              ),
              barGroups: _monthlyVolume.asMap().entries.map((entry) {
                final idx = entry.key;
                final vol = (entry.value['volume'] as double?) ?? 0;
                return BarChartGroupData(
                  x: idx,
                  barRods: [
                    BarChartRodData(
                      toY: vol,
                      color: theme.colorScheme.primary,
                      width: 20,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(4),
                        topRight: Radius.circular(4),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  String _monthLabel(String isoMonth) {
    try {
      return DateFormat('MMM', 'pt_BR').format(DateTime.parse(isoMonth));
    } catch (_) {
      return isoMonth.length >= 7 ? isoMonth.substring(5) : isoMonth;
    }
  }

  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  List<Widget> _buildExerciseCards(ThemeData theme) {
    final filtered = _filteredExercises;
    if (filtered.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Nenhum exercício encontrado',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        ),
      ];
    }

    return filtered.map((ex) {
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
    }).toList();
  }

  // ======================= EXERCISE DETAIL =======================

  Widget _buildExerciseDetail(ThemeData theme) {
    if (_selectedHistory == null) return const SizedBox.shrink();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              Expanded(child: _buildExerciseSelector(theme)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        _buildChartTypeSelector(theme),
        Expanded(
          child: SingleChildScrollView(
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
    );
  }

  Widget _buildExerciseSelector(ThemeData theme) {
    final selectedEx = _allExercises.firstWhere(
      (e) => e['id'] == (_selectedHistory?['exercise_id']),
      orElse: () => <String, dynamic>{},
    );

    return DropdownButtonFormField<String>(
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

  Widget _buildRecords(ThemeData theme) {
    final bestWeight = (_selectedHistory!['best_weight'] as double?) ?? 0;
    final bestVolume = (_selectedHistory!['best_volume'] as double?) ?? 0;
    final best1RM = (_selectedHistory!['best_1rm'] as double?) ?? 0;

    return Row(
      children: [
        Expanded(child: _StatCard(
          label: 'Peso Máx', value: bestWeight > 0 ? '${bestWeight.toStringAsFixed(1)}' : '--',
          icon: Icons.monitor_weight, color: theme.colorScheme.primary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: 'Volume', value: bestVolume > 0 ? '${_formatVolume(bestVolume)}' : '--',
          icon: Icons.auto_graph, color: theme.colorScheme.secondary,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          label: '1RM', value: best1RM > 0 ? '${best1RM.toStringAsFixed(1)}' : '--',
          icon: Icons.emoji_events, color: Colors.amber,
        )),
      ],
    );
  }

  Widget _buildChart(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];

    String title;
    List<double> values;

    switch (_selectedChartType) {
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
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.bar_chart_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
              const SizedBox(height: 12),
              Text('Nenhum dado disponível para este tipo de gráfico',
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    final range = maxVal - minVal;
    final interval = _niceInterval(range);

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
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              _selectedChartType == 3 ? '${v.toInt()}' : '${v.toStringAsFixed(1)}',
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 12)),
            Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
