import 'package:flutter/widgets.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_provider.dart';
import 'package:workout_notes/repositories/analytics_repository.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/routine_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/repositories/workout_repository.dart';

/// Application composition root.
///
/// This is the single place that creates long-lived infrastructure and
/// repositories. Dependencies can be replaced by constructing an
/// [AppDependencies] directly in tests or embedding an [AppDependenciesScope].
class AppDependencies {
  AppDependencies({DatabaseProvider? database})
    : database = database ?? DatabaseHelper.instance {
    DatabaseProviderRegistry.configure(this.database);
    settingsRepository = SettingsRepository(this.database);
    exerciseRepository = ExerciseRepository(this.database);
    workoutRepository = WorkoutRepository(this.database);
    routineRepository = RoutineRepository(this.database);
    bodyMeasurementRepository = BodyMeasurementRepository(this.database);
    analyticsRepository = AnalyticsRepository(this.database);
    goalRepository = GoalRepository(this.database);
    exportImportRepository = ExportImportRepository(
      databaseProvider: () => this.database.database,
    );
  }

  static final AppDependencies instance = AppDependencies();

  final DatabaseProvider database;
  late final SettingsRepository settingsRepository;
  late final ExerciseRepository exerciseRepository;
  late final WorkoutRepository workoutRepository;
  late final RoutineRepository routineRepository;
  late final BodyMeasurementRepository bodyMeasurementRepository;
  late final AnalyticsRepository analyticsRepository;
  late final GoalRepository goalRepository;
  late final ExportImportRepository exportImportRepository;
}

/// Makes the composition root available to UI code without coupling widgets to
/// static service locators.
class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<AppDependenciesScope>()
          ?.dependencies ??
      AppDependencies.instance;

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) =>
      dependencies != oldWidget.dependencies;
}
