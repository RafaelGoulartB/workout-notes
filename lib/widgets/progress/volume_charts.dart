import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/utils/progress_helpers.dart';

/// Self-contained "Volume & muscle groups" section for anaerobic training.
///
/// State: period bucket (week / month / year), volume metric (weight or
/// sets) and category view (pie / list). All charts and lists are filtered
/// by anaerobic energy system only.
class VolumeCharts extends StatefulWidget {
  final AnalyticsRepository analytics;

  const VolumeCharts({super.key, required this.analytics});

  @override
  State<VolumeCharts> createState() => _VolumeChartsState();
}

class _VolumeChartsState extends State<VolumeCharts> {
  AnaerobicTrendBucket _bucket = AnaerobicTrendBucket.month;
  bool _bySets = false;

  bool _isLoading = true;
  List<Map<String, dynamic>> _trend = [];
  List<Map<String, dynamic>> _topExercises = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final (start, end) = _currentRange();
      final results = await Future.wait([
        widget.analytics.getAnaerobicVolumeTrend(end, _bucket, bySets: _bySets),
        widget.analytics.getAnaerobicTopExercises(start, end, bySets: _bySets),
      ]);
      if (!mounted) return;
      setState(() {
        _trend = results[0];
        _topExercises = results[1];
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  (DateTime, DateTime) _currentRange() {
    final now = DateTime.now();
    if (_bucket == AnaerobicTrendBucket.week) {
      final endMonday = now.subtract(Duration(days: now.weekday - 1));
      final start = endMonday.subtract(const Duration(days: 7 * 11));
      final end = endMonday.add(const Duration(days: 6));
      return (start, end);
    } else if (_bucket == AnaerobicTrendBucket.month) {
      final ref = DateTime(now.year, now.month - 11, 1);
      final nextMonth = DateTime(now.year, now.month + 1, 1);
      final end = nextMonth.subtract(const Duration(days: 1));
      return (ref, end);
    } else {
      final start = DateTime(now.year - 4, 1, 1);
      final end = DateTime(now.year, 12, 31);
      return (start, end);
    }
  }

  String _formatValue(double v) {
    if (_bySets) return v.toStringAsFixed(0);
    return formatVolume(v);
  }

  String _unitLabel(AppLocalizations loc) {
    return _bySets ? loc.progressVolumeUnitSets : loc.progressVolumeUnitWeight;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (_isLoading && _trend.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    final (start, end) = _currentRange();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControls(theme, loc),
        const SizedBox(height: 12),
        _TrendChart(
          data: _trend,
          bucket: _bucket,
          bySets: _bySets,
          formatValue: _formatValue,
          unitLabel: _unitLabel(loc),
        ),
        const SizedBox(height: 12),
        _CategoryCard(analytics: widget.analytics, start: start, end: end),
        if (_topExercises.isNotEmpty) ...[
          const SizedBox(height: 12),
          _TopExercisesChart(
            data: _topExercises,
            bySets: _bySets,
            formatValue: _formatValue,
          ),
        ],
        const SizedBox(height: 4),
        if (_isLoading)
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: theme.colorScheme.primary.withAlpha(180),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(ThemeData theme, AppLocalizations loc) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _CompactSegmentedButton<AnaerobicTrendBucket>(
            selected: _bucket,
            onChanged: (v) {
              setState(() => _bucket = v);
              _load();
            },
            segments: [
              (AnaerobicTrendBucket.week, loc.progressPeriodWeek),
              (AnaerobicTrendBucket.month, loc.progressPeriodMonth),
              (AnaerobicTrendBucket.year, loc.progressPeriodYear),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _CompactSegmentedButton<bool>(
            selected: _bySets,
            onChanged: (v) {
              setState(() => _bySets = v);
              _load();
            },
            segments: [
              (false, loc.progressVolumeTypeWeight),
              (true, loc.progressVolumeTypeSets),
            ],
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// COMPACT SEGMENTED BUTTON
// =====================================================================

class _CompactSegmentedButton<T> extends StatelessWidget {
  final T selected;
  final ValueChanged<T> onChanged;
  final List<(T, String)> segments;

  const _CompactSegmentedButton({
    required this.selected,
    required this.onChanged,
    required this.segments,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        children: segments.map((s) {
          final isSel = s.$1 == selected;
          return Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onChanged(s.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: isSel ? theme.colorScheme.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  s.$2,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isSel
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// =====================================================================
// TREND BAR CHART
// =====================================================================

class _TrendChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final AnaerobicTrendBucket bucket;
  final bool bySets;
  final String Function(double) formatValue;
  final String unitLabel;

  const _TrendChart({
    required this.data,
    required this.bucket,
    required this.bySets,
    required this.formatValue,
    required this.unitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final volumes = data
        .map((m) => (m['volume'] as num?)?.toDouble() ?? 0)
        .toList();
    final maxVol = volumes.fold<double>(0, (a, b) => a > b ? a : b);
    final hasData = maxVol > 0;

    return _PrettyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: loc.progressVolumeTrend,
            subtitle: _periodLabel(loc),
            accent: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          if (!hasData)
            _EmptyChart(icon: Icons.show_chart, message: loc.progressNoData)
          else
            SizedBox(
              height: 130,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceBetween,
                  maxY: maxVol * 1.25,
                  minY: 0,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBorderRadius: BorderRadius.circular(10),
                      tooltipPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      getTooltipColor: (_) => theme.colorScheme.inverseSurface,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final m = data[groupIndex];
                        final start = m['bucket_start'] as String? ?? '';
                        final vol = (m['volume'] as num?)?.toDouble() ?? 0;
                        return BarTooltipItem(
                          '${_tooltipLabel(start)}\n${formatValue(vol)} $unitLabel',
                          TextStyle(
                            color: theme.colorScheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 22,
                        getTitlesWidget: (v, _) {
                          final idx = v.toInt();
                          if (idx < 0 || idx >= data.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              _axisLabel(
                                data[idx]['bucket_start'] as String? ?? '',
                                idx,
                                data.length,
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
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
                          return Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              formatValue(v),
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: maxVol > 0
                        ? niceInterval(maxVol / 4)
                        : 1,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: theme.colorScheme.outlineVariant.withAlpha(60),
                      strokeWidth: 1,
                      dashArray: const [3, 4],
                    ),
                  ),
                  barGroups: data.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final vol =
                        (entry.value['volume'] as num?)?.toDouble() ?? 0;
                    return BarChartGroupData(
                      x: idx,
                      barRods: [
                        BarChartRodData(
                          toY: vol,
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              theme.colorScheme.primary.withAlpha(180),
                              theme.colorScheme.primary,
                            ],
                          ),
                          width: bucket == AnaerobicTrendBucket.year ? 22 : 11,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: maxVol,
                            color: theme.colorScheme.surfaceContainerHighest
                                .withAlpha(60),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: const [],
                    );
                  }).toList(),
                ),
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
              ),
            ),
        ],
      ),
    );
  }

  String _periodLabel(AppLocalizations loc) {
    switch (bucket) {
      case AnaerobicTrendBucket.week:
        return loc.progressVolumeTrendLast12Weeks;
      case AnaerobicTrendBucket.month:
        return loc.progressVolumeTrendLast12Months;
      case AnaerobicTrendBucket.year:
        return loc.progressVolumeTrendLast5Years;
    }
  }

  String _axisLabel(String iso, int idx, int total) {
    if (iso.length < 10) return '';
    final dt = DateTime.parse(iso);
    final showAll = total <= 8;
    if (!showAll && idx % 2 != 0 && idx != total - 1) return '';
    switch (bucket) {
      case AnaerobicTrendBucket.week:
        return '${dt.day}/${dt.month}';
      case AnaerobicTrendBucket.month:
        return dt.month.toString().padLeft(2, '0');
      case AnaerobicTrendBucket.year:
        return dt.year.toString().substring(2);
    }
  }

  String _tooltipLabel(String iso) {
    if (iso.length < 10) return '';
    final dt = DateTime.parse(iso);
    switch (bucket) {
      case AnaerobicTrendBucket.week:
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
      case AnaerobicTrendBucket.month:
        return '${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      case AnaerobicTrendBucket.year:
        return dt.year.toString();
    }
  }
}

// =====================================================================
// CATEGORY CARD (pie / list + weight / sets toggle)
// =====================================================================

enum _CategoryView { pie, list }

class _CategoryCard extends StatefulWidget {
  final AnalyticsRepository analytics;
  final DateTime start;
  final DateTime end;

  const _CategoryCard({
    required this.analytics,
    required this.start,
    required this.end,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  _CategoryView _view = _CategoryView.pie;
  bool _bySets = true;
  bool _isLoading = true;
  List<Map<String, dynamic>> _data = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _CategoryCard old) {
    super.didUpdateWidget(old);
    if (old.start != widget.start || old.end != widget.end) {
      _load();
    }
  }

  Future<void> _load() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      final data = await widget.analytics.getAnaerobicVolumeByCategory(
        widget.start,
        widget.end,
        bySets: _bySets,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatValue(double v) {
    if (_bySets) return v.toStringAsFixed(0);
    return formatVolume(v);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final unitLabel = _bySets
        ? loc.progressVolumeUnitSets
        : loc.progressVolumeUnitWeight;

    final headerToggles = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SegmentedIconToggle<_CategoryView>(
          current: _view,
          onChanged: (v) => setState(() => _view = v),
          option1: (
            _CategoryView.pie,
            Icons.pie_chart_outline,
            loc.progressVolumeViewPie,
          ),
          option2: (
            _CategoryView.list,
            Icons.view_list,
            loc.progressVolumeViewList,
          ),
        ),
        const SizedBox(width: 6),
        _SegmentedIconToggle<bool>(
          current: _bySets,
          onChanged: (v) {
            setState(() => _bySets = v);
            _load();
          },
          option1: (false, Icons.fitness_center, loc.progressVolumeTypeWeight),
          option2: (
            true,
            Icons.format_list_numbered,
            loc.progressVolumeTypeSets,
          ),
        ),
      ],
    );

    if (_data.isEmpty && !_isLoading) {
      return _PrettyCard(
        child: _SectionHeader(
          title: loc.progressVolumeByGroup,
          trailing: headerToggles,
        ),
      );
    }

    final total = _data.fold<double>(
      0,
      (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0),
    );

    return _PrettyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: loc.progressVolumeByGroup,
            subtitle:
                '${loc.progressVolumeTotal} · ${_formatValue(total)} $unitLabel',
            trailing: headerToggles,
          ),
          const SizedBox(height: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.04),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _isLoading
                ? const _CategoryLoading(key: ValueKey('loading'))
                : _view == _CategoryView.pie
                ? _CategoryPie(
                    key: const ValueKey('pie'),
                    data: _data,
                    total: total,
                    formatValue: _formatValue,
                    unitLabel: unitLabel,
                  )
                : _CategoryList(
                    key: const ValueKey('list'),
                    data: _data,
                    formatValue: _formatValue,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryLoading extends StatelessWidget {
  const _CategoryLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 150,
      child: Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _CategoryPie extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final double total;
  final String Function(double) formatValue;
  final String unitLabel;

  const _CategoryPie({
    super.key,
    required this.data,
    required this.total,
    required this.formatValue,
    required this.unitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 1,
                      centerSpaceRadius: 22,
                      startDegreeOffset: -90,
                      sections: data.take(8).map((e) {
                        final vol = (e['volume'] as num?)?.toDouble() ?? 0;
                        final pct = total > 0 ? vol / total * 100 : 0.0;
                        final base = Color(e['color'] as int? ?? 0xFF757575);
                        return PieChartSectionData(
                          color: base,
                          value: vol,
                          title: pct >= 8 ? '${pct.toStringAsFixed(0)}%' : '',
                          titleStyle: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          titlePositionPercentageOffset: 0.65,
                          radius: pct >= 15 ? 40 : 34,
                          borderSide: BorderSide(
                            color: theme.colorScheme.surface,
                            width: 1.5,
                          ),
                        );
                      }).toList(),
                    ),
                    duration: const Duration(milliseconds: 400),
                    curve: Curves.easeOutCubic,
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatValue(total),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: theme.colorScheme.onSurface,
                          fontSize: 13,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        unitLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 9,
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                          height: 1.0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: data.take(5).map((cat) {
              final vol = (cat['volume'] as num?)?.toDouble() ?? 0;
              final pct = total > 0 ? vol / total * 100 : 0.0;
              final color = Color(cat['color'] as int? ?? 0xFF757575);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, cat)} ${pct.toStringAsFixed(0)}%',
                      style: const TextStyle(fontSize: 8),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _CategoryList extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final String Function(double) formatValue;

  const _CategoryList({
    super.key,
    required this.data,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxVol = data.fold<double>(
      0,
      (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0),
    );
    final rows = data.take(6).toList();

    return Column(
      children: rows.asMap().entries.map((entry) {
        final idx = entry.key;
        final cat = entry.value;
        final vol = (cat['volume'] as num?)?.toDouble() ?? 0;
        final pct = maxVol > 0 ? vol / maxVol : 0.0;
        final color = Color(cat['color'] as int? ?? 0xFF757575);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              _RankBadge(rank: idx + 1, color: color),
              const SizedBox(width: 8),
              SizedBox(
                width: 86,
                child: Text(
                  ExerciseLocaleHelper.categoryName(
                    AppLocalizations.of(context)!,
                    cat,
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Stack(
                    children: [
                      Container(
                        height: 12,
                        color: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(120),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct.clamp(0.0, 1.0),
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [color.withAlpha(180), color],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 50,
                child: Text(
                  formatValue(vol),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _RankBadge extends StatelessWidget {
  final int rank;
  final Color color;

  const _RankBadge({required this.rank, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = rank <= 3;
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: highlight
            ? color.withAlpha(40)
            : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(6),
        border: highlight
            ? Border.all(color: color.withAlpha(120), width: 1)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        '$rank',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: highlight ? color : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// =====================================================================
// TOP EXERCISES
// =====================================================================

class _TopExercisesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;
  final bool bySets;
  final String Function(double) formatValue;

  const _TopExercisesChart({
    required this.data,
    required this.bySets,
    required this.formatValue,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final maxVol = data.fold<double>(0, (a, b) {
      final v = (b['volume'] as num?)?.toDouble() ?? 0;
      return a > v ? a : v;
    });
    final rows = data.take(5).toList();

    return _PrettyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: loc.progressTopExercises,
            accent: theme.colorScheme.primary,
          ),
          const SizedBox(height: 10),
          ...rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final ex = entry.value;
            final vol = (ex['volume'] as num?)?.toDouble() ?? 0;
            final pct = maxVol > 0 ? vol / maxVol : 0.0;
            final catColor = Color(ex['category_color'] as int? ?? 0xFF757575);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  _RankBadge(rank: idx + 1, color: catColor),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 96,
                    child: Text(
                      ExerciseLocaleHelper.exerciseName(
                        AppLocalizations.of(context)!,
                        ex,
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Stack(
                        children: [
                          Container(
                            height: 12,
                            color: theme.colorScheme.surfaceContainerHighest
                                .withAlpha(120),
                          ),
                          FractionallySizedBox(
                            widthFactor: pct.clamp(0.0, 1.0),
                            child: Container(
                              height: 12,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [catColor.withAlpha(180), catColor],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatValue(vol),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// =====================================================================
// SHARED SUB-WIDGETS
// =====================================================================

class _PrettyCard extends StatelessWidget {
  final Widget child;

  const _PrettyCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Color? accent;
  final Widget? trailing;

  const _SectionHeader({
    required this.title,
    this.subtitle,
    this.accent,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (accent != null) ...[
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _SegmentedIconToggle<T> extends StatelessWidget {
  final T current;
  final ValueChanged<T> onChanged;
  final (T, IconData, String) option1;
  final (T, IconData, String) option2;

  const _SegmentedIconToggle({
    required this.current,
    required this.onChanged,
    required this.option1,
    required this.option2,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleButton(
            icon: option1.$2,
            tooltip: option1.$3,
            isSelected: current == option1.$1,
            onTap: () => onChanged(option1.$1),
          ),
          _ToggleButton(
            icon: option2.$2,
            tooltip: option2.$3,
            isSelected: current == option2.$1,
            onTap: () => onChanged(option2.$1),
          ),
        ],
      ),
    );
  }
}

class _ToggleButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isSelected;
  final VoidCallback onTap;

  const _ToggleButton({
    required this.icon,
    required this.tooltip,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: isSelected ? theme.colorScheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 15,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyChart({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 28,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
