import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';

void main() {
  testWidgets('a flat series with rounding noise keeps a usable axis', (
    tester,
  ) async {
    // 18 kg × 8 every session: the e1RM is 22.799999999999997 and the trend
    // line lands on 22.8, a spread of 4e-15 that used to make fl_chart step
    // through the axis forever.
    const e1rm = 18 * (1 + 8 / 30);
    final points = [
      for (var i = 0; i < 11; i++)
        StrengthTrendPoint(
          date: DateTime(2026, 6, 19).add(Duration(days: i * 9)),
          value: e1rm,
          tooltip: '',
        ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StrengthTrendChart(
            points: points,
            unit: 'kg',
            emptyLabel: 'empty',
            showTrend: true,
          ),
        ),
      ),
    );

    final data = tester.widget<LineChart>(find.byType(LineChart)).data;
    expect(data.maxY - data.minY, greaterThanOrEqualTo(1));
    expect(data.gridData.horizontalInterval, greaterThanOrEqualTo(0.1));
  });
}
