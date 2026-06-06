import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/screens/workout/body_tracker_dialogs.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker_badges.dart';
import 'package:workout_notes/widgets/body_tracker_cards.dart';
import 'package:workout_notes/widgets/body_tracker_type_selector.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

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
  static const _types = <MeasureType>[
    MeasureType('weight', Icons.monitor_weight, 'kg', Colors.indigo, false),
    MeasureType('bodyFat', Icons.water_drop, '%', Colors.orange, false),
    MeasureType('waist', Icons.straighten, 'cm', Colors.teal, false),
    MeasureType('chest', Icons.straighten, 'cm', Colors.blue, false),
    MeasureType('arm', Icons.straighten, 'cm', Colors.purple, true),
    MeasureType('thigh', Icons.straighten, 'cm', Colors.deepOrange, true),
    MeasureType('calf', Icons.straighten, 'cm', Colors.brown, true),
    MeasureType('hip', Icons.straighten, 'cm', Colors.cyan, false),
  ];

  MeasureType get _currentType =>
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
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
                SpeedDialOption(
                  label: loc.bodyTrackerAddTitle(typeName(_selectedType, context)),
                  icon: Icons.add_circle_outline,
                  color: _currentType.color,
                  onTap: () {
                    setState(() => _fabOpen = false);
                    showAddMeasurementSheet(
                      context,
                      db: _db,
                      currentType: _currentType,
                      typeId: _selectedType,
                      onSaved: _load,
                    );
                  },
                ),
                const SizedBox(height: 10),
                SpeedDialOption(
                  label: loc.bodyTrackerQuickMeasure,
                  icon: Icons.bolt,
                  color: Colors.amber,
                  onTap: () {
                    setState(() => _fabOpen = false);
                    showQuickMeasureSheet(
                      context,
                      db: _db,
                      types: _types,
                      latestByType: _latestByType,
                      onSaved: _load,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
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
      onAction: () {
        showQuickMeasureSheet(
          context,
          db: _db,
          types: _types,
          latestByType: _latestByType,
          onSaved: _load,
        );
      },
    );
  }

  Widget _buildContent(ThemeData theme, AppLocalizations loc) {
    return Column(
      children: [
        BodyTypeSelector(
          types: _types,
          selectedType: _selectedType,
          onSelected: _switchType,
        ),
        const SizedBox(height: 12),
        BodySummaryCard(
          type: _currentType,
          value: _currentValue,
          delta: _delta,
          isDecreasingGood: _isDecreasingGood,
          measurements: _measurements,
        ),
        if (_measurements.isNotEmpty) ...[
          const SizedBox(height: 12),
          BodyQuickStats(
            minValue: _minValue,
            maxValue: _maxValue,
            avgValue: _avgValue,
            totalCount: _measurements.length,
            typeColor: _currentType.color,
          ),
        ],
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (_measurements.length >= 2) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: BodyChartCard(
                    measurements: _measurements,
                    type: _currentType,
                  ),
                ),
              ],
              if (_measurements.isNotEmpty &&
                  _selectedType == 'weight' &&
                  _currentValue != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: BodyDerivedStatsCard(
                    weight: _currentValue!,
                    latestByType: _latestByType,
                  ),
                ),
              ],
              if (_measurements.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
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
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildMeasurementCard(theme, loc, i),
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

  Widget _buildMeasurementCard(ThemeData theme, AppLocalizations loc, int index) {
    final m = _measurements[index];
    final value = (m['value'] as num).toDouble();

    double? delta;
    if (index < _measurements.length - 1) {
      final prevVal =
          (_measurements[index + 1]['value'] as num).toDouble();
      delta = value - prevVal;
    }

    return BodyMeasurementCard(
      measurement: m,
      type: _currentType,
      delta: delta,
      isDecreasingGood: _isDecreasingGood,
      onTap: () {
        showMeasurementDetailSheet(
          context,
          measurement: m,
          type: _currentType,
          typeId: _selectedType,
          delta: delta,
          db: _db,
          onDeleted: _load,
        );
      },
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
    );
  }
}
