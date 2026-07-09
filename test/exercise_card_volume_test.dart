import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/exercise_with_sets.dart';
import 'package:workout_notes/widgets/workout/exercise_card.dart';

void main() {
  Widget buildCard(
    ExerciseWithSets exercise, {
    ExerciseVolumeComparison? comparison,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ExerciseCard(
          exercise: exercise,
          onAddSet: () {},
          onToggleSet: (_) {},
          onEditSet: (setId, data, setNumber) {},
          onDeleteSet: (_) {},
          theme: ThemeData(),
          onChangeRestTime: (_) {},
          volumeComparison: comparison,
        ),
      ),
    );
  }

  testWidgets('shows volume comparison for weight and reps exercises', (
    tester,
  ) async {
    final exercise = ExerciseWithSets(
      entryId: 'entry-1',
      exerciseId: 'bench_press',
      name: 'Bench Press',
      exerciseType: 'weightReps',
      categoryId: 'chest',
      categoryName: 'Chest',
      categoryColor: Colors.blue,
      sets: const [],
    );

    await tester.pumpWidget(
      buildCard(
        exercise,
        comparison: const ExerciseVolumeComparison(
          exerciseId: 'bench_press',
          currentVolume: 1200,
          lastVolume: 1100,
        ),
      ),
    );

    expect(find.text('+100 kg (+9%)'), findsOneWidget);
  });

  testWidgets('hides volume comparison for non weight and reps exercises', (
    tester,
  ) async {
    final exercise = ExerciseWithSets(
      entryId: 'entry-1',
      exerciseId: 'running',
      name: 'Running',
      exerciseType: 'distanceTime',
      categoryId: 'cardio',
      categoryName: 'Cardio',
      categoryColor: Colors.red,
      sets: const [],
    );

    await tester.pumpWidget(
      buildCard(
        exercise,
        comparison: const ExerciseVolumeComparison(
          exerciseId: 'running',
          currentVolume: 1200,
          lastVolume: 1100,
        ),
      ),
    );

    expect(find.text('+100 kg (+9%)'), findsNothing);
  });
}
