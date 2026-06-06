import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../database/database_helper.dart';
import '../../widgets/empty_state_placeholder.dart';

class BodyTrackerScreen extends StatefulWidget {
  const BodyTrackerScreen({super.key});

  @override
  State<BodyTrackerScreen> createState() => _BodyTrackerScreenState();
}

class _BodyTrackerScreenState extends State<BodyTrackerScreen> {
  final _db = DatabaseHelper.instance;

  // ── State ──────────────────────────────────────────────────────────
  String _selectedType = 'weight';
  List<Map<String, dynamic>> _measurements = [];
  List<Map<String, dynamic>> _allMeasurements = [];
  Map<String, Map<String, dynamic>?> _latestByType = {};
  bool _isLoading = true;
  bool _fabOpen = false;

  // ── Measurement type definitions ───────────────────────────────────
  static const _types = <_MeasureType>[
    _MeasureType('weight', Icons.monitor_weight, 'kg', Colors.indigo),
    _MeasureType('bodyFat', Icons.water_drop, '%', Colors.orange),
    _MeasureType('waist', Icons.straighten, 'cm', Colors.teal),
    _MeasureType('chest', Icons.straighten, 'cm', Colors.blue),
    _MeasureType('arm', Icons.straighten, 'cm', Colors.purple),
    _MeasureType('thigh', Icons.straighten, 'cm', Colors.deepOrange),
    _MeasureType('hip', Icons.straighten, 'cm', Colors.cyan),
  ];

  _MeasureType get _currentType =>
      _types.firstWhere((t) => t.id == _selectedType);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final all = await _db.getBodyMeasurements(limit: 500);
      final summary = await _db.getBodyMeasurementsSummary();
      final latestMap = <String, Map<String, dynamic>?>{};
      for (final t in _types) {
        try {
          latestMap[t.id] = summary.firstWhere((s) => s['type'] == t.id);
        } catch (_) {
          latestMap[t.id] = null;
        }
      }
      final filtered = all.where((m) => m['type'] == _selectedType).toList();
      if (!mounted) return;
      setState(() {
        _allMeasurements = all;
        _latestByType = latestMap;
        _measurements = filtered;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _switchType(String typeId) async {
    setState(() {
      _selectedType = typeId;
      _measurements =
          _allMeasurements.where((m) => m['type'] == typeId).toList();
    });
  }

  // ── Derived stats ──────────────────────────────────────────────────
  double? get _currentValue {
    final latest = _latestByType[_selectedType];
    if (latest == null) return null;
    return (latest['value'] as num?)?.toDouble();
  }

  double? get _previousValue {
    if (_measurements.length < 2) return null;
    return (_measurements[1]['value'] as num?)?.toDouble();
  }

  double? get _delta {
    if (_currentValue == null || _previousValue == null) return null;
    return _currentValue! - _previousValue!;
  }

  double? get _minValue {
    if (_measurements.isEmpty) return null;
    return _measurements
        .map((m) => (m['value'] as num).toDouble())
        .reduce((a, b) => a < b ? a : b);
  }

  double? get _maxValue {
    if (_measurements.isEmpty) return null;
    return _measurements
        .map((m) => (m['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
  }

  double? get _avgValue {
    if (_measurements.isEmpty) return null;
    return _measurements
            .map((m) => (m['value'] as num).toDouble())
            .reduce((a, b) => a + b) /
        _measurements.length;
  }

  bool get _isDecreasingGood =>
      _selectedType == 'weight' || _selectedType == 'bodyFat';

  // ── Speed Dial FAB ─────────────────────────────────────────────────
  Widget _buildSpeedDial(ThemeData theme, AppLocalizations loc) {
    final typeName = _typeName(_selectedType);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Child buttons (animated)
        AnimatedScale(
          scale: _fabOpen ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutBack,
          child: AnimatedOpacity(
            opacity: _fabOpen ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 150),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _SpeedDialOption(
                  label: loc.bodyTrackerAddTitle(typeName),
                  icon: Icons.add_circle_outline,
                  color: _currentType.color,
                  onTap: () {
                    setState(() => _fabOpen = false);
                    _showAddDialog();
                  },
                ),
                const SizedBox(height: 10),
                _SpeedDialOption(
                  label: loc.bodyTrackerQuickMeasure,
                  icon: Icons.bolt,
                  color: Colors.amber,
                  onTap: () {
                    setState(() => _fabOpen = false);
                    _showQuickMeasureSheet();
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Main FAB
        FloatingActionButton(
          onPressed: () => setState(() => _fabOpen = !_fabOpen),
          child: AnimatedRotation(
            turns: _fabOpen ? 0.125 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }

  // ── Add single measurement ─────────────────────────────────────────
  void _showAddDialog() {
    final valueCtl = TextEditingController();
    final commentCtl = TextEditingController();
    var date = DateTime.now();
    String? timeOfDay;
    bool isFasted = false;
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final loc = AppLocalizations.of(ctx)!;
        final unit = _currentType.unit;

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                  24, 20, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withAlpha(60),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _currentType.color.withAlpha(20),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(_currentType.icon,
                                size: 24, color: _currentType.color),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              loc.bodyTrackerAddTitle(_typeName(_selectedType)),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: valueCtl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        autofocus: true,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -1,
                        ),
                        textAlign: TextAlign.center,
                        decoration: InputDecoration(
                          hintText: '0.0',
                          suffixText: ' $unit',
                          suffixStyle: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withAlpha(80),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 20, horizontal: 16),
                        ),
                        validator: (v) {
                          final val =
                              double.tryParse(v?.replaceAll(',', '.') ?? '');
                          if (val == null || val <= 0) return 'Valor inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: date,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setSheetState(() => date = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withAlpha(100),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 18,
                                        color: theme.colorScheme.primary),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('d MMM yyyy', 'pt_BR')
                                          .format(date),
                                      style: theme.textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: _TimeOfDaySelector(
                              value: timeOfDay,
                              onChanged: (v) =>
                                  setSheetState(() => timeOfDay = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: FilterChip(
                              avatar: Icon(Icons.nightlight_round,
                                  size: 16,
                                  color: isFasted
                                      ? Colors.deepPurple
                                      : theme.colorScheme.onSurfaceVariant),
                              label: const Text('Em jejum'),
                              selected: isFasted,
                              onSelected: (v) =>
                                  setSheetState(() => isFasted = v),
                              selectedColor: Colors.deepPurple.withAlpha(30),
                              checkmarkColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: commentCtl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText: loc.bodyTrackerComment,
                          prefixIcon: Icon(Icons.notes,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 12, horizontal: 14),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: () async {
                            if (!formKey.currentState!.validate()) {
                              return;
                            }
                            final value = double.tryParse(
                                valueCtl.text.replaceAll(',', '.'));
                            if (value == null || value <= 0) return;
                            await _db.addBodyMeasurement(
                              _selectedType,
                              value,
                              _currentType.unit,
                              date: date,
                              comment: commentCtl.text.isNotEmpty
                                  ? commentCtl.text
                                  : null,
                              timeOfDay: timeOfDay,
                              isFasted: isFasted,
                            );
                            if (ctx.mounted) {
                              Navigator.pop(ctx);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(loc.bodyTrackerSaved),
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                            _load();
                          },
                          icon: const Icon(Icons.check),
                          label: Text(loc.bodyTrackerSave,
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Quick Measure (all types) ──────────────────────────────────────
  void _showQuickMeasureSheet() {
    final controllers = <String, TextEditingController>{};
    final hasValue = <String, bool>{};
    for (final t in _types) {
      controllers[t.id] = TextEditingController();
      hasValue[t.id] = false;
    }
    var date = DateTime.now();
    String? timeOfDay;
    bool isFasted = false;
    final commentCtl = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final loc = AppLocalizations.of(ctx)!;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final anyFilled = hasValue.values.any((v) => v);
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (ctx, scrollController) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  child: Column(
                    children: [
                      Center(
                        child: Container(
                          width: 36, height: 4,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.onSurfaceVariant
                                .withAlpha(60),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.bolt,
                                size: 22,
                                color: theme.colorScheme.onPrimaryContainer),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(loc.bodyTrackerQuickMeasure,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.bold)),
                                Text(loc.bodyTrackerQuickMeasureSubtitle,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color:
                                          theme.colorScheme.onSurfaceVariant,
                                    )),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: date,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                );
                                if (picked != null) {
                                  setSheetState(() => date = picked);
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: theme.colorScheme.outlineVariant
                                        .withAlpha(100),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 16,
                                        color: theme.colorScheme.primary),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        DateFormat('d MMM yyyy', 'pt_BR')
                                            .format(date),
                                        style: theme.textTheme.bodySmall,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilterChip(
                            avatar: Icon(Icons.nightlight_round,
                                size: 14,
                                color: isFasted
                                    ? Colors.deepPurple
                                    : theme.colorScheme.onSurfaceVariant),
                            label: const Text('Jejum',
                                style: TextStyle(fontSize: 12)),
                            selected: isFasted,
                            onSelected: (v) =>
                                setSheetState(() => isFasted = v),
                            selectedColor: Colors.deepPurple.withAlpha(30),
                            checkmarkColor: Colors.deepPurple,
                            visualDensity: VisualDensity.compact,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _QuickTimeOfDaySelector(
                        value: timeOfDay,
                        onChanged: (v) =>
                            setSheetState(() => timeOfDay = v),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: EdgeInsets.zero,
                          children: _types.map((t) {
                            final ctl = controllers[t.id]!;
                            final isFilled = hasValue[t.id] == true;
                            final latest = _latestByType[t.id];
                            final latestVal = latest != null
                                ? (latest['value'] as num?)?.toDouble()
                                : null;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isFilled
                                        ? t.color.withAlpha(80)
                                        : theme.colorScheme.outlineVariant
                                            .withAlpha(40),
                                  ),
                                  color: isFilled
                                      ? t.color.withAlpha(10)
                                      : null,
                                ),
                                child: ListTile(
                                  leading: Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: t.color.withAlpha(22),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(t.icon,
                                        size: 18, color: t.color),
                                  ),
                                  title: Text(
                                    _typeName(t.id),
                                    style:
                                        theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: isFilled ? t.color : null,
                                    ),
                                  ),
                                  subtitle: latestVal != null
                                      ? Text(
                                          'Último: ${latestVal.toStringAsFixed(1)} ${t.unit}',
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: theme
                                                  .colorScheme
                                                  .onSurfaceVariant
                                                  .withAlpha(180)),
                                        )
                                      : null,
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 2),
                                  trailing: SizedBox(
                                    width: 80,
                                    child: TextFormField(
                                      controller: ctl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      textAlign: TextAlign.end,
                                      style: theme.textTheme.titleSmall?.copyWith(
                                        fontWeight: FontWeight.bold,
                                        color: isFilled
                                            ? t.color
                                            : theme.colorScheme.onSurface,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: '0',
                                        hintStyle: theme.textTheme.bodySmall
                                            ?.copyWith(
                                          color: theme
                                              .colorScheme.onSurfaceVariant
                                              .withAlpha(80),
                                        ),
                                        suffixText: isFilled ? ' ${t.unit}' : null,
                                        suffixStyle: TextStyle(
                                            color: t.color, fontSize: 11),
                                        border: InputBorder.none,
                                        isDense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                      onChanged: (v) {
                                        setSheetState(() {
                                          hasValue[t.id] = v.isNotEmpty;
                                        });
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: commentCtl,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              '${loc.bodyTrackerComment} (comum a todas)',
                          prefixIcon: Icon(Icons.notes,
                              size: 16,
                              color: theme.colorScheme.onSurfaceVariant),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              vertical: 10, horizontal: 12),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton.icon(
                          onPressed: anyFilled
                              ? () async {
                                  final batch = <Map<String, dynamic>>[];
                                  for (final t in _types) {
                                    final txt = controllers[t.id]!.text;
                                    if (txt.isEmpty) continue;
                                    final val = double.tryParse(
                                        txt.replaceAll(',', '.'));
                                    if (val == null || val <= 0) continue;
                                    batch.add({
                                      'type': t.id,
                                      'value': val,
                                      'unit': t.unit,
                                      'date': date
                                          .toIso8601String()
                                          .substring(0, 10),
                                      'comment': commentCtl.text.isNotEmpty
                                          ? commentCtl.text
                                          : null,
                                      'time_of_day': timeOfDay,
                                      'is_fasted': isFasted,
                                    });
                                  }
                                  if (batch.isNotEmpty) {
                                    await _db
                                        .addBodyMeasurementsBatch(batch);
                                    if (ctx.mounted) {
                                      Navigator.pop(ctx);
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              '✅ ${batch.length} medidas salvas!'),
                                          behavior:
                                              SnackBarBehavior.floating,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                          ),
                                        ),
                                      );
                                    }
                                    _load();
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.save),
                          label: Text(loc.bodyTrackerSaveAll,
                              style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                          style: FilledButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.bodyTrackerTitle),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _allMeasurements.isEmpty
                  ? _buildEmptyState(theme, loc)
                  : _buildContent(theme, loc),
          // Backdrop when FAB menu is open
          if (_fabOpen)
            GestureDetector(
              onTap: () => setState(() => _fabOpen = false),
              behavior: HitTestBehavior.opaque,
              child: Container(color: Colors.black26),
            ),
        ],
      ),
      floatingActionButton: _buildSpeedDial(theme, loc),
    );
  }

  Widget _buildEmptyState(ThemeData theme, AppLocalizations loc) {
    return EmptyStatePlaceholder(
      icon: Icons.accessibility_new,
      title: loc.bodyTrackerEmptyTitle,
      subtitle: loc.bodyTrackerEmptySubtitle,
      actionLabel: loc.bodyTrackerQuickMeasure,
      onAction: _showQuickMeasureSheet,
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations loc) {
    return Column(
      children: [
        // Type selector (ChoiceChip style, matching the rest of the app)
        _buildTypeSelector(theme, loc),
        const SizedBox(height: 12),

        // Hero summary card
        _buildSummaryCard(theme, loc),

        if (_measurements.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildQuickStatsRow(theme, loc),
        ],

        // Body
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (_measurements.length >= 2) ...[
                SliverToBoxAdapter(child: const SizedBox(height: 12)),
                SliverToBoxAdapter(child: _buildChartCard(theme, loc)),
              ],
              if (_measurements.isNotEmpty &&
                  _selectedType == 'weight' &&
                  _currentValue != null) ...[
                SliverToBoxAdapter(child: const SizedBox(height: 12)),
                SliverToBoxAdapter(child: _buildDerivedStatsCard(theme, loc)),
              ],
              if (_measurements.isNotEmpty) ...[
                SliverToBoxAdapter(child: const SizedBox(height: 16)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          '${loc.bodyTrackerHistory} · ${_measurements.length} ${loc.bodyTrackerEntries}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(child: const SizedBox(height: 8)),
              ],
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) =>
                      _buildMeasurementCard(theme, loc, _measurements[i], i),
                  childCount: _measurements.length,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ],
    );
  }

  // ── Type Selector (ChoiceChip style) ───────────────────────────────
  Widget _buildTypeSelector(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SizedBox(
        height: 38,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: _types.map((t) {
            final isSelected = _selectedType == t.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                avatar: Icon(t.icon, size: 16,
                    color: isSelected ? t.color : theme.colorScheme.onSurfaceVariant),
                label: Text(_typeName(t.id)),
                selected: isSelected,
                selectedColor: t.color.withAlpha(25),
                onSelected: (_) => _switchType(t.id),
                visualDensity: VisualDensity.compact,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: isSelected
                        ? t.color.withAlpha(80)
                        : theme.colorScheme.outlineVariant.withAlpha(40),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Summary Card ───────────────────────────────────────────────────
  Widget _buildSummaryCard(ThemeData theme, AppLocalizations loc) {
    final value = _currentValue;
    final unit = _currentType.unit;
    final delta = _delta;

    final isGood = _isDecreasingGood
        ? (delta != null && delta < 0)
        : (delta != null && delta > 0);
    final isBad = _isDecreasingGood
        ? (delta != null && delta > 0)
        : (delta != null && delta < 0);
    final deltaColor = delta == null
        ? Colors.transparent
        : (isGood
            ? Colors.green
            : isBad
                ? Colors.red
                : theme.colorScheme.onSurfaceVariant);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: theme.colorScheme.surface,
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _currentType.color.withAlpha(20),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_currentType.icon,
                      size: 18, color: _currentType.color),
                ),
                const SizedBox(width: 10),
                Text(
                  _typeName(_selectedType),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (delta != null && delta != 0)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: deltaColor.withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: deltaColor.withAlpha(60)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta > 0 ? Icons.trending_up : Icons.trending_down,
                          size: 14,
                          color: deltaColor,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)}',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: deltaColor,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Big value
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value != null ? value.toStringAsFixed(1) : '--',
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: -2,
                    fontSize: 42,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      unit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),

            // Sparkline
            if (_measurements.length >= 3) ...[
              const SizedBox(height: 8),
              SizedBox(height: 40, child: _buildSparkline(theme)),
            ],

            // Last measurement info
            if (value != null && _measurements.isNotEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.access_time,
                      size: 12,
                      color: theme.colorScheme.onSurfaceVariant
                          .withAlpha(140)),
                  const SizedBox(width: 4),
                  Text(
                    _formatDate(
                        _measurements.first['date'] as String? ?? ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant
                          .withAlpha(160),
                      fontSize: 11,
                    ),
                  ),
                  if ((_measurements.first['time_of_day'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(width: 8),
                    _TimeOfDayBadge(tod: _measurements.first['time_of_day'] as String),
                  ],
                  if ((_measurements.first['is_fasted'] as int?) == 1) ...[
                    const SizedBox(width: 8),
                    const _FastedBadge(),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Sparkline ──────────────────────────────────────────────────────
  Widget _buildSparkline(ThemeData theme) {
    final reversed = _measurements.reversed.toList();
    final values =
        reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return LineChart(
      LineChartData(
        minY: minVal - range * 0.1,
        maxY: maxVal + range * 0.1,
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: values.asMap().entries
                .map((e) => FlSpot(e.key.toDouble(), e.value))
                .toList(),
            isCurved: true,
            color: _currentType.color.withAlpha(180),
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  _currentType.color.withAlpha(50),
                  _currentType.color.withAlpha(0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Quick Stats Row ────────────────────────────────────────────────
  Widget _buildQuickStatsRow(ThemeData theme, AppLocalizations loc) {
    final statItems = [
      (loc.bodyTrackerMin, _minValue?.toStringAsFixed(1) ?? '--',
          Icons.trending_down, Colors.blueGrey),
      (loc.bodyTrackerMax, _maxValue?.toStringAsFixed(1) ?? '--',
          Icons.trending_up, _currentType.color),
      (loc.bodyTrackerAverage, _avgValue?.toStringAsFixed(1) ?? '--',
          Icons.show_chart, _currentType.color.withAlpha(200)),
      ('Total', '${_measurements.length}', Icons.receipt_long,
          theme.colorScheme.secondary),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: statItems.map((s) {
          final (label, value, icon, color) = s;
          return Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: theme.colorScheme.outlineVariant.withAlpha(50),
                ),
              ),
              child: Column(
                children: [
                  Icon(icon, size: 14, color: color.withAlpha(200)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Chart Card ─────────────────────────────────────────────────────
  Widget _buildChartCard(ThemeData theme, AppLocalizations loc) {
    final reversed = _measurements.reversed.toList();
    final values =
        reversed.map((m) => (m['value'] as num).toDouble()).toList();
    final minVal = values.reduce((a, b) => a < b ? a : b);
    final maxVal = values.reduce((a, b) => a > b ? a : b);
    final range = maxVal - minVal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  loc.bodyTrackerTrendLine,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 200,
                child: LineChart(
                  LineChartData(
                    minY: minVal - range * 0.15,
                    maxY: maxVal + range * 0.15,
                    gridData: FlGridData(
                      show: true,
                      drawVerticalLine: false,
                      horizontalInterval:
                          range > 0 ? _niceInterval(range / 4) : 1,
                      getDrawingHorizontalLine: (v) => FlLine(
                        color:
                            theme.colorScheme.outlineVariant.withAlpha(40),
                        strokeWidth: 0.5,
                      ),
                    ),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 36,
                          getTitlesWidget: (v, _) => Text(
                            v.toStringAsFixed(v >= 100 ? 0 : 1),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 9,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          interval: reversed.length > 10 ? 2 : 1,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx < 0 || idx >= reversed.length) {
                              return const SizedBox.shrink();
                            }
                            final d =
                                reversed[idx]['date'] as String? ?? '';
                            return Text(
                              d.length >= 10 ? d.substring(5) : d,
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 8,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    borderData: FlBorderData(show: false),
                    lineBarsData: [
                      LineChartBarData(
                        spots: values.asMap().entries
                            .map((e) =>
                                FlSpot(e.key.toDouble(), e.value))
                            .toList(),
                        isCurved: true,
                        color: _currentType.color,
                        barWidth: 2.5,
                        dotData: FlDotData(
                          show: values.length <= 25,
                          getDotPainter: (s, p, b, i) => FlDotCirclePainter(
                            radius: 3,
                            color: _currentType.color,
                            strokeWidth: 1.5,
                            strokeColor: theme.colorScheme.surface,
                          ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: [
                              _currentType.color.withAlpha(40),
                              _currentType.color.withAlpha(5),
                            ],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ],
                    lineTouchData: LineTouchData(
                      touchTooltipData: LineTouchTooltipData(
                        getTooltipItems: (spots) => spots.map((s) {
                          final idx = s.spotIndex;
                          final d = idx < reversed.length
                              ? _formatDate(
                                  reversed[idx]['date'] as String? ?? '')
                              : '';
                          return LineTooltipItem(
                            '$d\n${s.y.toStringAsFixed(1)} ${_currentType.unit}',
                            TextStyle(
                              color: theme.colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
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

  // ── Derived Stats Card ─────────────────────────────────────────────
  Widget _buildDerivedStatsCard(ThemeData theme, AppLocalizations loc) {
    final weight = _currentValue!;
    final bodyFatLatest = _latestByType['bodyFat'];
    final bodyFatVal = bodyFatLatest != null
        ? (bodyFatLatest['value'] as num?)?.toDouble()
        : null;
    final waistLatest = _latestByType['waist'];
    final hipLatest = _latestByType['hip'];
    final waistVal = waistLatest != null
        ? (waistLatest['value'] as num?)?.toDouble()
        : null;
    final hipVal = hipLatest != null
        ? (hipLatest['value'] as num?)?.toDouble()
        : null;
    final whr = (waistVal != null && hipVal != null && hipVal > 0)
        ? waistVal / hipVal
        : null;
    final leanMass =
        (bodyFatVal != null) ? weight * (1 - bodyFatVal / 100) : null;
    final fatMass =
        (bodyFatVal != null) ? weight * (bodyFatVal / 100) : null;

    final stats = <_DerivedStat>[];
    if (leanMass != null) {
      stats.add(_DerivedStat(
        'Massa Magra',
        '${leanMass.toStringAsFixed(1)} kg',
        Icons.fitness_center,
        Colors.green,
      ));
    }
    if (fatMass != null) {
      stats.add(_DerivedStat(
        'Massa Gorda',
        '${fatMass.toStringAsFixed(1)} kg',
        Icons.water_drop,
        Colors.orange,
      ));
    }
    if (whr != null) {
      final whrEval =
          whr < 0.9 ? 'Saudável' : whr < 1.0 ? 'Moderado' : 'Elevado';
      stats.add(_DerivedStat(
        'RCQ (C/Q)',
        '${whr.toStringAsFixed(2)} · $whrEval',
        Icons.monitor_weight,
        Colors.teal,
      ));
    }

    if (stats.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Composição Estimada',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: stats
                    .map((s) => Expanded(
                          child: Column(
                            children: [
                              Icon(s.icon,
                                  size: 20, color: s.color.withAlpha(200)),
                              const SizedBox(height: 4),
                              Text(
                                s.value,
                                style:
                                    theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                s.label,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 9,
                                  color:
                                      theme.colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Measurement Card ───────────────────────────────────────────────
  Widget _buildMeasurementCard(
    ThemeData theme,
    AppLocalizations loc,
    Map<String, dynamic> m,
    int index,
  ) {
    final value = (m['value'] as num).toDouble();
    final date = m['date'] as String? ?? '';
    final comment = m['comment'] as String?;
    final timeOfDay = m['time_of_day'] as String?;
    final isFasted = (m['is_fasted'] as int?) == 1;

    double? delta;
    if (index < _measurements.length - 1) {
      final prevVal =
          (_measurements[index + 1]['value'] as num).toDouble();
      delta = value - prevVal;
    }

    final isGood = delta != null && delta != 0
        ? (_isDecreasingGood ? delta < 0 : delta > 0)
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(60)),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onLongPress: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text(loc.bodyTrackerDeleteConfirm),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(loc.commonCancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(loc.commonDelete,
                        style: const TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            );
            if (confirm == true) {
              await _db.deleteBodyMeasurement(m['id'] as String);
              _load();
            }
          },
          onTap: () =>
              _showMeasurementDetail(theme, loc, m, delta),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                // Date column
                SizedBox(
                  width: 48,
                  child: Column(
                    children: [
                      Text(
                        DateFormat('d', 'pt_BR')
                            .format(DateTime.parse(date)),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 19,
                        ),
                      ),
                      Text(
                        DateFormat('MMM', 'pt_BR')
                            .format(DateTime.parse(date)),
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),

                // Value + metadata
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '${value.toStringAsFixed(1)} ${_currentType.unit}',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (timeOfDay != null && timeOfDay.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            _TimeOfDayBadge(tod: timeOfDay),
                          ],
                          if (isFasted) ...[
                            const SizedBox(width: 4),
                            const _FastedBadge(),
                          ],
                        ],
                      ),
                      if (comment != null && comment.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          comment,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant
                                .withAlpha(180),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),

                // Delta badge
                if (delta != null && delta != 0) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: (isGood == true
                              ? Colors.green
                              : Colors.red)
                          .withAlpha(18),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: (isGood == true
                                ? Colors.green
                                : Colors.red)
                            .withAlpha(60),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          delta > 0
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 10,
                          color: isGood == true ? Colors.green : Colors.red,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          delta.abs().toStringAsFixed(1),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color:
                                isGood == true ? Colors.green : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                ],

                Icon(Icons.chevron_right,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant
                        .withAlpha(100)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMeasurementDetail(
    ThemeData theme,
    AppLocalizations loc,
    Map<String, dynamic> m,
    double? delta,
  ) {
    final value = (m['value'] as num).toDouble();
    final date = m['date'] as String? ?? '';
    final comment = m['comment'] as String?;
    final timeOfDay = m['time_of_day'] as String?;
    final isFasted = (m['is_fasted'] as int?) == 1;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36, height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(60),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentType.color.withAlpha(22),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_currentType.icon,
                        size: 28, color: _currentType.color),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _typeName(_selectedType),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatDate(date),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value.toStringAsFixed(1),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _currentType.unit,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              if (delta != null && delta != 0) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      delta > 0 ? Icons.trending_up : Icons.trending_down,
                      size: 16,
                      color: delta > 0 ? Colors.green : Colors.red,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${delta > 0 ? '+' : ''}${delta.toStringAsFixed(1)} ${_currentType.unit}',
                      style: TextStyle(
                        fontSize: 13,
                        color: delta > 0 ? Colors.green : Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (timeOfDay != null || isFasted)
                Wrap(
                  spacing: 8,
                  children: [
                    if (timeOfDay != null && timeOfDay.isNotEmpty)
                      _TimeOfDayChip(tod: timeOfDay, theme: theme),
                    if (isFasted) _FastedChip(theme: theme),
                  ],
                ),
              if (comment != null && comment.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(100),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.notes,
                          size: 16,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Expanded(child: Text(comment)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: Text(loc.bodyTrackerDeleteConfirm),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(c, false),
                              child: Text(loc.commonCancel),
                            ),
                            TextButton(
                              onPressed: () => Navigator.pop(c, true),
                              child: Text(loc.commonDelete,
                                  style: const TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _db.deleteBodyMeasurement(m['id'] as String);
                        _load();
                      }
                    },
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(loc.commonDelete),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String _typeName(String typeId) {
    final loc = AppLocalizations.of(context)!;
    switch (typeId) {
      case 'weight':
        return loc.bodyTrackerWeight;
      case 'bodyFat':
        return loc.bodyTrackerBodyFat;
      case 'waist':
        return loc.bodyTrackerWaist;
      case 'chest':
        return loc.bodyTrackerChest;
      case 'arm':
        return loc.bodyTrackerArm;
      case 'thigh':
        return loc.bodyTrackerThigh;
      case 'hip':
        return loc.bodyTrackerHip;
      default:
        return typeId;
    }
  }

  String _formatDate(String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      return DateFormat('d MMM yyyy', 'pt_BR').format(DateTime.parse(dateStr));
    } catch (_) {
      return dateStr;
    }
  }

  double _niceInterval(double range) {
    if (range <= 0) return 1;
    final rough = range / 4;
    double magnitude = 1;
    double temp = rough;
    while (temp >= 10) {
      temp /= 10;
      magnitude *= 10;
    }
    while (temp < 1) {
      temp *= 10;
      magnitude /= 10;
    }
    if (temp <= 1) temp = 1;
    if (temp <= 2) temp = 2;
    if (temp <= 5) temp = 5;
    if (temp <= 10) temp = 10;
    final result = temp * magnitude;
    return result < 0.5 ? 0.5 : result;
  }
}

// ═══════════════════════════════════════════════════════════════════════
// HELPERS & TYPES
// ═══════════════════════════════════════════════════════════════════════

class _MeasureType {
  final String id;
  final IconData icon;
  final String unit;
  final Color color;
  const _MeasureType(this.id, this.icon, this.unit, this.color);
}

class _DerivedStat {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _DerivedStat(this.label, this.value, this.icon, this.color);
}

// ── Time of Day Badge ────────────────────────────────────────────────
class _TimeOfDayBadge extends StatelessWidget {
  final String tod;
  const _TimeOfDayBadge({required this.tod});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _timeOfDayData(tod);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: Colors.blueGrey),
          const SizedBox(width: 2),
          Text(label,
              style: TextStyle(fontSize: 9, color: Colors.blueGrey.shade700)),
        ],
      ),
    );
  }
}

// ── Fasted Badge ─────────────────────────────────────────────────────
class _FastedBadge extends StatelessWidget {
  const _FastedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nightlight_round,
              size: 10, color: Colors.deepPurple.shade400),
          const SizedBox(width: 2),
          Text('Jejum',
              style:
                  TextStyle(fontSize: 9, color: Colors.deepPurple.shade500)),
        ],
      ),
    );
  }
}

// ── Time of Day Chip ─────────────────────────────────────────────────
class _TimeOfDayChip extends StatelessWidget {
  final String tod;
  final ThemeData theme;
  const _TimeOfDayChip({required this.tod, required this.theme});

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _timeOfDayData(tod);
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.blueGrey.withAlpha(20),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

// ── Fasted Chip ──────────────────────────────────────────────────────
class _FastedChip extends StatelessWidget {
  final ThemeData theme;
  const _FastedChip({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(Icons.nightlight_round, size: 16, color: Colors.deepPurple),
      label: const Text('Em jejum'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      backgroundColor: Colors.deepPurple.withAlpha(20),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

// ── Time of Day Selectors ────────────────────────────────────────────
class _TimeOfDaySelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _TimeOfDaySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(
        labelText: 'Horário',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(value: null, child: Text('Não informado')),
        DropdownMenuItem(value: 'morning', child: Text('🌅 Manhã')),
        DropdownMenuItem(value: 'afternoon', child: Text('☀️ Tarde')),
        DropdownMenuItem(value: 'evening', child: Text('🌆 Noite')),
        DropdownMenuItem(value: 'night', child: Text('🌙 Madrugada')),
      ],
      onChanged: onChanged,
    );
  }
}

class _QuickTimeOfDaySelector extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;
  const _QuickTimeOfDaySelector({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const options = [
      (null, 'Todas', Icons.all_inclusive),
      ('morning', 'Manhã', Icons.wb_sunny),
      ('afternoon', 'Tarde', Icons.wb_cloudy),
      ('evening', 'Noite', Icons.nights_stay),
    ];

    return Row(
      children: options.map((opt) {
        final isSelected = value == opt.$1;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => onChanged(opt.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant.withAlpha(60),
                  ),
                  color: isSelected
                      ? theme.colorScheme.primary.withAlpha(18)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(opt.$3,
                        size: 16,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 2),
                    Text(
                      opt.$2,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight:
                            isSelected ? FontWeight.w600 : FontWeight.w400,
                        color: isSelected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Shared helper ────────────────────────────────────────────────────
(IconData, String) _timeOfDayData(String tod) {
  switch (tod) {
    case 'morning':
      return (Icons.wb_sunny, 'Manhã');
    case 'afternoon':
      return (Icons.wb_cloudy, 'Tarde');
    case 'evening':
      return (Icons.nights_stay, 'Noite');
    case 'night':
      return (Icons.bedtime, 'Madrugada');
    default:
      return (Icons.access_time, tod);
  }
}

// ── Speed Dial Option ────────────────────────────────────────────────
class _SpeedDialOption extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SpeedDialOption({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Label
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withAlpha(20),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Mini FAB
        Material(
          color: color,
          borderRadius: BorderRadius.circular(16),
          elevation: 4,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
      ],
    );
  }
}
