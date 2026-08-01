import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/widgets/sleep/sleep_duration_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_latest_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_goal_metrics_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_monitor_hero_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_schedule_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_weekly_summary_card.dart';

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
  testWidgets('monitor hero prioritizes start and active states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localized(
        SleepMonitorHeroCard(
          isActive: false,
          elapsed: Duration.zero,
          onPressed: () {},
        ),
      ),
    );

    expect(find.text('Monitor sleep'), findsOneWidget);
    expect(find.text('Start monitoring'), findsNothing);
    expect(
      tester.getSize(find.byType(SleepMonitorHeroCard)).height,
      lessThan(90),
    );

    await tester.pumpWidget(
      _localized(
        SleepMonitorHeroCard(
          isActive: true,
          elapsed: const Duration(hours: 1, minutes: 2, seconds: 3),
          onPressed: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Monitoring in progress'), findsOneWidget);
    expect(find.text('Active for 01:02:03'), findsOneWidget);
  });

  testWidgets('weekly summary remains readable on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      _localized(
        SleepWeeklySummaryCard(
          stats: _stats(),
          start: DateTime(2026, 7, 20),
          end: DateTime(2026, 7, 26),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Weekly summary'), findsOneWidget);
    expect(find.text('7h 30min'), findsOneWidget);
    expect(find.text('92%'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('schedule chart renders sleep windows across midnight', (
    tester,
  ) async {
    final days = _days();
    var previousTaps = 0;
    var nextTaps = 0;
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
          onPreviousWeek: () => previousTaps++,
          onNextWeek: () => nextTaps++,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.byKey(const Key('sleep-schedule-chart')), findsOneWidget);

    await tester.tap(find.byKey(const Key('sleep-previous-week')));
    await tester.tap(find.byKey(const Key('sleep-next-week')));
    expect(previousTaps, 1);
    expect(nextTaps, 1);

    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final group = chart.data.barGroups[5];
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

  testWidgets('duration chart supports gaps and estimated sleep', (
    tester,
  ) async {
    final days = _days();
    await tester.pumpWidget(
      _localized(
        SleepDurationChart(
          entries: [
            _entry(date: days[4], actualSleepMinutes: 390),
            _entry(date: days[6], estimatedSleepMinutes: 410),
          ],
          days: days,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BarChart), findsOneWidget);
    expect(find.text('Recorded duration'), findsOneWidget);
    expect(find.text('Actual / estimated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('latest night card opens details and works in dark mode', (
    tester,
  ) async {
    var tapped = false;
    await tester.pumpWidget(
      _localized(
        SleepLatestCard(
          entry: _entry(
            date: DateTime(2026, 7, 26),
            actualSleepMinutes: 420,
            bedtimeMinutes: 1380,
            wakeTimeMinutes: 420,
          ),
          onTap: () => tapped = true,
        ),
        theme: ThemeData.dark(),
      ),
    );

    expect(find.text('Latest record'), findsOneWidget);
    expect(find.text('88%'), findsOneWidget);
    expect(find.text('23:00'), findsOneWidget);
    expect(find.text('07:00'), findsOneWidget);

    await tester.tap(find.text('Latest record'));
    expect(tapped, isTrue);
  });
  testWidgets(
    'sleep goal card compares the latest night and preserves missing values',
    (tester) async {
      await tester.pumpWidget(
        _localized(
          SleepGoalMetricsCard(
            entry: _entry(
              date: DateTime(2026, 7, 26),
              sleepMinutes: 480,
              actualSleepMinutes: 420,
              bedtimeMinutes: 1380,
              wakeTimeMinutes: 420,
            ),
            stats: _stats(),
            goalMinutes: 510,
          ),
          theme: ThemeData.dark(),
        ),
      );
      await tester.pump();

      expect(find.text('Sleep goal: Goal missed'), findsOneWidget);
      expect(find.text('7h 0min'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

SleepDashboardStats _stats() => SleepDashboardStats(
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
