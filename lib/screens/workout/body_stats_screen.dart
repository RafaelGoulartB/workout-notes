import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/utils/body_progress_analytics.dart';
import 'package:workout_notes/utils/body_tracker_utils.dart';
import 'package:workout_notes/widgets/body_tracker/body_stats_charts.dart';
import 'package:workout_notes/widgets/empty_state_placeholder.dart';

/// Which trend chart the chart card is showing.
enum _BodyChartTab { weekly, delta, daily }

/// Progress statistics for body measurements: Sunday-to-Sunday weekly
/// averages, week-over-week comparison, rate of change, goal tracking and
/// logging consistency.
class BodyStatsScreen extends StatefulWidget {
  final String initialTypeId;

  /// Types the user chose to track on the dashboard. Falls back to every
  /// known type when empty.
  final List<MeasureType> types;

  const BodyStatsScreen({
    super.key,
    this.initialTypeId = 'weight',
    this.types = const [],
  });

  @override
  State<BodyStatsScreen> createState() => _BodyStatsScreenState();
}

class _BodyStatsScreenState extends State<BodyStatsScreen> {
  final _bodyRepo = BodyMeasurementRepository();
  final _settingsRepo = SettingsRepository();
  final _periodizationRepo = PeriodizationRepository();

  late String _selectedType;
  BodyStatsPeriod _period = BodyStatsPeriod.weeks12;
  _BodyChartTab _chartTab = _BodyChartTab.weekly;

  bool _loading = true;

  /// Every measurement row, newest first.
  List<Map<String, dynamic>> _allRows = [];

  /// Rows of the selected type, newest first.
  List<Map<String, dynamic>> _rows = [];

  /// Types that actually have at least one measurement.
  Set<String> _typesWithData = {};

  double? _heightCm;
  PeriodizationPhase? _phase;
  double? _phaseTargetWeightKg;

  List<MeasureType> get _types =>
      widget.types.isEmpty ? kBodyMeasureTypes : widget.types;

  MeasureType get _currentType => _types.firstWhere(
    (t) => t.id == _selectedType,
    orElse: () => kBodyMeasureTypes.first,
  );

  bool get _isDecreasingGood => isDecreasingGoodFor(_selectedType);

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialTypeId;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final all = await _bodyRepo.getBodyMeasurements(limit: 2000);
      final height = await _settingsRepo.getSetting(
        'nutrition_profile_height_cm',
      );
      final phase = await _loadPhase();
      if (!mounted) return;
      setState(() {
        _allRows = all;
        _rows = all.where((m) => m['type'] == _selectedType).toList();
        _typesWithData = all.map((m) => m['type'] as String).toSet();
        _heightCm = double.tryParse(height?.replaceAll(',', '.') ?? '');
        _phase = phase.$1;
        _phaseTargetWeightKg = phase.$2;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Active phase and its effective target weight, when a periodization plan
  /// is running. Both null when there is no plan — the goal card is hidden.
  Future<(PeriodizationPhase?, double?)> _loadPhase() async {
    try {
      final phase = await _periodizationRepo.getEffectivePhase(DateTime.now());
      if (phase == null) return (null, null);
      final target = await _periodizationRepo.getEffectiveTarget(phase.id);
      return (phase, target?.targetWeightKg);
    } catch (_) {
      return (null, null);
    }
  }

  void _switchType(String typeId) {
    // Every type is already in memory, so switching needs no new query.
    setState(() {
      _selectedType = typeId;
      _rows = _allRows.where((m) => m['type'] == typeId).toList();
    });
  }

  // ── Formatting ──────────────────────────────────────────────────────

  String get _unit => _currentType.unit;

  int get _decimals => _selectedType == 'bloodPressure' ? 0 : 1;

  String _value(double? v, {int? decimals}) =>
      v == null ? '--' : v.toStringAsFixed(decimals ?? _decimals);

  String _signed(double? v, {int decimals = 1}) {
    if (v == null) return '--';
    final sign = v > 0 ? '+' : v < 0 ? '-' : '';
    return '$sign${v.abs().toStringAsFixed(decimals)}';
  }

  String _shortDate(DateTime d) => DateFormat.MMMd(
    Localizations.localeOf(context).toString(),
  ).format(d);

  String _monthLabel(DateTime d) => DateFormat.yMMM(
    Localizations.localeOf(context).toString(),
  ).format(d);

  /// True when a change of [delta] moves in the direction the user wants.
  bool _isGood(double delta) => _isDecreasingGood ? delta < 0 : delta > 0;

  // ── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final analytics = BodyProgressAnalytics.fromRows(_rows, period: _period);

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.bodyStatsTitle),
        centerTitle: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _buildTypeSelector(),
                  const SizedBox(height: 12),
                  _buildPeriodSelector(loc),
                  if (analytics.isEmpty)
                    _buildEmpty(loc)
                  else ...[
                    const SizedBox(height: 16),
                    _buildWeekHero(loc, analytics),
                    _sectionHeader(loc.bodyStatsSectionChart),
                    _buildChartCard(loc, analytics),
                    _sectionHeader(loc.bodyStatsSectionRate),
                    _buildRateCard(loc, analytics),
                    if (_buildGoalCard(loc, analytics) case final goal?) ...[
                      _sectionHeader(loc.bodyStatsSectionGoal),
                      goal,
                    ],
                    _sectionHeader(loc.bodyStatsSectionConsistency),
                    _buildConsistencyCard(loc, analytics),
                    if (analytics.months.length >= 2) ...[
                      _sectionHeader(loc.bodyStatsSectionMonthly),
                      _buildMonthlyCard(loc, analytics),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionHeader(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 22, 0, 10),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets? padding}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildEmpty(AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.only(top: 48),
      child: EmptyStatePlaceholder(
        icon: Icons.insights_outlined,
        title: loc.bodyStatsEmptyTitle,
        subtitle: loc.bodyStatsEmptySubtitle,
      ),
    );
  }

  // ===================== TYPE SELECTOR =====================
  Widget _buildTypeSelector() {
    // Types without data would render an empty screen, so they are dropped —
    // except the current selection, which must stay visible.
    final visible = _types
        .where((t) => _typesWithData.contains(t.id) || t.id == _selectedType)
        .toList();
    if (visible.length < 2) return const SizedBox.shrink();

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final type = visible[i];
          final selected = type.id == _selectedType;
          return ChoiceChip(
            avatar: Icon(
              type.icon,
              size: 16,
              color: selected ? type.color : Theme.of(context).hintColor,
            ),
            label: Text(typeName(type.id, context)),
            labelStyle: Theme.of(context).textTheme.labelMedium,
            showCheckmark: false,
            selected: selected,
            onSelected: (_) => selected ? null : _switchType(type.id),
          );
        },
      ),
    );
  }

  // ===================== PERIOD SELECTOR =====================
  String _periodLabel(AppLocalizations loc, BodyStatsPeriod period) {
    return switch (period) {
      BodyStatsPeriod.weeks4 => loc.bodyStatsPeriod4Weeks,
      BodyStatsPeriod.weeks12 => loc.bodyStatsPeriod12Weeks,
      BodyStatsPeriod.weeks26 => loc.bodyStatsPeriod6Months,
      BodyStatsPeriod.all => loc.bodyStatsPeriodAll,
    };
  }

  Widget _buildPeriodSelector(AppLocalizations loc) {
    return Row(
      children: [
        for (final period in BodyStatsPeriod.values) ...[
          if (period != BodyStatsPeriod.values.first) const SizedBox(width: 8),
          Expanded(
            child: ChoiceChip(
              // Four periods share the row, so labels scale down instead of
              // being clipped on narrow screens.
              label: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(_periodLabel(loc, period), maxLines: 1),
                ),
              ),
              labelStyle: Theme.of(context).textTheme.labelMedium,
              labelPadding: EdgeInsets.zero,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
              showCheckmark: false,
              selected: _period == period,
              onSelected: (_) => setState(() => _period = period),
            ),
          ),
        ],
      ],
    );
  }

  // ===================== WEEK HERO =====================
  Widget _buildWeekHero(AppLocalizations loc, BodyProgressAnalytics a) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final divider = colors.outlineVariant.withAlpha(80);
    final comparison = a.weekComparison;
    final week = comparison.current;
    final delta = comparison.delta;
    final percent = comparison.percent;

    final String subtitle;
    if (comparison.reference == null) {
      subtitle = loc.bodyStatsNoComparison;
    } else if (comparison.referenceIsAdjacent) {
      subtitle = loc.bodyStatsVsPreviousWeek;
    } else {
      subtitle = loc.bodyStatsVsWeekOf(
        _shortDate(comparison.reference!.weekStart),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colors.surfaceContainerHighest.withAlpha(200),
            colors.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _currentType.color.withAlpha(40),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_view_week_outlined,
                  size: 18,
                  color: _currentType.color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.bodyStatsWeeklyAverage,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      loc.bodyStatsWeekRange(
                        _shortDate(week.weekStart),
                        _shortDate(week.weekEnd),
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        _value(week.average),
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.0,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _unit,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (delta != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _TrendPill(
                    label: '${_signed(delta, decimals: _decimals)} $_unit',
                    icon: delta.abs() < 0.05
                        ? Icons.trending_flat_rounded
                        : delta > 0
                        ? Icons.trending_up_rounded
                        : Icons.trending_down_rounded,
                    positive: delta.abs() < 0.05 ? null : _isGood(delta),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            week.hasData
                ? percent == null
                      ? subtitle
                      : '$subtitle · ${_signed(percent, decimals: 1)}%'
                : loc.bodyStatsNoWeekData,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (week.hasData) ...[
            const SizedBox(height: 4),
            Text(
              loc.bodyStatsWeekEntries(week.entryCount, week.dayCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Container(height: 1, color: divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.show_chart_rounded,
                  color: _currentType.color,
                  label: loc.bodyStatsPeriodAverage,
                  value: _value(a.averageValue),
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.south_rounded,
                  color: colors.secondary,
                  label: loc.bodyStatsMin,
                  value: _value(a.minValue),
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.north_rounded,
                  color: colors.tertiary,
                  label: loc.bodyStatsMax,
                  value: _value(a.maxValue),
                ),
              ),
              _HeroDivider(color: divider),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.height_rounded,
                  color: colors.onSurfaceVariant,
                  label: loc.bodyStatsAmplitude,
                  value: _value(a.amplitude),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===================== CHART =====================
  Widget _buildChartCard(AppLocalizations loc, BodyProgressAnalytics a) {
    final theme = Theme.of(context);
    final labels = {
      _BodyChartTab.weekly: loc.bodyStatsChartWeekly,
      _BodyChartTab.delta: loc.bodyStatsChartDelta,
      _BodyChartTab.daily: loc.bodyStatsChartDaily,
    };

    final chart = switch (_chartTab) {
      _BodyChartTab.weekly => BodyWeeklyAverageChart(
        weeks: a.weeks,
        averageValue: a.averageValue,
        color: _currentType.color,
        unit: _unit,
        emptyLabel: loc.bodyStatsChartWeeklyEmpty,
      ),
      _BodyChartTab.delta => BodyWeeklyDeltaChart(
        weeks: a.weeks,
        isDecreasingGood: _isDecreasingGood,
        unit: _unit,
        emptyLabel: loc.bodyStatsChartDeltaEmpty,
      ),
      _BodyChartTab.daily => BodyDailyTrendChart(
        daily: a.daily,
        smoothed: a.smoothed,
        color: _currentType.color,
        unit: _unit,
        emptyLabel: loc.bodyStatsChartDailyEmpty,
      ),
    };

    final legend = switch (_chartTab) {
      _BodyChartTab.weekly => loc.bodyStatsChartWeeklyLegend,
      _BodyChartTab.delta => loc.bodyStatsChartDeltaLegend,
      _BodyChartTab.daily => loc.bodyStatsChartDailyLegend,
    };

    return _card(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _ChartTabBar(
              selected: _chartTab,
              labels: labels,
              onChanged: (tab) => setState(() => _chartTab = tab),
            ),
          ),
          const SizedBox(height: 14),
          chart,
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              legend,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== RATE =====================
  Widget _buildRateCard(AppLocalizations loc, BodyProgressAnalytics a) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final rate = a.ratePerWeek;
    final ratePercent = a.ratePercentPerWeek;

    // A rate faster than 1%/week of body weight is worth flagging; the same
    // threshold reads fine for circumferences and body fat.
    final String? paceLabel;
    final bool paceGood;
    if (rate == null) {
      paceLabel = null;
      paceGood = true;
    } else if (rate.abs() < 0.02 ||
        (ratePercent != null && ratePercent.abs() < 0.1)) {
      paceLabel = loc.bodyStatsPaceStable;
      paceGood = true;
    } else if (ratePercent != null && ratePercent.abs() > 1.0) {
      paceLabel = loc.bodyStatsPaceAggressive;
      paceGood = false;
    } else {
      paceLabel = loc.bodyStatsPaceSustainable;
      paceGood = true;
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rate == null)
            Text(
              loc.bodyStatsRateUnavailable,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            )
          else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _signed(rate, decimals: 2),
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _unit,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      Text(
                        ratePercent == null
                            ? loc.bodyStatsRatePerWeek
                            : '${loc.bodyStatsRatePerWeek} · '
                                  '${_signed(ratePercent, decimals: 2)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (paceLabel != null)
                  _TrendPill(
                    label: paceLabel,
                    icon: paceGood
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                    positive: paceGood,
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.swap_vert_rounded,
                    color: _currentType.color,
                    label: loc.bodyStatsTotalChange,
                    value: _signed(a.totalChange, decimals: _decimals),
                    unit: _unit,
                  ),
                ),
                _HeroDivider(color: colors.outlineVariant.withAlpha(80)),
                Expanded(
                  child: _HeroMetric(
                    icon: Icons.timeline_rounded,
                    color: colors.tertiary,
                    label: loc.bodyStatsProjection,
                    value: _value(a.projectedValue(4)),
                    unit: _unit,
                  ),
                ),
                if (_bmi(a.lastValue) case final bmi?) ...[
                  _HeroDivider(color: colors.outlineVariant.withAlpha(80)),
                  Expanded(
                    child: _HeroMetric(
                      icon: Icons.accessibility_new_rounded,
                      color: colors.secondary,
                      label: loc.bodyStatsBmi,
                      value: bmi.toStringAsFixed(1),
                      unit: _bmiLabel(loc, bmi),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              loc.bodyStatsProjectionNote,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// BMI for the current weight, or null when the type is not weight or no
  /// height is configured in the nutrition profile.
  double? _bmi(double? weightKg) {
    final height = _heightCm;
    if (_selectedType != 'weight' || weightKg == null) return null;
    if (height == null || height < 80 || height > 260) return null;
    final meters = height / 100;
    return weightKg / (meters * meters);
  }

  String _bmiLabel(AppLocalizations loc, double bmi) {
    if (bmi < 18.5) return loc.bodyStatsBmiUnder;
    if (bmi < 25) return loc.bodyStatsBmiNormal;
    if (bmi < 30) return loc.bodyStatsBmiOver;
    return loc.bodyStatsBmiObese;
  }

  // ===================== GOAL =====================
  /// Null when there is nothing to track: the goal comes from the active
  /// periodization phase's target weight, which only applies to weight.
  Widget? _buildGoalCard(AppLocalizations loc, BodyProgressAnalytics a) {
    final target = _phaseTargetWeightKg;
    final phase = _phase;
    if (_selectedType != 'weight' || target == null || phase == null) {
      return null;
    }

    // The phase start is the honest anchor for progress: it is where the user
    // committed to the target. Falls back to the period start when the phase
    // began before any measurement.
    final startValue = _weightAt(phase.startDate) ?? a.firstValue;
    final progress = a.goalProgress(target, startValue: startValue);
    if (progress == null) return null;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final eta = progress.etaFrom(a.now);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  loc.bodyStatsGoalPhase(phase.name),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _TrendPill(
                label: progress.achieved
                    ? loc.bodyStatsGoalReached
                    : loc.bodyStatsGoalRemaining(
                        '${progress.remaining.toStringAsFixed(1)} $_unit',
                      ),
                icon: progress.achieved
                    ? Icons.emoji_events_outlined
                    : Icons.flag_outlined,
                positive: progress.onTrack,
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.fraction,
              minHeight: 10,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(
                progress.onTrack ? colors.primary : colors.error,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _GoalAnchor(
                  label: loc.bodyStatsGoalStart,
                  value: '${_value(progress.startValue)} $_unit',
                  alignment: CrossAxisAlignment.start,
                ),
              ),
              Expanded(
                child: _GoalAnchor(
                  label: loc.bodyStatsGoalCurrent,
                  value: '${_value(progress.currentValue)} $_unit',
                  alignment: CrossAxisAlignment.center,
                  emphasized: true,
                ),
              ),
              Expanded(
                child: _GoalAnchor(
                  label: loc.bodyStatsGoalTarget,
                  value: '${_value(progress.targetValue)} $_unit',
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          if (!progress.achieved) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  eta == null
                      ? Icons.error_outline_rounded
                      : Icons.event_available_outlined,
                  size: 16,
                  color: colors.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    eta == null
                        ? loc.bodyStatsGoalOffTrack
                        : loc.bodyStatsGoalEta(_shortDate(eta)),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Weight recorded closest to [date] — the first entry on or after it, or
  /// the last one before it when the phase started after the final entry.
  double? _weightAt(DateTime date) {
    final target = DateTime(date.year, date.month, date.day);
    // Rows come newest first, so the last match walking down is the closest
    // entry on or after the phase start.
    double? onOrAfter;
    double? before;
    for (final row in _rows) {
      final raw = row['date'];
      final value = (row['value'] as num?)?.toDouble();
      if (raw is! String || raw.length < 10 || value == null) continue;
      final d = DateTime.tryParse(raw.substring(0, 10));
      if (d == null) continue;
      if (d.isBefore(target)) {
        before ??= value;
      } else {
        onOrAfter = value;
      }
    }
    return onOrAfter ?? before;
  }

  // ===================== CONSISTENCY =====================
  Widget _buildConsistencyCard(AppLocalizations loc, BodyProgressAnalytics a) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final days = a.daysSinceLast;

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  icon: Icons.event_repeat_outlined,
                  color: _currentType.color,
                  label: loc.bodyStatsConsistencyWeeks,
                  value: '${a.weeksWithData}/${a.weeks.length}',
                ),
              ),
              _HeroDivider(color: colors.outlineVariant.withAlpha(80)),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.local_fire_department_outlined,
                  color: Colors.deepOrange,
                  label: loc.bodyStatsStreak,
                  value: loc.bodyStatsStreakWeeks(a.weekStreak),
                ),
              ),
              _HeroDivider(color: colors.outlineVariant.withAlpha(80)),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.receipt_long_outlined,
                  color: colors.secondary,
                  label: loc.bodyStatsEntriesPerWeek,
                  value: a.entriesPerWeek.toStringAsFixed(1),
                ),
              ),
              _HeroDivider(color: colors.outlineVariant.withAlpha(80)),
              Expanded(
                child: _HeroMetric(
                  icon: Icons.history_toggle_off_outlined,
                  color: colors.tertiary,
                  label: loc.bodyStatsDaysSinceLast,
                  value: days == null
                      ? '--'
                      : days == 0
                      ? loc.bodyStatsToday
                      : '$days',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: a.consistency,
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation(_currentType.color),
            ),
          ),
        ],
      ),
    );
  }

  // ===================== MONTHLY =====================
  Widget _buildMonthlyCard(AppLocalizations loc, BodyProgressAnalytics a) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Newest first, capped so a long history does not dominate the screen.
    final months = a.months.reversed.take(12).toList();

    return _card(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        children: [
          for (var i = 0; i < months.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                color: colors.outlineVariant.withAlpha(60),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _monthLabel(months[i].monthStart),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          loc.bodyStatsMonthEntries(months[i].entryCount),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${_value(months[i].average)} $_unit',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      Text(
                        '${_value(months[i].min)} – ${_value(months[i].max)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  if (months[i].deltaVsPreviousMonth case final delta?) ...[
                    const SizedBox(width: 10),
                    _DeltaBadge(
                      label: _signed(delta, decimals: _decimals),
                      positive: delta.abs() < 0.05 ? null : _isGood(delta),
                    ),
                  ] else
                    const SizedBox(width: 10 + 46),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small coloured pill for deltas, paces and goal status. A null [positive]
/// renders the neutral variant.
class _TrendPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool? positive;

  const _TrendPill({
    required this.label,
    required this.icon,
    required this.positive,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (positive) {
      true => colors.primary,
      false => colors.error,
      null => colors.onSurfaceVariant,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed-width signed delta used by the monthly rows.
class _DeltaBadge extends StatelessWidget {
  final String label;
  final bool? positive;

  const _DeltaBadge({required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final color = switch (positive) {
      true => colors.primary,
      false => colors.error,
      null => colors.onSurfaceVariant,
    };

    return Container(
      width: 46,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _HeroDivider extends StatelessWidget {
  final Color color;

  const _HeroDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: color,
    );
  }
}

class _HeroMetric extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final String? unit;

  const _HeroMetric({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 3),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.1,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (unit != null) ...[
                const SizedBox(width: 2),
                Text(
                  unit!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 10,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Start / now / target column under the goal progress bar.
class _GoalAnchor extends StatelessWidget {
  final String label;
  final String value;
  final CrossAxisAlignment alignment;
  final bool emphasized;

  const _GoalAnchor({
    required this.label,
    required this.value,
    required this.alignment,
    this.emphasized = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// Segmented pill row that swaps the chart shown in the trends card.
class _ChartTabBar extends StatelessWidget {
  final _BodyChartTab selected;
  final Map<_BodyChartTab, String> labels;
  final ValueChanged<_BodyChartTab> onChanged;

  const _ChartTabBar({
    required this.selected,
    required this.labels,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          for (final tab in _BodyChartTab.values)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(9),
                onTap: () => onChanged(tab),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: tab == selected
                        ? colors.primary.withAlpha(45)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[tab] ?? '',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: tab == selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: tab == selected
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
