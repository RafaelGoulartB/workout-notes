import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/widgets/sleep/sleep_duration_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_history_row.dart';
import 'package:workout_notes/widgets/sleep/sleep_last_night_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_schedule_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_trend_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_week_card.dart';

Widget _localized(Widget child, {ThemeData? theme}) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  theme: theme,
  home: Scaffold(
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: child,
    ),
  ),
);

void main() {
  testWidgets('last night card compares sleep with the goal', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _localized(
        SleepLastNightCard(
          entry: _entry(
            date: DateTime(2026, 7, 26),
            sleepMinutes: 480,
            actualSleepMinutes: 420,
            bedtimeMinutes: 1380,
            wakeTimeMinutes: 420,
          ),
          goalMinutes: 480,
          onTap: () => tapped = true,
        ),
        theme: ThemeData.dark(),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Last night'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is SleepBigDuration && widget.minutes == 420,
      ),
      findsOneWidget,
    );
    expect(find.text('88%'), findsWidgets);
    expect(find.text('23:00 → 07:00'), findsOneWidget);
    expect(find.text('1h 0min short'), findsOneWidget);
    // No time in bed recorded: the tile keeps the missing value visible.
    expect(find.text('--'), findsOneWidget);

    await tester.tap(find.text('Last night'));
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('last night card fits a compact phone', (tester) async {
    tester.view.physicalSize = const Size(300, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _localized(
        SleepLastNightCard(
          entry: _entry(date: DateTime(2026, 7, 26), sleepMinutes: 510),
          goalMinutes: 480,
          onTap: () {},
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Goal reached'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('week card shows the week numbers and switches charts', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final days = _days();

    await tester.pumpWidget(
      _localized(
        SleepWeekCard(
          stats: _stats(),
          entries: [
            _entry(
              date: days[5],
              actualSleepMinutes: 390,
              bedtimeMinutes: 1430,
              wakeTimeMinutes: 430,
            ),
            _entry(date: days[6], bedtimeMinutes: 10, wakeTimeMinutes: 450),
          ],
          days: days,
          goalMinutes: 480,
        ),
      ),
    );
    await tester.pump();

    // Average of 6h 30min and 8h 0min.
    expect(find.text('7h 15min'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('6/7'), findsOneWidget);
    // The schedule is the default view.
    expect(find.byType(SleepScheduleChart), findsOneWidget);
    expect(find.byKey(const Key('sleep-schedule-chart')), findsOneWidget);

    await tester.tap(find.text('Duration'));
    await tester.pump();
    expect(find.byType(SleepDurationChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule chart renders sleep windows across midnight', (
    tester,
  ) async {
    final days = _days();
    await tester.pumpWidget(
      _localized(
        SleepScheduleChart(
          entries: [
            _entry(
              date: days[5],
              actualSleepMinutes: 390,
              bedtimeMinutes: 1430,
              wakeTimeMinutes: 430,
            ),
            _entry(date: days[6], bedtimeMinutes: 10, wakeTimeMinutes: 450),
          ],
          days: days,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byKey(const Key('sleep-schedule-chart')), findsOneWidget);
    expect(find.text('Avg. bedtime 00:00'), findsOneWidget);
    expect(find.text('Avg. wake-up 07:20'), findsOneWidget);

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final group = chart.data.barGroups[5];
    // Time runs downward: the rod spans from the wake-up (lower) to bedtime.
    expect(group.barRods.first.toY, closeTo(-(1430 / 60), 0.001));
    expect(group.barRods.first.fromY, closeTo(-(24 + 430 / 60), 0.001));
    final tooltip = chart.data.barTouchData.touchTooltipData.getTooltipItem(
      group,
      5,
      group.barRods.first,
      0,
    );
    final tooltipText = tooltip?.text;
    expect(tooltipText, isNotNull);
    expect(tooltipText, contains('Bedtime: 23:50'));
    expect(tooltipText, contains('Wake-up time: 07:10'));
    expect(tooltipText, contains('Recorded duration: 8h 0min'));
    expect(tooltipText, contains('Actual / estimated: 6h 30min'));

    final missingGroup = chart.data.barGroups[0];
    final missingTooltip = chart.data.barTouchData.touchTooltipData
        .getTooltipItem(missingGroup, 0, missingGroup.barRods.first, 0);
    expect(missingTooltip?.text, contains('No sleep record for this day'));
    expect(chart.data.barTouchData.allowTouchBarBackDraw, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duration chart pairs recorded and actual sleep per night', (
    tester,
  ) async {
    final days = _days();
    await tester.pumpWidget(
      _localized(
        SleepDurationChart(
          entries: [
            _entry(date: days[4], actualSleepMinutes: 390),
            _entry(date: days[6], estimatedSleepMinutes: 500),
          ],
          days: days,
          goalMinutes: 480,
        ),
      ),
    );
    await tester.pump();

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    expect(chart.data.barGroups[0].barRods, isEmpty);
    // Recorded duration next to the actual sleep.
    expect(chart.data.barGroups[4].barRods.map((rod) => rod.toY), [8, 6.5]);
    expect(chart.data.extraLinesData.horizontalLines.single.y, 8);
    expect(find.text('Recorded duration'), findsOneWidget);
    expect(find.text('Actual / estimated'), findsOneWidget);
    expect(find.text('Target 8h 0min'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('trend card needs two nights and then shows the average', (
    tester,
  ) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await tester.pumpWidget(
      _localized(
        SleepTrendCard(
          entries: [_entry(date: day, actualSleepMinutes: 420)],
          end: day,
          goalMinutes: 480,
        ),
      ),
    );
    expect(
      find.text('Add at least 2 records to see the trend.'),
      findsOneWidget,
    );

    await tester.pumpWidget(
      _localized(
        SleepTrendCard(
          entries: [
            _entry(date: day, actualSleepMinutes: 420),
            _entry(
              date: day.subtract(const Duration(days: 1)),
              actualSleepMinutes: 510,
            ),
          ],
          end: day,
          goalMinutes: 480,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(LineChart), findsOneWidget);
    expect(find.text('7h 45min'), findsOneWidget);
    expect(find.text('1 of 2 on goal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history row shows window, time in bed and efficiency', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localized(
        SleepHistoryRow(
          entry: SleepEntry(
            id: 'night',
            date: DateTime(2026, 7, 26),
            sleepMinutes: 450,
            estimatedSleepMinutes: 400,
            bedtimeMinutes: 1400,
            wakeTimeMinutes: 410,
            timeInBedMinutes: 450,
            createdAt: DateTime(2026, 7, 26),
          ),
          goalMinutes: 480,
          onTap: () {},
        ),
      ),
    );

    expect(find.text('6h 40min'), findsOneWidget);
    expect(find.text('23:20 → 06:50 · In bed 7h 30min'), findsOneWidget);
    expect(find.text('89%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

SleepDashboardStats _stats() => const SleepDashboardStats(
  latest: null,
  average7Days: 450,
  average30Days: 440,
  actualAverage7Days: 420,
  actualAverage30Days: 410,
  minimum30Days: 360,
  maximum30Days: 510,
  recordedDays7Days: 6,
  recordedDays30Days: 24,
  efficiency7Days: 88,
  efficiency30Days: 87,
  regularity7Days: 92,
  regularitySampleCount: 6,
);

List<DateTime> _days() {
  final end = DateTime(2026, 7, 26);
  return List.generate(7, (index) => end.subtract(Duration(days: 6 - index)));
}

SleepEntry _entry({
  required DateTime date,
  int sleepMinutes = 480,
  int? actualSleepMinutes,
  int? estimatedSleepMinutes,
  int? bedtimeMinutes,
  int? wakeTimeMinutes,
}) => SleepEntry(
  id: 'entry-${date.toIso8601String()}',
  date: date,
  sleepMinutes: sleepMinutes,
  actualSleepMinutes: actualSleepMinutes,
  estimatedSleepMinutes: estimatedSleepMinutes,
  bedtimeMinutes: bedtimeMinutes,
  wakeTimeMinutes: wakeTimeMinutes,
  createdAt: date,
);
