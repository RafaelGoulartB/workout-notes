import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_fitness_analytics.dart';

/// GitHub-style year calendar for strength training, same look as the running
/// one: one square per day, shaded by the working sets done (quartiles of the
/// lifter's own training days). Weeks are columns starting on Monday; the grid
/// scrolls sideways and opens on the current week. Tapping a day shows its
/// sets underneath.
class StrengthHeatmap extends StatefulWidget {
  final int year;

  /// Working sets per local calendar day.
  final Map<DateTime, double> daily;
  final DateTime today;

  const StrengthHeatmap({
    super.key,
    required this.year,
    required this.daily,
    required this.today,
  });

  @override
  State<StrengthHeatmap> createState() => _StrengthHeatmapState();
}

class _StrengthHeatmapState extends State<StrengthHeatmap> {
  static const double _cell = 14;
  static const double _gap = 3;
  static const double _step = _cell + _gap;
  static const double _monthLabelHeight = 18;

  final _scroll = ScrollController();
  DateTime? _selected;

  late DateTime _gridStart;
  late int _weeks;
  late List<double> _thresholds;

  @override
  void initState() {
    super.initState();
    _computeGrid();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
  }

  @override
  void didUpdateWidget(StrengthHeatmap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.year != widget.year || oldWidget.daily != widget.daily) {
      _selected = null;
      _computeGrid();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToToday());
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _computeGrid() {
    final jan1 = DateTime(widget.year);
    _gridStart = jan1.subtract(Duration(days: jan1.weekday - 1));
    final dec31 = DateTime(widget.year, 12, 31);
    final gridEnd = dec31.add(Duration(days: 7 - dec31.weekday));
    _weeks = (gridEnd.difference(_gridStart).inDays + 1) ~/ 7;
    _thresholds = RunFitnessAnalytics.heatThresholds(widget.daily.values);
  }

  void _scrollToToday() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (widget.today.year != widget.year) {
      _scroll.jumpTo(position.minScrollExtent);
      return;
    }
    final column = widget.today.difference(_gridStart).inDays ~/ 7;
    final target = (column + 1) * _step - position.viewportDimension + _gap;
    _scroll.jumpTo(target.clamp(0.0, position.maxScrollExtent));
  }

  DateTime _dateAt(int column, int row) => DateTime(
    _gridStart.year,
    _gridStart.month,
    _gridStart.day + column * 7 + row,
  );

  void _onTap(Offset local) {
    final column = (local.dx / _step).floor();
    final row = ((local.dy - _monthLabelHeight) / _step).floor();
    if (column < 0 || column >= _weeks || row < 0 || row > 6) return;
    final date = _dateAt(column, row);
    if (date.year != widget.year) return;
    setState(() => _selected = date);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final weekday = DateFormat.E(locale);
    final activeDays = widget.daily.length;
    final selected = _selected;
    final selectedText = selected == null
        ? null
        : (widget.daily[selected] ?? 0) > 0
        ? loc.strengthInsightsHeatDay(
            DateFormat.yMMMd(locale).format(selected),
            loc.strengthInsightsSetsCount(widget.daily[selected]!.round()),
          )
        : loc.strengthInsightsHeatRest(
            DateFormat.yMMMd(locale).format(selected),
          );

    final levelColors = [
      colors.surfaceContainerHighest.withValues(alpha: 0.55),
      for (final a in const [0.28, 0.5, 0.75, 1.0])
        colors.primary.withValues(alpha: a),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 30,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: _monthLabelHeight),
                  for (var row = 0; row < 7; row++)
                    SizedBox(
                      height: _step,
                      child: row.isEven
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                weekday
                                    .format(DateTime(2024, 1, 1 + row))
                                    .replaceAll('.', ''),
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontSize: 9,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            )
                          : null,
                    ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _onTap(d.localPosition),
                  child: CustomPaint(
                    size: Size(_weeks * _step, _monthLabelHeight + 7 * _step),
                    painter: _HeatmapPainter(
                      year: widget.year,
                      today: widget.today,
                      gridStart: _gridStart,
                      weeks: _weeks,
                      daily: widget.daily,
                      thresholds: _thresholds,
                      levelColors: levelColors,
                      outline: colors.outlineVariant.withValues(alpha: 0.5),
                      selected: selected,
                      selectedColor: colors.onSurface,
                      labelStyle:
                          theme.textTheme.labelSmall?.copyWith(
                            fontSize: 10,
                            color: colors.onSurfaceVariant,
                          ) ??
                          const TextStyle(fontSize: 10),
                      monthNames: [
                        for (var m = 1; m <= 12; m++)
                          DateFormat.MMM(locale).format(DateTime(2024, m)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                selectedText ?? loc.strengthInsightsActiveDays(activeDays),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
            Text(
              loc.runInsightsHeatLess,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            for (final c in levelColors)
              Container(
                width: 11,
                height: 11,
                margin: const EdgeInsets.only(left: 2),
                decoration: BoxDecoration(
                  color: c,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            const SizedBox(width: 4),
            Text(
              loc.runInsightsHeatMore,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeatmapPainter extends CustomPainter {
  final int year;
  final DateTime today;
  final DateTime gridStart;
  final int weeks;
  final Map<DateTime, double> daily;
  final List<double> thresholds;
  final List<Color> levelColors;
  final Color outline;
  final DateTime? selected;
  final Color selectedColor;
  final TextStyle labelStyle;
  final List<String> monthNames;

  const _HeatmapPainter({
    required this.year,
    required this.today,
    required this.gridStart,
    required this.weeks,
    required this.daily,
    required this.thresholds,
    required this.levelColors,
    required this.outline,
    required this.selected,
    required this.selectedColor,
    required this.labelStyle,
    required this.monthNames,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const cell = _StrengthHeatmapState._cell;
    const step = _StrengthHeatmapState._step;
    const top = _StrengthHeatmapState._monthLabelHeight;
    final radius = const Radius.circular(3);
    final todayOnly = DateTime(today.year, today.month, today.day);
    var lastLabelEnd = -100.0;

    // Month name above the column that holds the 1st of the month.
    for (var column = 0; column < weeks; column++) {
      for (var row = 0; row < 7; row++) {
        final date = DateTime(
          gridStart.year,
          gridStart.month,
          gridStart.day + column * 7 + row,
        );
        if (date.year != year || date.day != 1) continue;
        final x = column * step;
        if (x - lastLabelEnd < 4) continue;
        final painter = TextPainter(
          text: TextSpan(text: monthNames[date.month - 1], style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x, 0));
        lastLabelEnd = x + painter.width;
      }
    }

    for (var column = 0; column < weeks; column++) {
      for (var row = 0; row < 7; row++) {
        final date = DateTime(
          gridStart.year,
          gridStart.month,
          gridStart.day + column * 7 + row,
        );
        if (date.year != year) continue;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(column * step, top + row * step, cell, cell),
          radius,
        );
        final meters = daily[date] ?? 0;
        final level = RunFitnessAnalytics.heatLevel(meters, thresholds);
        canvas.drawRRect(rect, Paint()..color = levelColors[level]);
        if (date.isAfter(todayOnly)) {
          canvas.drawRRect(
            rect,
            Paint()
              ..color = outline
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.8,
          );
        }
        if (selected != null && selected == date) {
          canvas.drawRRect(
            rect.inflate(1),
            Paint()
              ..color = selectedColor
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => true;
}
