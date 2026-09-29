import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/screens/workout/exercise_detail_tabs_screen.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/database/database_helper.dart';

/// Everything the strength analysis needs, loaded once: every completed
/// working set and finished workout, plus the muscle groups that were trained.
class StrengthInsightsData {
  final DateTime today;
  final List<StrengthSetSample> sets;
  final List<StrengthWorkoutInfo> workouts;

  /// Anaerobic categories that have at least one set, in library order.
  final List<Map<String, dynamic>> categories;

  const StrengthInsightsData({
    required this.today,
    required this.sets,
    required this.workouts,
    required this.categories,
  });

  bool get isEmpty => workouts.isEmpty;

  Map<String, dynamic>? category(String id) {
    for (final c in categories) {
      if (c['id'] == id) return c;
    }
    return null;
  }

  Color categoryColor(String id) =>
      Color((category(id)?['color'] as int?) ?? 0xFF757575);

  String categoryName(AppLocalizations loc, String id) {
    final row = category(id);
    return row == null ? id : strengthCategoryLabel(loc, row);
  }

  static Future<StrengthInsightsData> load({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final records = DatabaseHelper.instance.strengthRecordsRepo;
    final results = await Future.wait([
      records.loadSets(includeUnweighted: true),
      records.loadWorkouts(),
      DatabaseHelper.instance.exerciseRepo.getCategories(),
    ]);
    final sets = results[0] as List<StrengthSetSample>;
    final trained = {for (final s in sets) s.categoryId};
    final categories = [
      for (final c in results[2] as List<Map<String, dynamic>>)
        if ((c['energy_system'] as String?) != 'aerobic' &&
            trained.contains(c['id']))
          c,
    ];
    return StrengthInsightsData(
      today: today,
      sets: sets,
      workouts: results[1] as List<StrengthWorkoutInfo>,
      categories: categories,
    );
  }
}

/// Opens the exercise detail (history and charts) of a strength exercise.
Future<void> openStrengthExercise(
  BuildContext context, {
  required String exerciseId,
  required Map<String, dynamic> exerciseRow,
}) {
  final loc = AppLocalizations.of(context)!;
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ExerciseDetailTabsScreen(
        exerciseId: exerciseId,
        exerciseName: ExerciseLocaleHelper.exerciseName(loc, exerciseRow),
      ),
    ),
  );
}

/// Whole-week bucket labels: `dd/MM` for weeks, the month for month buckets.
extension StrengthBucketLabels on StrengthVolumeBucket {
  String label(String locale) => monthly
      ? DateFormat.MMM(locale).format(start)
      : DateFormat('dd/MM').format(start);
}

/// Localized name of an `exercise_categories` row (resolved through its
/// `locale_key`, else its id, else the stored name).
String strengthCategoryLabel(AppLocalizations loc, Map<String, dynamic> row) =>
    ExerciseLocaleHelper.categoryName(loc, {
      'locale_key': row['locale_key'],
      'category_id': row['id'],
      'category_name': row['name'],
    });
