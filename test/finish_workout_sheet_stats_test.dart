import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/workout/finish_workout_sheet.dart';

void main() {
  testWidgets('shows workout density in final summary when available', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(
          body: FinishWorkoutSheet(
            summary: WorkoutSummary(
              durationSeconds: 30 * 60,
              totalVolume: 3000,
              totalSets: 3,
              completedSets: 3,
              estimatedCalories: 367.5,
            ),
          ),
        ),
      ),
    );

    expect(find.text('Density'), findsOneWidget);
    expect(find.text('100 kg/min'), findsOneWidget);
    expect(find.text('Estimated calories'), findsOneWidget);
    expect(find.text('368 kcal'), findsOneWidget);
  });
}
