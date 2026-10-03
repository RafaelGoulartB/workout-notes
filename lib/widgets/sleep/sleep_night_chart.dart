import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_night_timeline.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// The night minute by minute: estimated state, the model's chance of sleep
/// and the sound heard (the person vs the room). Drag or tap to inspect a
/// minute.
class SleepNightChart extends StatefulWidget {
  final SleepNightTimeline timeline;
  final DateTime startedAt;
  final int utcOffsetMinutes;

  /// Start of the smart alarm window, shaded to the end of the night.
  final DateTime? smartWindowStart;

  /// When the alarm rang, drawn as a vertical mark.
  final DateTime? alarmFiredAt;

  const SleepNightChart({
    super.key,
    required this.timeline,
    required this.startedAt,
    required this.utcOffsetMinutes,
    this.smartWindowStart,
    this.alarmFiredAt,
  });

  @override
  State<SleepNightChart> createState() => _SleepNightChartState();
}

class _SleepNightChartState extends State<SleepNightChart> {
  static const height = 196.0;
  int? _selected;

  int _indexAt(double dx, double width) {
    final n = widget.timeline.length;
    return (dx / width * n).floor().clamp(0, n - 1);
  }

  void _select(double dx, double width) {
    final index = _indexAt(dx, width);
    if (index != _selected) setState(() => _selected = index);
  }

  double? _stepOf(DateTime? time) => time == null
      ? null
      : time.difference(widget.startedAt).inMilliseconds /
            1000 /
            widget.timeline.stepSeconds;

  String _clockAt(int step) => SleepUi.wallTime(
    widget.startedAt.add(Duration(seconds: step * widget.timeline.stepSeconds)),
    widget.utcOffsetMinutes,
  );

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final timeline = widget.timeline;
    final selected = _selected;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Readout(
          child: selected == null
              ? Text(
                  loc.sleepChartHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                )
              : _TooltipBody(
                  timeline: timeline,
                  index: selected,
                  clock: _clockAt(selected),
                ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Semantics(
              label: loc.sleepChartSemantics(
                _clockAt(0),
                _clockAt(timeline.length),
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) => _select(d.localPosition.dx, width),
                onHorizontalDragStart: (d) =>
                    _select(d.localPosition.dx, width),
                onHorizontalDragUpdate: (d) =>
                    _select(d.localPosition.dx, width),
                child: SizedBox(
                  height: height,
                  width: width,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _NightPainter(
                            timeline: timeline,
                            startedAt: widget.startedAt,
                            utcOffsetMinutes: widget.utcOffsetMinutes,
                            selected: selected,
                            labels: (
                              loc.sleepChartStageRow,
                              loc.sleepChartProbabilityRow,
                              loc.sleepChartSoundRow,
                            ),
                            ink: colors.onSurface,
                            muted: colors.onSurfaceVariant,
                            grid: colors.outlineVariant.withValues(alpha: 0.5),
                            textStyle: theme.textTheme.labelSmall!,
                            accent: colors.primary,
                            windowStartStep: _stepOf(widget.smartWindowStart),
                            alarmStep: _stepOf(widget.alarmFiredAt),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 14,
          runSpacing: 6,
          children: [
            _LegendDot(color: SleepUi.awake, label: loc.sleepStageAwake),
            _LegendDot(color: SleepUi.sleeping, label: loc.sleepStageSleeping),
            _LegendDot(color: SleepUi.unknown, label: loc.sleepStageUnknown),
            _LegendDot(
              color: colors.onSurfaceVariant,
              label: loc.sleepChartPersonSound,
            ),
            _LegendDot(
              color: SleepUi.ambient,
              label: loc.sleepChartAmbientSound,
            ),
            if (timeline.hasSnoring)
              _LegendDot(color: SleepUi.snoring, label: loc.sleepSnoring),
            if (widget.smartWindowStart != null)
              _LegendDot(
                color: colors.primary.withValues(alpha: 0.35),
                label: loc.sleepChartSmartWindow,
              ),
            if (widget.alarmFiredAt != null)
              _LegendDot(color: colors.primary, label: loc.sleepChartAlarm),
          ],
        ),
      ],
    );
  }
}

Color _stageColor(SleepStageType stage) => SleepStageBar.stageColor(stage);

String _stageLabel(AppLocalizations loc, SleepStageType stage) =>
    switch (stage) {
      SleepStageType.awake => loc.sleepStageAwake,
      SleepStageType.sleeping => loc.sleepStageSleeping,
      SleepStageType.deep => loc.sleepStageDeepShort,
      SleepStageType.unknown => loc.sleepStageUnknown,
    };

class _NightPainter extends CustomPainter {
  // Row geometry: caption, band, caption, probability, caption, sound, axis.
  static const caption = 15.0;
  static const band = 20.0;
  static const probability = 50.0;
  static const sound = 40.0;
  static const gap = 8.0;

  final SleepNightTimeline timeline;
  final DateTime startedAt;
  final int utcOffsetMinutes;
  final int? selected;
  final (String, String, String) labels;
  final Color ink;
  final Color muted;
  final Color grid;
  final TextStyle textStyle;
  final Color accent;
  final double? windowStartStep;
  final double? alarmStep;

  _NightPainter({
    required this.timeline,
    required this.startedAt,
    required this.utcOffsetMinutes,
    required this.selected,
    required this.labels,
    required this.ink,
    required this.muted,
    required this.grid,
    required this.textStyle,
    required this.accent,
    this.windowStartStep,
    this.alarmStep,
  });

  void _text(
    Canvas canvas,
    String text,
    Offset at, {
    Color? color,
    bool center = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: textStyle.copyWith(color: color ?? muted),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, center ? at - Offset(painter.width / 2, 0) : at);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = timeline.length;
    if (n == 0) return;
    final w = size.width;
    double x(num step) => step / n * w;
    const bandTop = caption;
    const probTop = bandTop + band + gap + caption;
    const soundTop = probTop + probability + gap + caption;
    const soundBottom = soundTop + sound;

    // Hour grid through every row, labelled on the axis.
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    final localStart = startedAt.toUtc().add(
      Duration(minutes: utcOffsetMinutes),
    );
    final startSecond =
        localStart.minute * 60 +
        localStart.second +
        localStart.millisecond / 1000;
    final hours = n * timeline.stepSeconds / 3600;
    final every = hours > 9 ? 2 : 1;
    for (var h = 1; h <= hours.ceil() + 1; h++) {
      final second = h * 3600 - startSecond;
      final step = second / timeline.stepSeconds;
      if (step <= 0 || step >= n) continue;
      final hour = (localStart.hour + h) % 24;
      if (hour % every != 0) continue;
      final gx = x(step);
      canvas.drawLine(Offset(gx, bandTop), Offset(gx, soundBottom), gridPaint);
      _text(
        canvas,
        '${hour.toString().padLeft(2, '0')}:00',
        Offset(gx, soundBottom + 4),
        center: true,
      );
    }

    // Smart alarm window, behind every row.
    final windowStart = windowStartStep;
    if (windowStart != null && windowStart < n) {
      canvas.drawRect(
        Rect.fromLTRB(x(windowStart.clamp(0, n)), bandTop, w, soundBottom),
        Paint()..color = accent.withValues(alpha: 0.12),
      );
    }

    // Captions.
    _text(canvas, labels.$1, const Offset(0, 0), color: ink);
    _text(canvas, labels.$2, const Offset(0, probTop - caption), color: ink);
    _text(canvas, labels.$3, const Offset(0, soundTop - caption), color: ink);

    // State band: one rounded block per run, a hairline apart.
    var i = 0;
    while (i < n) {
      var j = i;
      while (j + 1 < n && timeline.stages[j + 1] == timeline.stages[i]) {
        j++;
      }
      final left = x(i);
      final right = x(j + 1) - (j + 1 < n ? 1.5 : 0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            left,
            bandTop,
            right < left + 1 ? left + 1 : right,
            bandTop + band,
          ),
          const Radius.circular(3),
        ),
        Paint()..color = _stageColor(timeline.stages[i]),
      );
      i = j + 1;
    }

    // Chance of sleep: 0 / 50 / 100 % guides and the line.
    for (final level in [0.0, 0.5, 1.0]) {
      final y = probTop + probability * (1 - level);
      final paint = Paint()
        ..color = grid
        ..strokeWidth = 1;
      if (level == 0.5) {
        for (var dx = 0.0; dx < w; dx += 6) {
          canvas.drawLine(Offset(dx, y), Offset(dx + 3, y), paint);
        }
      } else {
        canvas.drawLine(Offset(0, y), Offset(w, y), paint);
      }
    }
    final line = Path();
    final fill = Path();
    var open = false;
    var runStart = 0.0;
    void closeFill(double lastX) {
      fill
        ..lineTo(lastX, probTop + probability)
        ..lineTo(runStart, probTop + probability)
        ..close();
    }

    var lastX = 0.0;
    for (var k = 0; k < n; k++) {
      final p = timeline.sleepProbability[k];
      if (p == null) {
        if (open) closeFill(lastX);
        open = false;
        continue;
      }
      final px = x(k + 0.5);
      final py = probTop + probability * (1 - p);
      if (!open) {
        line.moveTo(px, py);
        fill.moveTo(px, probTop + probability);
        fill.lineTo(px, py);
        runStart = px;
        open = true;
      } else {
        line.lineTo(px, py);
        fill.lineTo(px, py);
      }
      lastX = px;
    }
    if (open) closeFill(lastX);
    canvas.drawPath(
      fill,
      Paint()..color = SleepUi.sleeping.withValues(alpha: 0.12),
    );
    canvas.drawPath(
      line,
      Paint()
        ..color = SleepUi.sleeping
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    // Sound per minute: the person stacked on the room, snoring on top.
    canvas.drawLine(
      const Offset(0, soundBottom),
      Offset(w, soundBottom),
      gridPaint,
    );
    final barWidth = (w / n - 0.4).clamp(0.6, 6.0);
    final perStep = timeline.stepSeconds.toDouble();
    for (var k = 0; k < n; k++) {
      var base = soundBottom;
      final left = x(k);
      for (final (seconds, color) in [
        (timeline.movementSeconds[k], muted),
        (timeline.ambientSeconds[k], SleepUi.ambient),
      ]) {
        if (seconds <= 0) continue;
        final h = seconds / perStep * sound;
        canvas.drawRect(
          Rect.fromLTWH(left, base - h, barWidth, h),
          Paint()..color = color,
        );
        base -= h;
      }
      if (timeline.snoring[k]) {
        canvas.drawRect(
          Rect.fromLTWH(left, soundTop, barWidth, 3),
          Paint()..color = SleepUi.snoring,
        );
      }
    }

    final alarm = alarmStep;
    if (alarm != null && alarm >= 0 && alarm <= n + 1) {
      final ax = x(alarm.clamp(0, n)) - 1;
      final paint = Paint()
        ..color = accent
        ..strokeWidth = 2;
      canvas.drawLine(Offset(ax, bandTop - 2), Offset(ax, soundBottom), paint);
      canvas.drawCircle(Offset(ax, bandTop - 2), 3.5, paint);
    }

    final s = selected;
    if (s != null) {
      final sx = x(s + 0.5);
      canvas.drawLine(
        Offset(sx, bandTop - 2),
        Offset(sx, soundBottom),
        Paint()
          ..color = ink.withValues(alpha: 0.7)
          ..strokeWidth = 1.2,
      );
      final p = timeline.sleepProbability[s];
      if (p != null) {
        final center = Offset(sx, probTop + probability * (1 - p));
        canvas.drawCircle(
          center,
          5,
          Paint()..color = ink.withValues(alpha: 0.9),
        );
        canvas.drawCircle(center, 3.5, Paint()..color = SleepUi.sleeping);
      }
    }
  }

  @override
  bool shouldRepaint(_NightPainter old) =>
      old.timeline != timeline ||
      old.selected != selected ||
      old.ink != ink ||
      old.muted != muted ||
      old.grid != grid ||
      old.accent != accent ||
      old.windowStartStep != windowStartStep ||
      old.alarmStep != alarmStep;
}

/// Fixed-height strip above the chart: the hint, or the inspected minute.
class _Readout extends StatelessWidget {
  final Widget child;

  const _Readout({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: child,
    );
  }
}

class _TooltipBody extends StatelessWidget {
  final SleepNightTimeline timeline;
  final int index;
  final String clock;

  const _TooltipBody({
    required this.timeline,
    required this.index,
    required this.clock,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final stage = timeline.stages[index];
    final p = timeline.sleepProbability[index];
    final style = theme.textTheme.bodySmall;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(clock, style: style?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(width: 10),
            _Dot(color: _stageColor(stage)),
            const SizedBox(width: 5),
            Text(
              _stageLabel(loc, stage),
              style: style?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (timeline.snoring[index]) ...[
              const SizedBox(width: 10),
              const _Dot(color: SleepUi.snoring),
              const SizedBox(width: 5),
              Text(loc.sleepSnoring, style: style),
            ],
          ],
        ),
        const SizedBox(height: 2),
        Text(
          [
            if (p != null) loc.sleepChartTooltipProbability((p * 100).round()),
            loc.sleepChartTooltipSound(
              timeline.movementSeconds[index],
              timeline.ambientSeconds[index],
            ),
          ].join(' · '),
          style: style?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
