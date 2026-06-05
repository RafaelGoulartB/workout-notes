import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:life_notes/l10n/app_localizations.dart';
import '../../database/database_helper.dart';

class BodyTrackerScreen extends StatefulWidget {
  const BodyTrackerScreen({super.key});

  @override
  State<BodyTrackerScreen> createState() => _BodyTrackerScreenState();
}

class _BodyTrackerScreenState extends State<BodyTrackerScreen> {
  final _db = DatabaseHelper.instance;
  String _selectedType = 'weight';
  List<Map<String, dynamic>> _measurements = [];
  bool _isLoading = true;

  final _types = [
    {'id': 'weight', 'name': 'bodyTrackerWeight', 'unit': 'kg', 'icon': Icons.monitor_weight},
    {'id': 'bodyFat', 'name': 'bodyTrackerBodyFat', 'unit': '%', 'icon': Icons.water_drop},
    {'id': 'waist', 'name': 'bodyTrackerWaist', 'unit': 'cm', 'icon': Icons.straighten},
    {'id': 'chest', 'name': 'bodyTrackerChest', 'unit': 'cm', 'icon': Icons.straighten},
    {'id': 'arm', 'name': 'bodyTrackerArm', 'unit': 'cm', 'icon': Icons.straighten},
    {'id': 'thigh', 'name': 'bodyTrackerThigh', 'unit': 'cm', 'icon': Icons.straighten},
    {'id': 'hip', 'name': 'bodyTrackerHip', 'unit': 'cm', 'icon': Icons.straighten},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    _measurements = await _db.getBodyMeasurements(type: _selectedType, limit: 50);
    setState(() => _isLoading = false);
  }

  void _addMeasurement() {
    final valueCtl = TextEditingController();
    final dateCtl = TextEditingController(
      text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final commentCtl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.bodyTrackerAddTitle(_typeName(_selectedType))),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: valueCtl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Valor (${_types.firstWhere((t) => t['id'] == _selectedType)['unit']})',
                border: const OutlineInputBorder(),
              ),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: dateCtl,
              decoration: const InputDecoration(
                labelText: 'Data',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.calendar_today),
              ),
              readOnly: true,
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (date != null) dateCtl.text = DateFormat('yyyy-MM-dd').format(date);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              controller: commentCtl,
              decoration: const InputDecoration(
                labelText: 'Observação (opcional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () async {
            final value = double.tryParse(valueCtl.text.replaceAll(',', '.'));
            if (value == null || value <= 0) return;
            final date = DateTime.tryParse(dateCtl.text);
            await _db.addBodyMeasurement(
              _selectedType, value,
              _types.firstWhere((t) => t['id'] == _selectedType)['unit'] as String,
              date: date, comment: commentCtl.text,
            );
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          }, child: const Text('Adicionar')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentType = _types.firstWhere((t) => t['id'] == _selectedType);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Medidas Corporais'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Type selector
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _types.map((t) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    avatar: Icon(t['icon'] as IconData, size: 18),
                    label: Text(_typeName(t['id'] as String)),
                    selected: _selectedType == t['id'],
                    onSelected: (_) {
                      setState(() => _selectedType = t['id'] as String);
                      _load();
                    },
                  ),
                )).toList(),
              ),
            ),
          ),

          if (_isLoading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_measurements.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(currentType['icon'] as IconData, size: 64, color: theme.colorScheme.primary.withAlpha(80)),
                      const SizedBox(height: 16),
                      Text('${AppLocalizations.of(context)!.progressNoData}: ${_typeName(currentType['id'] as String)}', style: theme.textTheme.titleMedium),
                      const SizedBox(height: 8),
                      Text('Adicione sua primeira medida', style: theme.textTheme.bodySmall),
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
                  children: [
                    // Chart
                    if (_measurements.length >= 2)
                      Card(
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
                              Text('Evolução', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 200,
                                child: LineChart(
                                  LineChartData(
                                    gridData: FlGridData(show: true, drawVerticalLine: false),
                                    titlesData: FlTitlesData(
                                      leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40,
                                        getTitlesWidget: (v, _) => Text('${v.toInt()}', style: theme.textTheme.bodySmall))),
                                      bottomTitles: AxisTitles(sideTitles: SideTitles(
                                        showTitles: true, reservedSize: 30,
                                        getTitlesWidget: (v, _) {
                                          final idx = v.toInt();
                                          if (idx < 0 || idx >= _measurements.length) return const SizedBox.shrink();
                                          final date = _measurements[idx]['date'] as String? ?? '';
                                          return Text(date.length >= 5 ? date.substring(5) : '', style: theme.textTheme.bodySmall?.copyWith(fontSize: 9));
                                        },
                                      )),
                                      topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                      rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    ),
                                    borderData: FlBorderData(show: false),
                                    lineBarsData: [
                                      LineChartBarData(
                                        spots: _measurements.asMap().entries.map((e) =>
                                          FlSpot(e.key.toDouble(), (e.value['value'] as num).toDouble())).toList(),
                                        isCurved: true,
                                        color: theme.colorScheme.primary,
                                        barWidth: 3,
                                        dotData: FlDotData(show: true),
                                        belowBarData: BarAreaData(show: true, color: theme.colorScheme.primary.withAlpha(30)),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                    const SizedBox(height: 16),

                    // Measurement list
                    ..._measurements.asMap().entries.map((entry) {
                      final m = entry.value;
                      final date = m['date'] as String? ?? '';
                      final value = (m['value'] as num?)?.toDouble() ?? 0;
                      final unit = m['unit'] as String? ?? '';
                      final comment = m['comment'] as String?;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Card(
                          elevation: 0,
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(100),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(currentType['icon'] as IconData, color: theme.colorScheme.onPrimaryContainer, size: 18),
                            ),
                            title: Text('${value.toStringAsFixed(1)} $unit', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                            subtitle: Text(date.isNotEmpty ? DateFormat('d MMM yyyy', 'pt_BR').format(DateTime.parse(date)) : ''),
                            trailing: comment != null && comment.isNotEmpty
                                ? Icon(Icons.info_outline, size: 16, color: theme.colorScheme.onSurfaceVariant)
                                : null,
                            onLongPress: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Excluir medida?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir', style: TextStyle(color: Colors.red))),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _db.deleteBodyMeasurement(m['id'] as String);
                                _load();
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addMeasurement,
        icon: const Icon(Icons.add),
        label: Text(AppLocalizations.of(context)!.bodyTrackerAddTitle(_typeName(currentType['id'] as String))),
      ),
    );
  }

  String _typeName(String typeId) {
    switch (typeId) {
      case 'weight': return AppLocalizations.of(context)!.bodyTrackerWeight;
      case 'bodyFat': return AppLocalizations.of(context)!.bodyTrackerBodyFat;
      case 'waist': return AppLocalizations.of(context)!.bodyTrackerWaist;
      case 'chest': return AppLocalizations.of(context)!.bodyTrackerChest;
      case 'arm': return AppLocalizations.of(context)!.bodyTrackerArm;
      case 'thigh': return AppLocalizations.of(context)!.bodyTrackerThigh;
      case 'hip': return AppLocalizations.of(context)!.bodyTrackerHip;
      default: return typeId;
    }
  }
}
