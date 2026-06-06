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

  // ── Bilateral state ───────────────────────────────────────────────
  String? _selectedSide; // 'left', 'right', or null for 'all'
  List<Map<String, dynamic>> _leftMeasurements = [];
  List<Map<String, dynamic>> _rightMeasurements = [];

  // ── History pagination ────────────────────────────────────────────
  int _historyDisplayCount = 5;

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
    setState(() {
      _isLoading = true;
      _historyDisplayCount = 5;
    });
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
        _updateBilateralData(filtered);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateBilateralData(List<Map<String, dynamic>> filtered) {
    if (_currentType.isBilateral) {
      _leftMeasurements =
          filtered.where((m) => m['side'] == 'left').toList();
      _rightMeasurements =
          filtered.where((m) => m['side'] == 'right').toList();
      _selectedSide ??= 'all';
    } else {
      _leftMeasurements = [];
      _rightMeasurements = [];
      _selectedSide = null;
    }
  }

  Future<void> _switchType(String typeId) async {
    setState(() {
      _selectedType = typeId;
      _selectedSide = null;
      _historyDisplayCount = 5;
      _measurements =
          _allMeasurements.where((m) => m['type'] == typeId).toList();
      _updateBilateralData(_measurements);
    });
  }

  void _switchSide(String? side) {
    setState(() {
      _selectedSide = side;
      _historyDisplayCount = 5;
    });
  }

  void _loadMoreHistory() {
    setState(() => _historyDisplayCount += 5);
  }

  // ── Derived stats (unilateral) ─────────────────────────────────────
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

  // ── Derived stats (bilateral) ──────────────────────────────────────
  double? get _leftCurrentValue {
    if (_leftMeasurements.isEmpty) return null;
    return (_leftMeasurements.first['value'] as num?)?.toDouble();
  }

  double? get _rightCurrentValue {
    if (_rightMeasurements.isEmpty) return null;
    return (_rightMeasurements.first['value'] as num?)?.toDouble();
  }

  double? get _leftDelta {
    if (_leftMeasurements.length < 2) return null;
    final current = (_leftMeasurements[0]['value'] as num).toDouble();
    final previous = (_leftMeasurements[1]['value'] as num).toDouble();
    return current - previous;
  }

  double? get _rightDelta {
    if (_rightMeasurements.length < 2) return null;
    final current = (_rightMeasurements[0]['value'] as num).toDouble();
    final previous = (_rightMeasurements[1]['value'] as num).toDouble();
    return current - previous;
  }

  List<Map<String, dynamic>> get _bilateralFilteredMeasurements {
    if (_selectedSide == 'left') return _leftMeasurements;
    if (_selectedSide == 'right') return _rightMeasurements;
    return _measurements; // 'all'
  }

  double? get _bilateralMinValue {
    final list = _bilateralFilteredMeasurements;
    if (list.isEmpty) return null;
    return list
        .map((m) => (m['value'] as num).toDouble())
        .reduce((a, b) => a < b ? a : b);
  }

  double? get _bilateralMaxValue {
    final list = _bilateralFilteredMeasurements;
    if (list.isEmpty) return null;
    return list
        .map((m) => (m['value'] as num).toDouble())
        .reduce((a, b) => a > b ? a : b);
  }

  double? get _bilateralAvgValue {
    final list = _bilateralFilteredMeasurements;
    if (list.isEmpty) return null;
    return list
            .map((m) => (m['value'] as num).toDouble())
            .reduce((a, b) => a + b) /
        list.length;
  }

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
    final isBilateral = _currentType.isBilateral;

    // Determine which data to use for history (chart uses all data)
    final historyList = isBilateral
        ? _bilateralFilteredMeasurements
        : _measurements;

    return Column(
      children: [
        BodyTypeSelector(
          types: _types,
          selectedType: _selectedType,
          onSelected: _switchType,
        ),
        const SizedBox(height: 12),

        // Summary card — bilateral or unilateral
        if (isBilateral)
          BodyBilateralSummaryCard(
            type: _currentType,
            leftValue: _leftCurrentValue,
            rightValue: _rightCurrentValue,
            leftDelta: _leftDelta,
            rightDelta: _rightDelta,
            isDecreasingGood: _isDecreasingGood,
            leftMeasurements: _leftMeasurements,
            rightMeasurements: _rightMeasurements,
          )
        else
          BodySummaryCard(
            type: _currentType,
            value: _currentValue,
            delta: _delta,
            isDecreasingGood: _isDecreasingGood,
            measurements: _measurements,
          ),

        // Quick stats (only for unilateral)
        if (!isBilateral && _measurements.isNotEmpty) ...[
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
              // ── Chart ──────────────────────────────────────────────
              if (_measurements.length >= 2) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: isBilateral
                      ? BodyBilateralChartCard(
                          leftMeasurements: _leftMeasurements,
                          rightMeasurements: _rightMeasurements,
                          type: _currentType,
                        )
                      : BodyChartCard(
                          measurements: _measurements,
                          type: _currentType,
                        ),
                ),
              ],

              // ── Quick stats for bilateral ──────────────────────────
              if (isBilateral && historyList.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: BodyQuickStats(
                    minValue: _bilateralMinValue,
                    maxValue: _bilateralMaxValue,
                    avgValue: _bilateralAvgValue,
                    totalCount: historyList.length,
                    typeColor: _currentType.color,
                  ),
                ),
              ],

              // ── Body composition (weight only) ─────────────────────
              if (!isBilateral &&
                  _measurements.isNotEmpty &&
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

              // ── Side tabs (bilateral only) ─────────────────────────
              if (isBilateral && _measurements.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: _buildSideTabs(theme, loc),
                ),
              ],

              // ── History header ─────────────────────────────────────
              if (historyList.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Icon(Icons.history,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isBilateral
                                ? '${loc.bodyTrackerHistory} · ${historyList.length} ${loc.bodyTrackerEntries}'
                                : '${loc.bodyTrackerHistory} · ${_measurements.length} ${loc.bodyTrackerEntries}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
              ],

              // ── History list (paginated) ──────────────────────────
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _buildMeasurementCard(theme, loc, i, historyList),
                  childCount: historyList.length > _historyDisplayCount
                      ? _historyDisplayCount
                      : historyList.length,
                ),
              ),

              // ── Load more button ───────────────────────────────────
              if (historyList.length > _historyDisplayCount) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverToBoxAdapter(
                  child: _buildLoadMoreButton(theme, loc, historyList),
                ),
              ],

              const SliverToBoxAdapter(child: SizedBox(height: 80)),
            ],
          ),
        ),
      ],
    );
  }

  /// Minimalistic "+ Load more" button for paginated history.
  Widget _buildLoadMoreButton(ThemeData theme, AppLocalizations loc, List<Map<String, dynamic>> list) {
    final remaining = list.length - _historyDisplayCount;
    final remainingText = remaining > 5
        ? loc.bodyTrackerLoadMore(remaining)
        : loc.bodyTrackerLoadMoreCount(remaining);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: InkWell(
        onTap: _loadMoreHistory,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          width: double.infinity,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.add, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                remainingText,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSideTabs(ThemeData theme, AppLocalizations loc) {
    final tabs = <Widget>[
      _SideTab(
        label: loc.commonAll,
        icon: Icons.sync_alt,
        isSelected: _selectedSide == 'all' || _selectedSide == null,
        color: theme.colorScheme.primary,
        count: _measurements.length,
        theme: theme,
        onTap: () => _switchSide('all'),
      ),
      _SideTab(
        label: loc.bodyTrackerLeftAbbr,
        icon: Icons.arrow_back,
        isSelected: _selectedSide == 'left',
        color: Colors.blue,
        count: _leftMeasurements.length,
        theme: theme,
        onTap: () => _switchSide('left'),
      ),
      _SideTab(
        label: loc.bodyTrackerRightAbbr,
        icon: Icons.arrow_forward,
        isSelected: _selectedSide == 'right',
        color: Colors.red,
        count: _rightMeasurements.length,
        theme: theme,
        onTap: () => _switchSide('right'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: tabs.map((t) => Expanded(child: t)).toList(),
      ),
    );
  }

  Widget _buildMeasurementCard(ThemeData theme, AppLocalizations loc, int index, List<Map<String, dynamic>> list) {
    final m = list[index];
    final value = (m['value'] as num).toDouble();
    final isBilateral = _currentType.isBilateral;
    final side = m['side'] as String?;

    // Delta: compare only with the previous entry of the SAME side
    // (prevents comparing left vs right when viewing "All")
    double? delta;
    for (int j = index + 1; j < list.length; j++) {
      final prev = list[j];
      if (!isBilateral || prev['side'] == side) {
        final prevVal = (prev['value'] as num).toDouble();
        delta = value - prevVal;
        break;
      }
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

// ═══════════════════════════════════════════════════════════════════════
// SIDE TAB (inline filter button for bilateral measurements)
// ═══════════════════════════════════════════════════════════════════════

/// Compact filter button used in the side selector for bilateral types.
class _SideTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final Color color;
  final int count;
  final ThemeData theme;
  final VoidCallback onTap;

  const _SideTab({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.color,
    required this.count,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? color.withAlpha(120)
                  : theme.colorScheme.outlineVariant.withAlpha(50),
            ),
            color: isSelected ? color.withAlpha(18) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isSelected ? color : theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                  color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? color.withAlpha(30) : theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? color : theme.colorScheme.onSurfaceVariant,
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
