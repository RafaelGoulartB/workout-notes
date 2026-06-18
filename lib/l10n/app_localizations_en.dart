// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Workout Notes';

  @override
  String get tabWorkout => 'Workout';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDiscard => 'Discard';

  @override
  String get commonKeepEditing => 'Keep editing';

  @override
  String commonError(Object error) {
    return 'Error: $error';
  }

  @override
  String get commonSearch => 'Search';

  @override
  String get commonAll => 'All';

  @override
  String get commonExercises => 'Exercises';

  @override
  String get commonVolume => 'Volume';

  @override
  String get commonSets => 'Sets';

  @override
  String get commonReps => 'Reps';

  @override
  String get commonCompleted => 'Completed';

  @override
  String get commonInProgress => 'In progress';

  @override
  String get commonConfirmDelete => 'Are you sure?';

  @override
  String get commonActionCannotBeUndone => 'This action cannot be undone.';

  @override
  String get accentColorRed => 'Deep Red';

  @override
  String get accentColorDarkOrange => 'Dark Orange';

  @override
  String get accentColorOrange => 'Orange';

  @override
  String get accentColorAmber => 'Amber';

  @override
  String get accentColorDeepPurple => 'Deep Purple';

  @override
  String get accentColorDarkBlue => 'Dark Blue';

  @override
  String get accentColorGraphite => 'Graphite';

  @override
  String get accentColorForestGreen => 'Forest Green';

  @override
  String get workoutHomeTitle => 'Workout';

  @override
  String get workoutHomeHistoryTooltip => 'History';

  @override
  String get workoutHomeSettingsTooltip => 'Settings';

  @override
  String get workoutHomeMonthWorkouts => 'Workouts this Month';

  @override
  String get workoutHomeVolume => 'Volume';

  @override
  String get workoutHomeStreak => 'Streak';

  @override
  String get workoutHomeDay => 'day';

  @override
  String get workoutHomeDays => 'days';

  @override
  String get workoutHomeNewWorkout => 'New Workout';

  @override
  String get workoutHomeStartNow => 'Start now';

  @override
  String get workoutHomeQuickAdd => 'Quick Add';

  @override
  String get workoutHomeQuickAddSubtitle => 'Quick add';

  @override
  String get workoutHomeNavigation => 'NAVIGATION';

  @override
  String get workoutHomeExercises => 'Exercises';

  @override
  String get workoutHomeRoutines => 'Routines';

  @override
  String get workoutHomeProgress => 'Progress';

  @override
  String get workoutHomeBodyMeasurements => 'Measurements';

  @override
  String get workoutHomeInProgress => 'IN PROGRESS';

  @override
  String get workoutHomeNoActiveWorkout => 'No workout in progress';

  @override
  String get workoutHomeUpcoming => 'UPCOMING WORKOUTS';

  @override
  String get workoutHomeCompleted => 'COMPLETED WORKOUTS';

  @override
  String get workoutHomeOngoing => 'In progress';

  @override
  String get workoutHomeContinueWorkout => 'Continue Workout';

  @override
  String get workoutHomeDeleteWorkout => 'Delete Workout';

  @override
  String get workoutHomeSectionQuickActions => 'QUICK ACTIONS';

  @override
  String get workoutHomeSectionTools => 'TOOLS';

  @override
  String get workoutHomeSectionHistory => 'HISTORY';

  @override
  String workoutHomeActiveBannerSubtitle(Object duration) {
    return '$duration elapsed · tap to continue';
  }

  @override
  String get workoutHomeActiveBannerAction => 'Continue';

  @override
  String get workoutHomeLastWorkout => 'Last workout';

  @override
  String workoutHomeLastWorkoutAgo(Object when) {
    return '$when ago';
  }

  @override
  String get workoutHomeLastWorkoutToday => 'Today';

  @override
  String get workoutHomeLastWorkoutYesterday => 'Yesterday';

  @override
  String get workoutHomeEmptyTitle => 'No workouts yet';

  @override
  String get workoutHomeEmptySubtitle =>
      'Log your first workout to start tracking your progress';

  @override
  String get workoutHomeEmptyCta => 'Start first workout';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsSectionAppearance => 'APPEARANCE';

  @override
  String get settingsSectionWorkout => 'WORKOUT';

  @override
  String get settingsSectionNotifications => 'NOTIFICATIONS';

  @override
  String get settingsSectionData => 'DATA';

  @override
  String get settingsAboutDescription =>
      'A complete workout tracker with routines, progress charts, body measurements and CSV export.';

  @override
  String get settingsAboutOk => 'OK';

  @override
  String get settingsThemeColor => 'Theme Color';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsSystemSubtitle => 'Follow device setting';

  @override
  String get settingsLight => 'Light';

  @override
  String get settingsLightSubtitle => 'Force light mode';

  @override
  String get settingsDark => 'Dark';

  @override
  String get settingsDarkSubtitle => 'Force dark mode';

  @override
  String get settingsUnits => 'Units';

  @override
  String get settingsUnitSystem => 'Unit System';

  @override
  String get settingsUnitKgCm => 'kg / cm';

  @override
  String get settingsUnitLbsIn => 'lbs / in';

  @override
  String get settingsTimer => 'Timer';

  @override
  String get settingsDefaultRest => 'Default Rest';

  @override
  String get settingsSeconds => 'seconds';

  @override
  String get settingsAutoStartRest => 'Auto-start Rest Timer';

  @override
  String get settingsAutoStartRestSubtitle =>
      'Start automatically after each set';

  @override
  String get settingsAutoStartWorkoutTimer => 'Auto-start Workout Timer';

  @override
  String get settingsAutoStartWorkoutTimerSubtitle =>
      'Start timer after 1st set, stop after last set';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsRestTimerNotif => 'Rest Timer';

  @override
  String get settingsRestTimerNotifSubtitle => 'Notification between sets';

  @override
  String get settingsWorkoutTimerNotif => 'Workout Timer';

  @override
  String get settingsWorkoutTimerNotifSubtitle => 'Active workout notification';

  @override
  String get settingsAlertOptions => 'Alert options';

  @override
  String get settingsSound => 'Sound';

  @override
  String get settingsRestSoundSubtitle =>
      'Play sound when rest starts and ends';

  @override
  String get settingsWorkoutSoundSubtitle => 'Play sound when workout starts';

  @override
  String get settingsVibration => 'Vibration';

  @override
  String get settingsRestVibrationSubtitle =>
      'Vibrate when rest starts and ends';

  @override
  String get settingsWorkoutVibrationSubtitle => 'Vibrate when workout starts';

  @override
  String get settingsDisplay => 'Display';

  @override
  String get settingsKeepScreenOn => 'Keep Screen On';

  @override
  String get settingsKeepScreenOnSubtitle => 'During workout';

  @override
  String get settingsData => 'Data';

  @override
  String get settingsExportBackup => 'Export Backup';

  @override
  String get settingsExportBackupSubtitle =>
      'Full JSON backup to save or transfer';

  @override
  String get settingsGenerateTestData => 'Generate Test Data';

  @override
  String get settingsGenerateTestDataSubtitle =>
      'Adds fictional workouts to test the app';

  @override
  String get settingsGenerateTitle => 'Generate Test Data?';

  @override
  String get settingsGenerateContent =>
      'This will add fictional workouts from recent months to test charts and features.\n\nUse \"Delete All History\" to remove them later.';

  @override
  String get settingsGenerate => 'Generate';

  @override
  String settingsGenerateSuccess(Object count) {
    return '✅ $count workouts generated!';
  }

  @override
  String get settingsAbout => 'About';

  @override
  String get settingsAboutSubtitle => 'Workout Notes v1.0';

  @override
  String get settingsDeleteAllHistory => 'Delete All Workout History';

  @override
  String get settingsDeleteHistoryTitle => 'Delete All History?';

  @override
  String get settingsDeleteHistoryContent =>
      'All workouts, sets and registered exercises will be deleted. This action cannot be undone.';

  @override
  String get settingsDeleteEverything => 'Delete Everything';

  @override
  String get settingsDeleteHistorySuccess => 'History deleted';

  @override
  String get settingsExportSuccess => '✅ Backup exported!';

  @override
  String settingsExportError(Object error) {
    return 'Error: $error';
  }

  @override
  String get settingsImportBackup => 'Import Backup';

  @override
  String get settingsImportBackupSubtitle =>
      'Restore all data from a JSON backup';

  @override
  String get settingsImportWarning =>
      'This will replace ALL your current data (workouts, exercises, routines, measurements, settings) with the backup data.\n\nThis action cannot be undone.';

  @override
  String get settingsImport => 'Import';

  @override
  String settingsImportSuccess(Object count) {
    return '✅ $count records imported! Restart the app to apply changes.';
  }

  @override
  String settingsImportError(Object error) {
    return 'Import error: $error';
  }

  @override
  String get settingsNoBackupFile => 'No backup file selected';

  @override
  String get settingsImportPasteTitle => 'Paste Backup';

  @override
  String get settingsImportPasteHint =>
      'Copy the .json file content and paste here';

  @override
  String get settingsImportPasteOption => 'Paste backup content';

  @override
  String get settingsImportPasteSubtitle =>
      'Copy the JSON from another device and paste here';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsEnglish => 'English';

  @override
  String get settingsPortuguese => 'Português (Brasil)';

  @override
  String get settingsLanguageSubtitle => 'App interface language';

  @override
  String get calendarTitle => 'History';

  @override
  String get calendarSun => 'Sun';

  @override
  String get calendarMon => 'Mon';

  @override
  String get calendarTue => 'Tue';

  @override
  String get calendarWed => 'Wed';

  @override
  String get calendarThu => 'Thu';

  @override
  String get calendarFri => 'Fri';

  @override
  String get calendarSat => 'Sat';

  @override
  String calendarNoWorkouts(Object date) {
    return 'No workouts on $date';
  }

  @override
  String get calendarCreateWorkout => 'Create Workout';

  @override
  String get calendarNoTime => 'No time';

  @override
  String get calendarInProgress => 'In progress';

  @override
  String get calendarWorkoutCreated => '✅ Workout created for this day!';

  @override
  String get calendarSelectNewDate => 'Select the new date';

  @override
  String get exportTitle => 'Export Data';

  @override
  String get exportJsonBackup => 'Full Backup (JSON)';

  @override
  String get exportJsonBackupSubtitle =>
      'Exports all data: workouts, exercises, routines, measurements and settings';

  @override
  String get exportCsv => 'Export CSV';

  @override
  String get exportCsvSubtitle =>
      'Exports workout history (date, exercise, weight, reps) - filterable by exercise and date';

  @override
  String get exportShareSummary => 'Share Summary';

  @override
  String get exportShareSummarySubtitle =>
      'Generates a text summary of a specific workout to share';

  @override
  String get exportTips => 'Tips';

  @override
  String get exportTipsContent =>
      '• JSON backup contains all app data\n• CSV is ideal for analysis in Excel/Google Sheets\n• Files are saved temporarily and shared via native share sheet';

  @override
  String get exportCsvDialogTitle => 'Export CSV';

  @override
  String get exportCsvExerciseLabel =>
      'Exercise (optional - empty exports all)';

  @override
  String get exportCsvExerciseHint => 'Leave empty for all';

  @override
  String get exportCsvStartDate => 'Start date';

  @override
  String get exportCsvEndDate => 'End date';

  @override
  String get exportCsvButton => 'Export CSV';

  @override
  String get exportShareWorkoutTitle => 'Share Workout';

  @override
  String get exportNoWorkouts => 'No workouts to share';

  @override
  String get exportSuccess => 'Backup exported successfully!';

  @override
  String get exportCsvSuccess => 'CSV exported successfully!';

  @override
  String exportError(Object error) {
    return 'Error: $error';
  }

  @override
  String get progressTitle => 'Progress';

  @override
  String progressMonthlyReport(Object month) {
    return 'MONTHLY REPORT OF $month';
  }

  @override
  String get progressWorkouts => 'Workouts';

  @override
  String get progressSets => 'Sets';

  @override
  String get progressDays => 'Days';

  @override
  String progressAverageFeeling(Object rating) {
    return 'Average feeling: $rating ★';
  }

  @override
  String progressVsLastMonth(Object delta) {
    return '$delta vs last month';
  }

  @override
  String get progressStreak => 'Streak';

  @override
  String get progressFrequency => 'Frequency & Consistency';

  @override
  String get progressVolumeGroups => 'Volume & Muscle Groups';

  @override
  String get progressExerciseHistory => 'Exercise History';

  @override
  String get progressDurationEfficiency => 'Duration & Efficiency';

  @override
  String get progressRecovery => 'Recovery & Well-being';

  @override
  String get progressBodyMeasurements => 'Body Measurements';

  @override
  String get progressBodyMeasurementsSubtitle =>
      'View detailed trends, photos, and body composition charts';

  @override
  String get progressCardio => 'Cardio';

  @override
  String get progressCardioSubtitle =>
      'Distance, pace, and cardiovascular tracking';

  @override
  String get progressCardioWeekly => 'Weekly Distance';

  @override
  String get progressCardioByModality => 'Distance by Modality';

  @override
  String get progressCardioPace => 'Pace Trend';

  @override
  String get progressCardioPRs => 'Cardio Records';

  @override
  String progressCardioTotal(Object distance) {
    return 'Total: $distance this month';
  }

  @override
  String progressCardioAvgPace(Object pace) {
    return 'Avg pace: $pace';
  }

  @override
  String get progressCardioNoData => 'No cardio workouts yet';

  @override
  String get progressCardioNoDataCta => 'Start a cardio workout';

  @override
  String get progressFilterAll => 'All';

  @override
  String get progressFilterStrength => 'Strength';

  @override
  String get progressFilterCardio => 'Cardio';

  @override
  String get progressSelectExercise => 'Select exercise';

  @override
  String get cardioLongestDistance => 'Longest Distance';

  @override
  String get cardioLongestDuration => 'Longest Duration';

  @override
  String get cardioBestPace => 'Best Pace';

  @override
  String get settingsDistanceUnit => 'Distance Unit';

  @override
  String get settingsDistanceUnitKm => 'km';

  @override
  String get settingsDistanceUnitMi => 'mi (miles)';

  @override
  String get workoutHomeCardioDistance => 'Cardio Dist.';

  @override
  String get workoutHomeCardioTime => 'Cardio Time';

  @override
  String get commonDistance => 'Distance';

  @override
  String get commonPace => 'Pace';

  @override
  String get commonTotal => 'Total';

  @override
  String get progressBodyComposition => 'Body Composition Evolution';

  @override
  String get progressYearHeatmap => 'Annual heatmap';

  @override
  String get progressWeeklyFrequency => 'Weekly frequency (last 12 weeks)';

  @override
  String get progressDayOfWeek => 'Day of week';

  @override
  String get progressTimeOfDay => 'Time of day';

  @override
  String get progressMorning => 'Morning';

  @override
  String get progressAfternoon => 'Afternoon';

  @override
  String get progressEvening => 'Evening';

  @override
  String get progressDawn => 'Dawn';

  @override
  String get progressNoData => 'No data';

  @override
  String get progressVolumeByGroup => 'Volume by Group';

  @override
  String get progressEnergySystem => 'Energy System';

  @override
  String get progressAerobic => 'Aerobic';

  @override
  String get progressAnaerobic => 'Anaerobic';

  @override
  String get progressTopExercises => 'Top Exercises by Volume';

  @override
  String get progressNoExercises => 'No exercises registered';

  @override
  String get progressTapForHistory => 'Tap an exercise to view full history';

  @override
  String get progressDuration => 'Workout Duration';

  @override
  String progressAverage(Object avg) {
    return 'Average: ${avg}min';
  }

  @override
  String get progressDensity => 'Density (Volume per Minute)';

  @override
  String progressDensityAverage(Object avg) {
    return 'Average: $avg kg/min';
  }

  @override
  String get progressWeekAbbreviation => 'W';

  @override
  String get progressBodyWeight => 'Body Weight';

  @override
  String get progressNoChartData => 'No data available for this chart';

  @override
  String get progressHistoryTitle => 'Workout History';

  @override
  String get progressHistoryDate => 'Date';

  @override
  String get progressHistorySetsReps => 'Sets × Reps';

  @override
  String get progressLoadError => 'Error loading data';

  @override
  String progressHeatmapNoData(Object year) {
    return 'No data for $year';
  }

  @override
  String get progressChartTitleProgress => 'Progress';

  @override
  String get progressChartTitleVolumePerWorkout => 'Volume per Workout';

  @override
  String get progressChartTitleRepsPerWorkout => 'Reps per Workout';

  @override
  String get progressRecoveryFeeling => 'Feeling Over Time';

  @override
  String get progressRecoveryFeelingVsVolume => 'Feeling vs Average Volume';

  @override
  String get progressBodyWeightVsVolume => 'Body Weight vs Workout Volume';

  @override
  String get progressVolumeByMonth => 'Volume by Month';

  @override
  String get bodyTrackerTitle => 'Body Measurements';

  @override
  String get bodyTrackerWeight => 'Body Weight';

  @override
  String get bodyTrackerBodyFat => '% Body Fat';

  @override
  String get bodyTrackerWaist => 'Waist';

  @override
  String get bodyTrackerChest => 'Chest';

  @override
  String get bodyTrackerArm => 'Arm';

  @override
  String get bodyTrackerThigh => 'Thigh';

  @override
  String get bodyTrackerHip => 'Hip';

  @override
  String get bodyTrackerAdd => 'Add Measurement';

  @override
  String bodyTrackerAddTitle(Object type) {
    return 'Add $type';
  }

  @override
  String get bodyTrackerValue => 'Value';

  @override
  String get bodyTrackerDate => 'Date';

  @override
  String get bodyTrackerComment => 'Comment';

  @override
  String get bodyTrackerSave => 'Save';

  @override
  String get bodyTrackerSaved => '✅ Measurement saved!';

  @override
  String get bodyTrackerDeleted => 'Measurement deleted';

  @override
  String get bodyTrackerDeleteConfirm => 'Delete this measurement?';

  @override
  String get bodyTrackerQuickMeasure => 'Quick Measure';

  @override
  String get bodyTrackerQuickMeasureSubtitle =>
      'Fill in the measurements you want to record. Leave blank to skip.';

  @override
  String get bodyTrackerSaveAll => 'Save Measurements';

  @override
  String bodyTrackerAddSingle(Object type) {
    return 'Add $type';
  }

  @override
  String get bodyTrackerEmptyTitle => 'No measurements yet';

  @override
  String get bodyTrackerEmptySubtitle =>
      'Start tracking your body measurements to see your progress over time.';

  @override
  String get bodyTrackerBodyMap => 'BODY MAP';

  @override
  String get bodyTrackerLastValue => 'Last';

  @override
  String get bodyTrackerCurrent => 'Current';

  @override
  String get bodyTrackerAverage => 'Average';

  @override
  String get bodyTrackerMin => 'Min';

  @override
  String get bodyTrackerMax => 'Max';

  @override
  String get bodyTrackerTrendLine => 'Trend';

  @override
  String get bodyTrackerHistory => 'History';

  @override
  String get bodyTrackerEntries => 'entries';

  @override
  String get bodyTrackerNeedTwoMeasurements =>
      'Add at least 2 measurements to see the chart';

  @override
  String get bodyTrackerPhoto => 'Photo (optional)';

  @override
  String get bodyTrackerCamera => 'Camera';

  @override
  String get bodyTrackerGallery => 'Gallery';

  @override
  String get bodyTrackerInvalidValue => 'Invalid value';

  @override
  String get bodyTrackerFasting => 'Fasting';

  @override
  String get bodyTrackerFasted => 'Fasted';

  @override
  String get bodyTrackerQuickCommentHint => 'Quick note (optional)';

  @override
  String bodyTrackerSavedBatch(Object count) {
    return '✅ $count measurements saved!';
  }

  @override
  String get bodyTrackerLeftAbbr => 'L';

  @override
  String get bodyTrackerRightAbbr => 'R';

  @override
  String get bodyTrackerLastLabel => 'Last: ';

  @override
  String get bodyTrackerMorning => 'Morning';

  @override
  String get bodyTrackerAfternoon => 'Afternoon';

  @override
  String get bodyTrackerEvening => 'Evening';

  @override
  String get bodyTrackerNight => 'Night';

  @override
  String get bodyTrackerCalf => 'Calf';

  @override
  String get bodyTrackerForearm => 'Forearm';

  @override
  String get bodyTrackerNeck => 'Neck';

  @override
  String get bodyTrackerLeft => 'Left';

  @override
  String get bodyTrackerRight => 'Right';

  @override
  String get bodyTrackerSelectMeasurement => 'Select Measurement';

  @override
  String get bodyTrackerCustomize => 'Customize';

  @override
  String get bodyTrackerCustomizeTitle => 'Customize Measurements';

  @override
  String get bodyTrackerCustomizeSubtitle =>
      'Select the measurements you want to track';

  @override
  String get bodyTrackerLeanMass => 'Lean Mass';

  @override
  String get bodyTrackerFatMass => 'Fat Mass';

  @override
  String get bodyTrackerHealthy => 'Healthy';

  @override
  String get bodyTrackerModerate => 'Moderate Risk';

  @override
  String get bodyTrackerHigh => 'High Risk';

  @override
  String bodyTrackerAsymmetry(Object diff, Object largerSide, Object unit) {
    return 'Difference: $diff $unit ($largerSide larger)';
  }

  @override
  String get bodyTrackerTrendComparison => 'Left vs Right';

  @override
  String bodyTrackerLoadMore(Object count) {
    return 'Load $count more entries';
  }

  @override
  String bodyTrackerLoadMoreCount(Object count) {
    return 'Load $count more';
  }

  @override
  String get bodyTrackerWHR => 'WHR';

  @override
  String get bodyTrackerEstimatedComposition => 'Estimated Body Composition';

  @override
  String get bodyTrackerTimeOfDay => 'Time of day';

  @override
  String get bodyTrackerNotInformed => 'Not informed';

  @override
  String get commonOptional => 'optional';

  @override
  String get routinesTitle => 'Routines';

  @override
  String get routinesNew => 'New Routine';

  @override
  String get routinesName => 'Routine Name';

  @override
  String get routinesNameHint => 'Ex: Push Pull Legs';

  @override
  String get routinesCreate => 'Create';

  @override
  String get routinesEdit => 'Edit Routine';

  @override
  String get routinesDelete => 'Delete Routine';

  @override
  String routinesDeleteConfirm(Object name) {
    return 'Delete \"$name\"?';
  }

  @override
  String get routinesDeleteContent => 'All routine data will be lost.';

  @override
  String get routinesEmptyTitle => 'No routines yet';

  @override
  String get routinesEmptySubtitle => 'Create a routine to train faster';

  @override
  String get routinesRename => 'Rename';

  @override
  String get routinesNewDay => 'New Day';

  @override
  String get routinesDayName => 'Day Name';

  @override
  String get routinesDayNameHint => 'Ex: Push Day, Monday';

  @override
  String get routinesAddDay => 'Add Day';

  @override
  String get routinesDeleteDay => 'Delete Day';

  @override
  String get routinesEditDay => 'Edit Day';

  @override
  String get routinesDayEmpty => 'No days yet';

  @override
  String get routinesDayEmptySubtitle => 'Add days to your routine';

  @override
  String get routinesNoExercises => 'No exercises added';

  @override
  String get routinesAddExercise => 'Add Exercise';

  @override
  String get routinesRestTimeTitle => 'Rest Time';

  @override
  String get restTimerTitle => 'Rest Timer';

  @override
  String get restTimerStop => 'Stop';

  @override
  String get restTimerComplete => 'COMPLETED';

  @override
  String get restTimerPaused => 'PAUSED';

  @override
  String get restTimerResting => 'RESTING';

  @override
  String get restTimerReady => 'READY';

  @override
  String get restTimerResume => 'Resume';

  @override
  String get restTimerPause => 'Pause';

  @override
  String get restTimerStartRest => 'Start rest';

  @override
  String get exerciseLibraryTitle => 'Exercises';

  @override
  String get exerciseLibraryFavorites => 'Favorites';

  @override
  String get exerciseLibrarySearch => 'Search exercise...';

  @override
  String get exerciseLibraryAll => 'All';

  @override
  String get exerciseLibraryNoResults => 'No exercises found';

  @override
  String get exerciseLibraryNoResultsHint =>
      'Try a different search or add a new one';

  @override
  String get exerciseLibraryNew => 'New Exercise';

  @override
  String get exerciseLibraryAerobic => 'Aerobic';

  @override
  String get exerciseLibraryAnaerobic => 'Anaerobic';

  @override
  String get exerciseFormTitleNew => 'New Exercise';

  @override
  String get exerciseFormTitleEdit => 'Edit Exercise';

  @override
  String get exerciseFormName => 'Exercise Name';

  @override
  String get exerciseFormNameHint => 'Ex: Incline Bench Press';

  @override
  String get exerciseFormCategory => 'Muscle Group';

  @override
  String get exerciseFormType => 'Type';

  @override
  String get exerciseFormEquipment => 'Equipment (optional)';

  @override
  String get exerciseFormEquipmentHint => 'Barbell, Dumbbell, Machine...';

  @override
  String get exerciseFormWeightIncrement => 'Weight Increment (kg)';

  @override
  String get exerciseFormWeightIncrementHint => 'Ex: 2.5';

  @override
  String get exerciseFormDefaultRest => 'Default Rest (seconds)';

  @override
  String get exerciseFormDefaultRestHint => 'Ex: 90';

  @override
  String get exerciseFormNotes => 'Instructions / Tips (optional)';

  @override
  String get exerciseFormNotesHint => 'Execution tips, proper form...';

  @override
  String get exerciseFormNameRequired => 'Name is required';

  @override
  String get exerciseFormSave => 'Save';

  @override
  String exerciseFormError(Object error) {
    return 'Error: $error';
  }

  @override
  String get exerciseFormTypeWeightReps => 'Weight × Reps';

  @override
  String get exerciseFormTypeDistanceTime => 'Distance × Time';

  @override
  String get exerciseFormTypeWeightDistance => 'Weight × Distance';

  @override
  String get exerciseFormTypeWeightTime => 'Weight × Time';

  @override
  String get exerciseFormTypeRepsDistance => 'Reps × Distance';

  @override
  String get exerciseFormTypeRepsTime => 'Reps × Time';

  @override
  String get exerciseFormTypeWeightOnly => 'Weight Only';

  @override
  String get exerciseFormTypeRepsOnly => 'Reps Only';

  @override
  String get exerciseFormTypeDistanceOnly => 'Distance Only';

  @override
  String get exerciseFormTypeTimeOnly => 'Time Only';

  @override
  String get quickAddTitle => 'Quick Add';

  @override
  String get quickAddHint => 'Ex: Bench Press 80kg 3x10';

  @override
  String get quickAddSave => 'Save';

  @override
  String get quickAddAcceptedFormats => 'Accepted formats:';

  @override
  String quickAddSetsIdentified(Object count) {
    return '$count set(s) identified';
  }

  @override
  String get quickAddRecentExercises => 'Recent Exercises';

  @override
  String quickAddExerciseNotFound(Object name) {
    return 'Exercise \"$name\" not found';
  }

  @override
  String get quickAddCreate => 'Create';

  @override
  String quickAddSaved(Object count, Object name) {
    return '✅ $name • $count sets registered';
  }

  @override
  String quickAddCreatedAndSaved(Object name) {
    return '✅ $name created and registered!';
  }

  @override
  String get quickAddFormatError => 'Format: ExerciseName Weight [SetsxReps]';

  @override
  String get quickAddWeightNotFound =>
      'Weight not found. Use: Name Weight [SetsxReps]';

  @override
  String get quickAddNoSets => 'No sets identified';

  @override
  String get exerciseDetailEdit => 'Edit';

  @override
  String get exerciseDetailHistory => 'History';

  @override
  String get exerciseDetailCharts => 'Charts';

  @override
  String get exerciseDetailChart1RM => '1RM';

  @override
  String get exerciseDetailChartMaxWeight => 'Max Weight';

  @override
  String get exerciseDetailChartVolume => 'Volume';

  @override
  String get exerciseDetailChartTotalReps => 'Total Reps';

  @override
  String get workoutDetailContinue => 'Continue Workout';

  @override
  String get workoutDetailDelete => 'Delete Workout';

  @override
  String get workoutDetailDeleteConfirm => 'Delete Workout?';

  @override
  String get workoutDetailEdit => 'Edit Workout';

  @override
  String get workoutDetailEditDate => 'Change Date';

  @override
  String get workoutDetailShare => 'Share';

  @override
  String get workoutDetailNoSets => 'No sets';

  @override
  String get workoutDetailWeight => 'Weight';

  @override
  String get workoutDetailDateChanged => '✅ Date changed!';

  @override
  String get workoutDetailKg => 'kg';

  @override
  String get workoutDetailViewExercise => 'View exercise';

  @override
  String get workoutDetailSelectDate => 'Select the new date';

  @override
  String get workoutDetailCopy => 'Copy Workout';

  @override
  String get workoutDetailCopyDateChanged => '✅ Workout copied!';

  @override
  String get workoutDetailGoToWorkout => 'Go to workout';

  @override
  String workoutDetailDuration(Object min, Object sec) {
    return '${min}min ${sec}s';
  }

  @override
  String get activeWorkoutTitle => 'Workout';

  @override
  String get activeWorkoutFinishWorkout => 'Finish';

  @override
  String get activeWorkoutFinished => '💪 Workout finished!';

  @override
  String activeWorkoutFinishedWithPRs(Object count) {
    return '🎉 Workout finished! $count personal record(s)!';
  }

  @override
  String get activeWorkoutAddExercise => 'Add Exercise';

  @override
  String get activeWorkoutEmptyTitle => 'No exercises yet';

  @override
  String get activeWorkoutEmptySubtitle =>
      'Add exercises to start your workout';

  @override
  String get activeWorkoutImportRoutine => 'Import from Routine';

  @override
  String get activeWorkoutEditSet => 'Edit Set';

  @override
  String get activeWorkoutWarmup => 'Warm-up';

  @override
  String get activeWorkoutRemoveExercise => 'Remove Exercise?';

  @override
  String activeWorkoutRemoveExerciseContent(Object name) {
    return 'Remove \"$name\" from the workout?';
  }

  @override
  String activeWorkoutRemoved(Object name) {
    return '$name removed from workout';
  }

  @override
  String get activeWorkoutResetTimer => 'Reset Timer?';

  @override
  String get activeWorkoutResetTimerContent =>
      'This will clear the start and end time of the workout.';

  @override
  String get activeWorkoutReset => 'Reset';

  @override
  String get activeWorkoutWeight => 'Weight (kg)';

  @override
  String get activeWorkoutReps => 'Reps';

  @override
  String get activeWorkoutDistance => 'Distance (km)';

  @override
  String get activeWorkoutTime => 'Time';

  @override
  String get activeWorkoutTimerDuration => 'Duration';

  @override
  String get activeWorkoutTimerStartLabel => 'Started at';

  @override
  String get activeWorkoutTimerTitle => 'Timer';

  @override
  String get activeWorkoutNoRoutineFound =>
      'No routine found. Create one first!';

  @override
  String get activeWorkoutNoRoutineDays => 'This routine has no days.';

  @override
  String get activeWorkoutRoutineImported =>
      '✅ Exercises imported from routine!';

  @override
  String get activeWorkoutSelectRoutine => 'Select Routine';

  @override
  String get activeWorkoutBack => 'Back';

  @override
  String get activeWorkoutStart => 'Start';

  @override
  String get activeWorkoutStartTimerTooltip => 'Start workout timer';

  @override
  String activeWorkoutSetsSummary(Object completed, Object total) {
    return '$completed/$total sets';
  }

  @override
  String get activeWorkoutOK => 'OK';

  @override
  String get activeWorkoutRemove => 'Remove';

  @override
  String get activeWorkoutCustom => 'Custom';

  @override
  String get activeWorkoutCustomTime => 'Custom Time';

  @override
  String get activeWorkoutSelectDay => 'Select the day to import';

  @override
  String get activeWorkoutAddSet => 'Add Set';

  @override
  String get activeWorkoutCompleted => 'Workout Completed!';

  @override
  String get activeWorkoutSummarySubtitle => 'Great job! Here\'s the summary:';

  @override
  String get activeWorkoutPersonalRecords => 'New Personal Records';

  @override
  String get activeWorkoutHowWasWorkout => 'How was the workout?';

  @override
  String get activeWorkoutCommentHint => 'Workout note (optional)...';

  @override
  String get activeWorkoutFeeling1 => 'Bad';

  @override
  String get activeWorkoutFeeling2 => 'Ok';

  @override
  String get activeWorkoutFeeling3 => 'Good';

  @override
  String get activeWorkoutFeeling4 => 'Great';

  @override
  String get activeWorkoutFeeling5 => 'Excellent!';

  @override
  String activeWorkoutSetLabel(Object number) {
    return 'Set $number';
  }

  @override
  String get workoutDetailSetNumber => '#';

  @override
  String get workoutDetailRpe => 'RPE';

  @override
  String get notificationRestChannelName => 'Rest Timer';

  @override
  String get notificationRestChannelDesc =>
      'Rest timer notifications between sets';

  @override
  String get notificationWorkoutChannelName => 'Workout Timer';

  @override
  String get notificationWorkoutChannelDesc =>
      'Active workout timer notifications';

  @override
  String get exportServiceBackupText => 'Workout Notes - Workout Backup';

  @override
  String get exportServiceCsvText => 'Workout Notes - Workout Export';

  @override
  String get exportServiceCsvHeaderDate => 'Date';

  @override
  String get exportServiceCsvHeaderExercise => 'Exercise';

  @override
  String get exportServiceCsvHeaderCategory => 'Category';

  @override
  String get exportServiceCsvHeaderWeight => 'Weight';

  @override
  String get exportServiceCsvHeaderReps => 'Reps';

  @override
  String get exportServiceCsvHeaderDistance => 'Distance';

  @override
  String get exportServiceCsvHeaderTime => 'Time (s)';

  @override
  String get exportServiceCsvHeaderWarmup => 'Warm-up';

  @override
  String get exportServiceCsvHeaderRpe => 'RPE';

  @override
  String get exportServiceCsvHeaderSetNote => 'Set Note';

  @override
  String get exportServiceCsvHeaderWorkoutNote => 'Workout Note';

  @override
  String get exportServiceCsvYes => 'Yes';

  @override
  String get exportServiceCsvNo => 'No';

  @override
  String exportServiceWorkoutSummary(Object date) {
    return '🏋️ Workout - $date\n';
  }

  @override
  String exportServiceWorkoutNote(Object note) {
    return '📝 $note\n';
  }

  @override
  String get noticePermissionTitle => 'Rest Timer Permission';

  @override
  String get noticePermissionBody =>
      'This app needs notification permission to alert you when rest time is over during workouts.';

  @override
  String get routinesDayDashboard => 'Day Dashboard';

  @override
  String get routinesNoExercisesHint =>
      'Add exercises to build your workout template';

  @override
  String get routinesDayDashboardSets => 'sets';

  @override
  String get routinesDayDashboardVolume => 'kg volume';

  @override
  String get routinesDayDashboardGroups => 'groups';

  @override
  String get routinesWeeklyView => 'Weekly View';

  @override
  String get routinesPerDay => 'Per Day';

  @override
  String routinesDaySets(Object count) {
    return '$count sets';
  }

  @override
  String routinesDayGroups(Object count) {
    return '$count groups';
  }

  @override
  String routinesInsightMuscleGroups(Object count) {
    return '📋 $count muscle groups this week';
  }

  @override
  String get routinesInsightBalanced =>
      '⚖️ Balanced week! All groups with similar volume.';

  @override
  String routinesInsightHighDiff(
    Object highest,
    Object highestSets,
    Object lowest,
    Object lowestSets,
  ) {
    return '💪 $highest (${highestSets}s) is far above $lowest (${lowestSets}s). Consider redistributing.';
  }

  @override
  String routinesInsightFocus(
    Object highest,
    Object lowest,
    Object lowestSets,
    Object pct,
  ) {
    return '📊 Focus on $highest ($pct% of sets). $lowest with ${lowestSets}s — lower volume.';
  }

  @override
  String routinesInsightAverage(Object avg, Object days) {
    return 'Average of $avg sets/day over $days training days.';
  }

  @override
  String routinesWeeklyVolume(Object volume) {
    return '${volume}kg volume';
  }

  @override
  String routinesWeeklyDays(Object count) {
    return '$count days';
  }

  @override
  String get routinesNotes => 'Description';

  @override
  String get routinesNotesHint => 'Optional routine description';

  @override
  String get reorderHint => 'Press and hold an exercise to reorder';

  @override
  String get reorderMovedToTop => 'Moved to top';

  @override
  String get reorderMovedToBottom => 'Moved to bottom';

  @override
  String get editWorkoutTitle => 'Edit Workout';

  @override
  String get editWorkoutDateTime => 'Date and Time';

  @override
  String get editWorkoutStart => 'Start';

  @override
  String get editWorkoutEnd => 'End';

  @override
  String get editWorkoutDuration => 'Duration';

  @override
  String get editWorkoutChangeDate => 'Change Date';

  @override
  String get editWorkoutChangeStart => 'Change start time';

  @override
  String get editWorkoutChangeEnd => 'Change end time';

  @override
  String get editWorkoutChangeStartDate => 'Change start date and time';

  @override
  String get editWorkoutChangeEndDate => 'Change end date and time';

  @override
  String get editWorkoutSelectDate => 'Select date';

  @override
  String get editWorkoutSelectTime => 'Select time';

  @override
  String get editWorkoutEndAfterStart => 'End time must be after start time';

  @override
  String get editWorkoutInvalidRange => 'Invalid date range';

  @override
  String get editWorkoutSaved => 'Workout updated';

  @override
  String get editWorkoutReorderHint => 'Press and hold an exercise to reorder';

  @override
  String get editWorkoutAddExercise => 'Add Exercise';

  @override
  String get progressGoals => 'Goals';

  @override
  String get progressGoalsSubtitle => 'Track and beat your personal challenges';

  @override
  String get goalScopeAnaerobic => 'Strength';

  @override
  String get goalScopeAerobic => 'Cardio';

  @override
  String get goalMetricVolume => 'Volume';

  @override
  String get goalMetricDays => 'Days';

  @override
  String get goalMetricDistance => 'Distance';

  @override
  String get goalMetricTime => 'Time';

  @override
  String get goalPeriodWeekly => 'Weekly';

  @override
  String get goalPeriodMonthly => 'Monthly';

  @override
  String get goalCreateTitle => 'New Goal';

  @override
  String get goalEditTitle => 'Edit Goal';

  @override
  String get goalLabelTitle => 'Title (optional)';

  @override
  String get goalTitleHint => 'e.g. Hypertrophy month';

  @override
  String get goalChooseMetric => 'Pick a metric';

  @override
  String get goalChoosePeriod => 'Period';

  @override
  String get goalTargetValue => 'Target value';

  @override
  String get goalTargetHint => 'Numeric value';

  @override
  String get goalCurrentProgress => 'Current progress';

  @override
  String goalDaysRemaining(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days left',
      one: '1 day left',
    );
    return '$_temp0';
  }

  @override
  String get goalCompleted => 'Goal reached! 🎉';

  @override
  String get goalKeepGoing => 'Keep pushing!';

  @override
  String get goalHistory => 'History';

  @override
  String get goalEmpty => 'No goals yet';

  @override
  String get goalEmptySubtitle => 'Tap + to create your first goal';

  @override
  String get goalDelete => 'Delete goal';

  @override
  String get goalDeleteConfirm => 'Delete this goal?';

  @override
  String get goalDeleteMessage => 'This action cannot be undone.';

  @override
  String get goalPaused => 'Paused';

  @override
  String get goalPausedBadge => 'PAUSED';

  @override
  String goalAchievementRate(Object rate) {
    return '$rate% success';
  }

  @override
  String get goalGridAdd => 'Add goal';

  @override
  String goalSuggestedTarget(Object value) {
    return 'Suggested: $value';
  }

  @override
  String get goalPickScope => 'Energy System';

  @override
  String get goalPickScopeSubtitle => 'Strength or Cardio?';

  @override
  String get goalStep1 => 'Scope';

  @override
  String get goalStep2 => 'Metric';

  @override
  String get goalStep3 => 'Details';

  @override
  String get goalNoHistory => 'No past periods';

  @override
  String get goalNoHistoryHint =>
      'History will appear after the first cycle completes';

  @override
  String get goalResume => 'Resume';

  @override
  String get goalPause => 'Pause';

  @override
  String get goalSaved => 'Goal saved';

  @override
  String get goalDeleted => 'Goal deleted';

  @override
  String goalValueVolumeKg(Object value) {
    return '$value kg';
  }

  @override
  String goalValueDistance(Object value) {
    return '$value km';
  }

  @override
  String goalValueTime(Object value) {
    return '$value';
  }

  @override
  String goalValueDays(Object value) {
    return '$value days';
  }

  @override
  String goalValueDaysShort(Object value) {
    return '${value}d';
  }

  @override
  String get goalMotivationNear => 'Almost there — you got this!';

  @override
  String get goalMotivationMid => 'On track. Keep going!';

  @override
  String get goalMotivationEarly => 'Let\'s start! Every workout counts.';

  @override
  String get goalMotivationDone => 'Amazing! You crushed your goal!';

  @override
  String get goalContributingWorkouts => 'Workouts this period';

  @override
  String get goalNoContributors => 'No workouts in this period yet';

  @override
  String get progressPeriodWeek => 'Week';

  @override
  String get progressPeriodMonth => 'Month';

  @override
  String get progressPeriodYear => 'Year';

  @override
  String get progressVolumeTypeWeight => 'Weight';

  @override
  String get progressVolumeTypeSets => 'Sets';

  @override
  String get progressVolumeTrend => 'Trend';

  @override
  String get progressVolumeTrendLast12Weeks => 'Last 12 weeks';

  @override
  String get progressVolumeTrendLast12Months => 'Last 12 months';

  @override
  String get progressVolumeTrendLast5Years => 'Last 5 years';

  @override
  String get progressVolumeUnitSets => 'sets';

  @override
  String get progressVolumeUnitWeight => 'kg';

  @override
  String get progressVolumeViewPie => 'Pie';

  @override
  String get progressVolumeViewList => 'List';

  @override
  String get progressVolumeTotal => 'Total';
}
