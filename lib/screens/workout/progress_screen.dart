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
  List<Map<String, dynamic>> _exercises = [];
  bool _isLoading = true;
  Map<String, dynamic>? _selectedHistory;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _exercises = await _db.getExercises();
    setState(() => _isLoading = false);
  }

  Future<void> _loadHistory(String exerciseId) async {
    final data = await _db.getExerciseHistory(exerciseId, limit: 30);
    setState(() => _selectedHistory = data);
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
          : Column(
              children: [
                // Exercise selector
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Autocomplete<Map<String, dynamic>>(
                          optionsBuilder: (text) {
                            if (text.text.isEmpty) return _exercises;
                            return _exercises.where((e) =>
                              (e['name'] as String).toLowerCase().contains(text.text.toLowerCase()));
                          },
                          displayStringForOption: (ex) => ex['name'] as String,
                          onSelected: (ex) => _loadHistory(ex['id'] as String),
                          fieldViewBuilder: (ctx, ctl, focusNode, onFieldSubmitted) => TextField(
                            controller: ctl,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              hintText: 'Buscar exercício...',
                              prefixIcon: const Icon(Icons.search),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              filled: true,
                              fillColor: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                            ),
                            onSubmitted: (_) => onFieldSubmitted(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                if (_selectedHistory == null)
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.trending_up, size: 64, color: theme.colorScheme.primary.withAlpha(80)),
                            const SizedBox(height: 16),
                            Text('Selecione um exercício', style: theme.textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('Veja gráficos de progresso, recordes e histórico',
                                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Records
                          _buildRecords(theme),
                          const SizedBox(height: 16),

                          // Progress chart
                          _buildChart(theme),
                          const SizedBox(height: 16),

                          // Volume chart
                          _buildVolumeChart(theme),
                          const SizedBox(height: 16),

                          // History table
                          Text('Histórico', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          ..._buildHistoryTable(theme),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildRecords(ThemeData theme) {
    final bestWeight = (_selectedHistory!['best_weight'] as double?) ?? 0;
    final bestVolume = (_selectedHistory!['best_volume'] as double?) ?? 0;
    final best1RM = (_selectedHistory!['best_1rm'] as double?) ?? 0;

    return Row(
      children: [
        Expanded(child: _RecordCard(label: 'Melhor Peso', value: '${bestWeight.toStringAsFixed(1)} kg', icon: Icons.monitor_weight, color: theme.colorScheme.primary)),
        const SizedBox(width: 8),
        Expanded(child: _RecordCard(label: 'Maior Volume', value: '${bestVolume.toStringAsFixed(0)} kg', icon: Icons.auto_graph, color: theme.colorScheme.secondary)),
        const SizedBox(width: 8),
        Expanded(child: _RecordCard(label: 'Melhor 1RM', value: '${best1RM.toStringAsFixed(1)} kg', icon: Icons.emoji_events, color: Colors.amber)),
      ],
    );
  }

  Widget _buildChart(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

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
            Text('Evolução do Peso Máximo', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true, drawVerticalLine: false,
                    horizontalInterval: _getInterval(history.map((h) => (h['max_weight'] as double)).toList())),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}', style: theme.textTheme.bodySmall))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 30, interval: 1,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                        final date = history[idx]['date'] as String? ?? '';
                        return Transform.rotate(
                          angle: -0.5,
                          child: Text(date.length >= 5 ? date.substring(5) : '', style: theme.textTheme.bodySmall?.copyWith(fontSize: 9)),
                        );
                      },
                    )),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: history.asMap().entries.map((e) =>
                        FlSpot(e.key.toDouble(), (e.value['max_weight'] as double? ?? 0))).toList(),
                      isCurved: true,
                      color: theme.colorScheme.primary,
                      barWidth: 3,
                      dotData: FlDotData(show: true, getDotPainter: (_, __, ___, ____) =>
                        FlDotCirclePainter(radius: 4, color: theme.colorScheme.primary)),
                      belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withAlpha(30)),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVolumeChart(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.isEmpty) return const SizedBox.shrink();

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
            Text('Volume Total por Treino', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  gridData: FlGridData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                      getTitlesWidget: (v, _) => Text('${(v / 1000).toInt()}k', style: theme.textTheme.bodySmall))),
                    bottomTitles: AxisTitles(sideTitles: SideTitles(
                      showTitles: true, reservedSize: 30,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= history.length) return const SizedBox.shrink();
                        final date = history[idx]['date'] as String? ?? '';
                        return Transform.rotate(angle: -0.5, child: Text(date.length >= 5 ? date.substring(5) : '', style: theme.textTheme.bodySmall?.copyWith(fontSize: 9)));
                      },
                    )),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: history.asMap().entries.map((e) =>
                    BarChartGroupData(x: e.key, barRods: [
                      BarChartRodData(toY: e.value['total_volume'] as double? ?? 0,
                        color: theme.colorScheme.secondary, width: 12, borderRadius: BorderRadius.circular(4)),
                    ])).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildHistoryTable(ThemeData theme) {
    final history = _selectedHistory!['history'] as List? ?? [];
    if (history.isEmpty) return [Text('Nenhum histórico disponível', style: theme.textTheme.bodySmall)];

    return history.reversed.map((h) {
      final date = h['date'] as String? ?? '';
      final maxW = (h['max_weight'] as double?) ?? 0;
      final vol = (h['total_volume'] as double?) ?? 0;
      final sets = (h['total_sets'] as int?) ?? 0;
      final reps = (h['total_reps'] as int?) ?? 0;
      final estimated1RM = (h['estimated_1rm'] as double?);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(flex: 2, child: Text(date.length >= 10 ? date.substring(5) : date, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600))),
                Expanded(child: Text('${maxW.toStringAsFixed(1)}kg', style: theme.textTheme.bodySmall)),
                Expanded(child: Text('${vol.toStringAsFixed(0)}kg', style: theme.textTheme.bodySmall)),
                Expanded(child: Text('$sets × $reps', style: theme.textTheme.bodySmall)),
                if (estimated1RM != null)
                  Expanded(child: Text('1RM: ${estimated1RM.toStringAsFixed(1)}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.amber))),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  double _getInterval(List<double> values) {
    if (values.isEmpty) return 10;
    final max = values.reduce((a, b) => a > b ? a : b);
    final min = values.reduce((a, b) => a < b ? a : b);
    final range = max - min;
    if (range <= 0) return 10;
    final steps = range / 5;
    return steps < 1 ? 1 : (steps / 5).ceil() * 5;
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
