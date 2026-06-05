/// ====================================================================
/// ABSTRACT MIXIN — Workout Home, Calendar, Export, Progress,
///                  Body Tracker, Rest Timer, Exercise, Quick Add,
///                  Workout Detail, Notifications, Export Service
/// ====================================================================
mixin WorkoutLocale {
  // Workout Home
  String get workoutHomeTitle;
  String get workoutHomeHistoryTooltip;
  String get workoutHomeSettingsTooltip;
  String get workoutHomeMonthWorkouts;
  String get workoutHomeVolume;
  String get workoutHomeStreak;
  String get workoutHomeDay;
  String get workoutHomeDays;
  String get workoutHomeNewWorkout;
  String get workoutHomeStartNow;
  String get workoutHomeQuickAdd;
  String get workoutHomeQuickAddSubtitle;
  String get workoutHomeNavigation;
  String get workoutHomeExercises;
  String get workoutHomeRoutines;
  String get workoutHomeProgress;
  String get workoutHomeBodyMeasurements;
  String get workoutHomeInProgress;
  String get workoutHomeNoActiveWorkout;
  String get workoutHomeUpcoming;
  String get workoutHomeCompleted;
  String get workoutHomeOngoing;
  String get workoutHomeContinueWorkout;
  String get workoutHomeDeleteWorkout;

  // Calendar
  String get calendarTitle;
  String get calendarSun;
  String get calendarMon;
  String get calendarTue;
  String get calendarWed;
  String get calendarThu;
  String get calendarFri;
  String get calendarSat;
  String calendarNoWorkouts(Object date);
  String get calendarCreateWorkout;
  String get calendarNoTime;
  String get calendarInProgress;
  String get calendarWorkoutCreated;
  String get calendarSelectNewDate;

  // Export
  String get exportTitle;
  String get exportJsonBackup;
  String get exportJsonBackupSubtitle;
  String get exportCsv;
  String get exportCsvSubtitle;
  String get exportShareSummary;
  String get exportShareSummarySubtitle;
  String get exportTips;
  String get exportTipsContent;
  String get exportCsvDialogTitle;
  String get exportCsvExerciseLabel;
  String get exportCsvExerciseHint;
  String get exportCsvStartDate;
  String get exportCsvEndDate;
  String get exportCsvButton;
  String get exportShareWorkoutTitle;
  String get exportNoWorkouts;
  String get exportSuccess;
  String get exportCsvSuccess;
  String exportError(Object error);

  // Progress
  String get progressTitle;
  String progressMonthlyReport(Object month);
  String get progressWorkouts;
  String get progressSets;
  String get progressDays;
  String progressAverageFeeling(Object rating);
  String progressVsLastMonth(Object delta);
  String get progressStreak;
  String get progressFrequency;
  String get progressVolumeGroups;
  String get progressExerciseHistory;
  String get progressDurationEfficiency;
  String get progressRecovery;
  String get progressBodyMeasurements;
  String get progressYearHeatmap;
  String get progressWeeklyFrequency;
  String get progressDayOfWeek;
  String get progressTimeOfDay;
  String get progressMorning;
  String get progressAfternoon;
  String get progressEvening;
  String get progressDawn;
  String get progressNoData;
  String get progressVolumeByGroup;
  String get progressEnergySystem;
  String get progressAerobic;
  String get progressAnaerobic;
  String get progressTopExercises;
  String get progressNoExercises;
  String get progressTapForHistory;
  String get progressDuration;
  String progressAverage(Object avg);
  String get progressDensity;
  String get progressBodyWeight;
  String get progressNoChartData;
  String get progressHistoryTitle;
  String get progressHistoryDate;
  String get progressHistorySetsReps;
  String get progressLoadError;
  String progressHeatmapNoData(Object year);
  String get progressChartTitleProgress;
  String get progressChartTitleVolumePerWorkout;
  String get progressChartTitleRepsPerWorkout;
  String get progressRecoveryFeeling;
  String get progressRecoveryFeelingVsVolume;
  String get progressBodyWeightVsVolume;
  String get progressVolumeByMonth;

  // Body Tracker
  String get bodyTrackerTitle;
  String get bodyTrackerWeight;
  String get bodyTrackerBodyFat;
  String get bodyTrackerWaist;
  String get bodyTrackerChest;
  String get bodyTrackerArm;
  String get bodyTrackerThigh;
  String get bodyTrackerHip;
  String get bodyTrackerAdd;
  String bodyTrackerAddTitle(Object type);
  String get bodyTrackerValue;
  String get bodyTrackerDate;
  String get bodyTrackerComment;
  String get bodyTrackerSave;
  String get bodyTrackerSaved;
  String get bodyTrackerDeleted;
  String get bodyTrackerDeleteConfirm;

  // Rest Timer
  String get restTimerTitle;
  String get restTimerStop;
  String get restTimerComplete;
  String get restTimerPaused;
  String get restTimerResting;
  String get restTimerReady;
  String get restTimerResume;
  String get restTimerPause;
  String get restTimerStartRest;

  // Exercise Library
  String get exerciseLibraryTitle;
  String get exerciseLibraryFavorites;
  String get exerciseLibrarySearch;
  String get exerciseLibraryAll;
  String get exerciseLibraryNoResults;
  String get exerciseLibraryNoResultsHint;
  String get exerciseLibraryNew;
  String get exerciseLibraryAerobic;
  String get exerciseLibraryAnaerobic;

  // Exercise Form
  String get exerciseFormTitleNew;
  String get exerciseFormTitleEdit;
  String get exerciseFormName;
  String get exerciseFormNameHint;
  String get exerciseFormCategory;
  String get exerciseFormType;
  String get exerciseFormEquipment;
  String get exerciseFormEquipmentHint;
  String get exerciseFormWeightIncrement;
  String get exerciseFormWeightIncrementHint;
  String get exerciseFormDefaultRest;
  String get exerciseFormDefaultRestHint;
  String get exerciseFormNotes;
  String get exerciseFormNotesHint;
  String get exerciseFormNameRequired;
  String get exerciseFormSave;
  String exerciseFormError(Object error);
  String get exerciseFormTypeWeightReps;
  String get exerciseFormTypeDistanceTime;
  String get exerciseFormTypeWeightDistance;
  String get exerciseFormTypeWeightTime;
  String get exerciseFormTypeRepsDistance;
  String get exerciseFormTypeRepsTime;
  String get exerciseFormTypeWeightOnly;
  String get exerciseFormTypeRepsOnly;
  String get exerciseFormTypeDistanceOnly;
  String get exerciseFormTypeTimeOnly;

  // Quick Add
  String get quickAddTitle;
  String get quickAddHint;
  String get quickAddSave;
  String get quickAddAcceptedFormats;
  String quickAddSetsIdentified(Object count);
  String get quickAddRecentExercises;
  String quickAddExerciseNotFound(Object name);
  String get quickAddCreate;
  String quickAddSaved(Object count, Object name);
  String quickAddCreatedAndSaved(Object name);
  String get quickAddFormatError;
  String get quickAddWeightNotFound;
  String get quickAddNoSets;

  // Exercise Detail
  String get exerciseDetailEdit;
  String get exerciseDetailHistory;
  String get exerciseDetailCharts;
  String get exerciseDetailChart1RM;
  String get exerciseDetailChartMaxWeight;
  String get exerciseDetailChartVolume;
  String get exerciseDetailChartTotalReps;

  // Workout Detail
  String get workoutDetailContinue;
  String get workoutDetailDelete;
  String get workoutDetailDeleteConfirm;
  String get workoutDetailEditDate;
  String get workoutDetailShare;
  String get workoutDetailNoSets;
  String get workoutDetailWeight;
  String get workoutDetailDateChanged;
  String get workoutDetailKg;
  String get workoutDetailViewExercise;
  String get workoutDetailSelectDate;
  String workoutDetailDuration(int min, int sec);
  String get activeWorkoutTitle;
  String get activeWorkoutFinishWorkout;
  String get activeWorkoutAddExercise;
  String get activeWorkoutEmptyTitle;
  String get activeWorkoutEmptySubtitle;
  String get activeWorkoutImportRoutine;
  String get activeWorkoutEditSet;
  String get activeWorkoutWarmup;
  String get activeWorkoutRemoveExercise;
  String activeWorkoutRemoveExerciseContent(Object name);
  String activeWorkoutRemoved(Object name);
  String get activeWorkoutResetTimer;
  String get activeWorkoutResetTimerContent;
  String get activeWorkoutReset;
  String get activeWorkoutWeight;
  String get activeWorkoutReps;
  String get activeWorkoutDistance;
  String get activeWorkoutTime;
  String get activeWorkoutNoRoutineFound;
  String get activeWorkoutNoRoutineDays;
  String get activeWorkoutRoutineImported;
  String get activeWorkoutSelectRoutine;
  String get activeWorkoutBack;
  String get activeWorkoutStart;
  String get activeWorkoutStartTimerTooltip;
  String activeWorkoutSetsSummary(int completed, int total);
  String get activeWorkoutOK;
  String get activeWorkoutRemove;
  String get activeWorkoutCustom;
  String get activeWorkoutCustomTime;
  String get activeWorkoutSelectDay;
  String get activeWorkoutAddSet;
  String get workoutDetailSetNumber;
  String get workoutDetailRpe;

  // Notifications
  String get notificationRestChannelName;
  String get notificationRestChannelDesc;
  String get notificationWorkoutChannelName;
  String get notificationWorkoutChannelDesc;

  // Export Service
  String get exportServiceBackupText;
  String get exportServiceCsvText;
  String get exportServiceCsvHeaderDate;
  String get exportServiceCsvHeaderExercise;
  String get exportServiceCsvHeaderCategory;
  String get exportServiceCsvHeaderWeight;
  String get exportServiceCsvHeaderReps;
  String get exportServiceCsvHeaderDistance;
  String get exportServiceCsvHeaderTime;
  String get exportServiceCsvHeaderWarmup;
  String get exportServiceCsvHeaderRpe;
  String get exportServiceCsvHeaderSetNote;
  String get exportServiceCsvHeaderWorkoutNote;
  String get exportServiceCsvYes;
  String get exportServiceCsvNo;
  String exportServiceWorkoutSummary(Object date);
  String exportServiceWorkoutNote(Object note);
}

/// ====================================================================
/// EN IMPLEMENTATION
/// ====================================================================
mixin WorkoutLocaleEn on WorkoutLocale {
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
    return 'Exercise "$name" not found';
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
  String workoutDetailDuration(int min, int sec) {
    return '$min' + 'min ' + '$sec' + 's';
  }

  @override
  String get activeWorkoutTitle => 'Workout';

  @override
  String get activeWorkoutFinishWorkout => 'Finish';

  @override
  String get activeWorkoutAddExercise => 'Add Exercise';

  @override
  String get activeWorkoutEmptyTitle => 'No exercises yet';

  @override
  String get activeWorkoutEmptySubtitle => 'Add exercises to start your workout';

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
    return 'Remove "$name" from the workout?';
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
  String activeWorkoutSetsSummary(int completed, int total) {
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
}

/// ====================================================================
/// PT IMPLEMENTATION
/// ====================================================================
mixin WorkoutLocalePt on WorkoutLocale {
  @override
  String get workoutHomeTitle => 'Treino';

  @override
  String get workoutHomeHistoryTooltip => 'Histórico';

  @override
  String get workoutHomeSettingsTooltip => 'Configurações';

  @override
  String get workoutHomeMonthWorkouts => 'Treinos no Mês';

  @override
  String get workoutHomeVolume => 'Volume';

  @override
  String get workoutHomeStreak => 'Sequência';

  @override
  String get workoutHomeDay => 'dia';

  @override
  String get workoutHomeDays => 'dias';

  @override
  String get workoutHomeNewWorkout => 'Novo Treino';

  @override
  String get workoutHomeStartNow => 'Começar agora';

  @override
  String get workoutHomeQuickAdd => 'Quick Add';

  @override
  String get workoutHomeQuickAddSubtitle => 'Adicionar rápido';

  @override
  String get workoutHomeNavigation => 'NAVEGAÇÃO';

  @override
  String get workoutHomeExercises => 'Exercícios';

  @override
  String get workoutHomeRoutines => 'Rotinas';

  @override
  String get workoutHomeProgress => 'Progresso';

  @override
  String get workoutHomeBodyMeasurements => 'Medidas';

  @override
  String get workoutHomeInProgress => 'EM ANDAMENTO';

  @override
  String get workoutHomeNoActiveWorkout => 'Nenhum treino em andamento';

  @override
  String get workoutHomeUpcoming => 'PRÓXIMOS TREINOS';

  @override
  String get workoutHomeCompleted => 'TREINOS CONCLUÍDOS';

  @override
  String get workoutHomeOngoing => 'Em andamento';

  @override
  String get workoutHomeContinueWorkout => 'Continuar Treino';

  @override
  String get workoutHomeDeleteWorkout => 'Excluir Treino';

  @override
  String get calendarTitle => 'Histórico';

  @override
  String get calendarSun => 'Dom';

  @override
  String get calendarMon => 'Seg';

  @override
  String get calendarTue => 'Ter';

  @override
  String get calendarWed => 'Qua';

  @override
  String get calendarThu => 'Qui';

  @override
  String get calendarFri => 'Sex';

  @override
  String get calendarSat => 'Sáb';

  @override
  String calendarNoWorkouts(Object date) {
    return 'Nenhum treino em $date';
  }

  @override
  String get calendarCreateWorkout => 'Criar Treino';

  @override
  String get calendarNoTime => 'Sem horário';

  @override
  String get calendarInProgress => 'Em andamento';

  @override
  String get calendarWorkoutCreated => '✅ Treino criado para este dia!';

  @override
  String get calendarSelectNewDate => 'Selecione a nova data';

  @override
  String get exportTitle => 'Exportar Dados';

  @override
  String get exportJsonBackup => 'Backup Completo (JSON)';

  @override
  String get exportJsonBackupSubtitle =>
      'Exporta todos os dados: treinos, exercícios, rotinas, medidas e configurações';

  @override
  String get exportCsv => 'Exportar CSV';

  @override
  String get exportCsvSubtitle =>
      'Exporta histórico de treinos (data, exercício, peso, reps) - filtrável por exercício e data';

  @override
  String get exportShareSummary => 'Compartilhar Resumo';

  @override
  String get exportShareSummarySubtitle =>
      'Gera um resumo de texto de um treino específico para compartilhar';

  @override
  String get exportTips => 'Dicas';

  @override
  String get exportTipsContent =>
      '• O backup JSON contém todos os dados do app\n• CSV é ideal para análise em Excel/Google Sheets\n• Os arquivos são salvos temporariamente e compartilhados via share sheet nativo';

  @override
  String get exportCsvDialogTitle => 'Exportar CSV';

  @override
  String get exportCsvExerciseLabel =>
      'Exercício (opcional - vazio exporta todos)';

  @override
  String get exportCsvExerciseHint => 'Deixe vazio para todos';

  @override
  String get exportCsvStartDate => 'Data início';

  @override
  String get exportCsvEndDate => 'Data fim';

  @override
  String get exportCsvButton => 'Exportar CSV';

  @override
  String get exportShareWorkoutTitle => 'Compartilhar Treino';

  @override
  String get exportNoWorkouts => 'Nenhum treino para compartilhar';

  @override
  String get exportSuccess => 'Backup exportado com sucesso!';

  @override
  String get exportCsvSuccess => 'CSV exportado com sucesso!';

  @override
  String exportError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get progressTitle => 'Progresso';

  @override
  String progressMonthlyReport(Object month) {
    return 'RESUMO DE $month';
  }

  @override
  String get progressWorkouts => 'Treinos';

  @override
  String get progressSets => 'Séries';

  @override
  String get progressDays => 'Dias';

  @override
  String progressAverageFeeling(Object rating) {
    return 'Sentimento médio: $rating ★';
  }

  @override
  String progressVsLastMonth(Object delta) {
    return '$delta vs mês ant.';
  }

  @override
  String get progressStreak => 'Sequência';

  @override
  String get progressFrequency => 'Frequência & Consistência';

  @override
  String get progressVolumeGroups => 'Volume & Grupos Musculares';

  @override
  String get progressExerciseHistory => 'Histórico dos Exercícios';

  @override
  String get progressDurationEfficiency => 'Duração & Eficiência';

  @override
  String get progressRecovery => 'Recuperação & Bem-estar';

  @override
  String get progressBodyMeasurements => 'Medidas Corporais';

  @override
  String get progressYearHeatmap => 'Mapa de calor anual';

  @override
  String get progressWeeklyFrequency =>
      'Frequência semanal (últimas 12 semanas)';

  @override
  String get progressDayOfWeek => 'Dia da semana';

  @override
  String get progressTimeOfDay => 'Horário';

  @override
  String get progressMorning => 'Manhã';

  @override
  String get progressAfternoon => 'Tarde';

  @override
  String get progressEvening => 'Noite';

  @override
  String get progressDawn => 'Madrugada';

  @override
  String get progressNoData => 'Sem dados';

  @override
  String get progressVolumeByGroup => 'Volume por Grupo';

  @override
  String get progressEnergySystem => 'Sistema Energético';

  @override
  String get progressAerobic => 'Aeróbico';

  @override
  String get progressAnaerobic => 'Anaeróbico';

  @override
  String get progressTopExercises => 'Top Exercícios por Volume';

  @override
  String get progressNoExercises => 'Nenhum exercício cadastrado';

  @override
  String get progressTapForHistory =>
      'Toque em um exercício para ver o histórico completo';

  @override
  String get progressDuration => 'Duração dos Treinos';

  @override
  String progressAverage(Object avg) {
    return 'Média: ${avg}min';
  }

  @override
  String get progressDensity => 'Densidade (Volume por Minuto)';

  @override
  String get progressBodyWeight => 'Peso Corporal';

  @override
  String get progressNoChartData => 'Nenhum dado disponível para este gráfico';

  @override
  String get progressHistoryTitle => 'Histórico de Treinos';

  @override
  String get progressHistoryDate => 'Data';

  @override
  String get progressHistorySetsReps => 'Séries × Reps';

  @override
  String get progressLoadError => 'Erro ao carregar dados';

  @override
  String progressHeatmapNoData(Object year) {
    return 'Nenhum dado para $year';
  }

  @override
  String get progressChartTitleProgress => 'Progresso';

  @override
  String get progressChartTitleVolumePerWorkout => 'Volume por Treino';

  @override
  String get progressChartTitleRepsPerWorkout => 'Repetições por Treino';

  @override
  String get progressRecoveryFeeling => 'Sentimento ao Longo do Tempo';

  @override
  String get progressRecoveryFeelingVsVolume => 'Sentimento vs Volume Médio';

  @override
  String get progressBodyWeightVsVolume => 'Peso Corporal vs Volume de Treino';

  @override
  String get progressVolumeByMonth => 'Volume por Mês';

  @override
  String get bodyTrackerTitle => 'Medidas Corporais';

  @override
  String get bodyTrackerWeight => 'Peso Corporal';

  @override
  String get bodyTrackerBodyFat => '% Gordura';

  @override
  String get bodyTrackerWaist => 'Cintura';

  @override
  String get bodyTrackerChest => 'Peito';

  @override
  String get bodyTrackerArm => 'Braço';

  @override
  String get bodyTrackerThigh => 'Coxa';

  @override
  String get bodyTrackerHip => 'Quadril';

  @override
  String get bodyTrackerAdd => 'Adicionar Medida';

  @override
  String bodyTrackerAddTitle(Object type) {
    return 'Adicionar $type';
  }

  @override
  String get bodyTrackerValue => 'Valor';

  @override
  String get bodyTrackerDate => 'Data';

  @override
  String get bodyTrackerComment => 'Comentário';

  @override
  String get bodyTrackerSave => 'Salvar';

  @override
  String get bodyTrackerSaved => '✅ Medida salva!';

  @override
  String get bodyTrackerDeleted => 'Medida excluída';

  @override
  String get bodyTrackerDeleteConfirm => 'Excluir esta medida?';

  @override
  String get restTimerTitle => 'Temporizador';

  @override
  String get restTimerStop => 'Parar';

  @override
  String get restTimerComplete => 'CONCLUÍDO';

  @override
  String get restTimerPaused => 'PAUSADO';

  @override
  String get restTimerResting => 'DESCANSANDO';

  @override
  String get restTimerReady => 'PRONTO';

  @override
  String get restTimerResume => 'Continuar';

  @override
  String get restTimerPause => 'Pausar';

  @override
  String get restTimerStartRest => 'Iniciar descanso';

  @override
  String get exerciseLibraryTitle => 'Exercícios';

  @override
  String get exerciseLibraryFavorites => 'Favoritos';

  @override
  String get exerciseLibrarySearch => 'Buscar exercício...';

  @override
  String get exerciseLibraryAll => 'Todos';

  @override
  String get exerciseLibraryNoResults => 'Nenhum exercício encontrado';

  @override
  String get exerciseLibraryNoResultsHint =>
      'Tente alterar a busca ou adicione um novo';

  @override
  String get exerciseLibraryNew => 'Novo Exercício';

  @override
  String get exerciseLibraryAerobic => 'Aeróbico';

  @override
  String get exerciseLibraryAnaerobic => 'Anaeróbico';

  @override
  String get exerciseFormTitleNew => 'Novo Exercício';

  @override
  String get exerciseFormTitleEdit => 'Editar Exercício';

  @override
  String get exerciseFormName => 'Nome do Exercício';

  @override
  String get exerciseFormNameHint => 'Ex: Supino Inclinado';

  @override
  String get exerciseFormCategory => 'Grupo Muscular';

  @override
  String get exerciseFormType => 'Tipo';

  @override
  String get exerciseFormEquipment => 'Equipamento (opcional)';

  @override
  String get exerciseFormEquipmentHint => 'Barbell, Dumbbell, Machine...';

  @override
  String get exerciseFormWeightIncrement => 'Incremento de Peso (kg)';

  @override
  String get exerciseFormWeightIncrementHint => 'Ex: 2.5';

  @override
  String get exerciseFormDefaultRest => 'Descanso Padrão (segundos)';

  @override
  String get exerciseFormDefaultRestHint => 'Ex: 90';

  @override
  String get exerciseFormNotes => 'Instruções / Dicas (opcional)';

  @override
  String get exerciseFormNotesHint => 'Dicas de execução, forma correta...';

  @override
  String get exerciseFormNameRequired => 'Nome é obrigatório';

  @override
  String get exerciseFormSave => 'Salvar';

  @override
  String exerciseFormError(Object error) {
    return 'Erro: $error';
  }

  @override
  String get exerciseFormTypeWeightReps => 'Peso × Repetições';

  @override
  String get exerciseFormTypeDistanceTime => 'Distância × Tempo';

  @override
  String get exerciseFormTypeWeightDistance => 'Peso × Distância';

  @override
  String get exerciseFormTypeWeightTime => 'Peso × Tempo';

  @override
  String get exerciseFormTypeRepsDistance => 'Repetições × Distância';

  @override
  String get exerciseFormTypeRepsTime => 'Repetições × Tempo';

  @override
  String get exerciseFormTypeWeightOnly => 'Apenas Peso';

  @override
  String get exerciseFormTypeRepsOnly => 'Apenas Repetições';

  @override
  String get exerciseFormTypeDistanceOnly => 'Apenas Distância';

  @override
  String get exerciseFormTypeTimeOnly => 'Apenas Tempo';

  @override
  String get quickAddTitle => 'Quick Add';

  @override
  String get quickAddHint => 'Ex: Supino 80kg 3x10';

  @override
  String get quickAddSave => 'Salvar';

  @override
  String get quickAddAcceptedFormats => 'Formatos aceitos:';

  @override
  String quickAddSetsIdentified(Object count) {
    return '$count série(s) identificada(s)';
  }

  @override
  String get quickAddRecentExercises => 'Exercícios Recentes';

  @override
  String quickAddExerciseNotFound(Object name) {
    return 'Exercício "$name" não encontrado';
  }

  @override
  String get quickAddCreate => 'Criar';

  @override
  String quickAddSaved(Object count, Object name) {
    return '✅ $name • $count séries registradas';
  }

  @override
  String quickAddCreatedAndSaved(Object name) {
    return '✅ $name criado e registrado!';
  }

  @override
  String get quickAddFormatError =>
      'Formato: NomeExercício Peso [SériesxReps]';

  @override
  String get quickAddWeightNotFound =>
      'Peso não encontrado. Use: Nome Peso [SériesxReps]';

  @override
  String get quickAddNoSets => 'Nenhuma série identificada';

  @override
  String get exerciseDetailEdit => 'Editar';

  @override
  String get exerciseDetailHistory => 'Histórico';

  @override
  String get exerciseDetailCharts => 'Gráficos';

  @override
  String get exerciseDetailChart1RM => '1RM';

  @override
  String get exerciseDetailChartMaxWeight => 'Peso Máx.';

  @override
  String get exerciseDetailChartVolume => 'Volume';

  @override
  String get exerciseDetailChartTotalReps => 'Total Reps';

  @override
  String get workoutDetailContinue => 'Continuar Treino';

  @override
  String get workoutDetailDelete => 'Excluir Treino';

  @override
  String get workoutDetailDeleteConfirm => 'Excluir Treino?';

  @override
  String get workoutDetailEditDate => 'Alterar Data';

  @override
  String get workoutDetailShare => 'Compartilhar';

  @override
  String get workoutDetailNoSets => 'Nenhuma série';

  @override
  String get workoutDetailWeight => 'Peso';

  @override
  String get workoutDetailDateChanged => '✅ Data alterada!';

  @override
  String get workoutDetailKg => 'kg';

  @override
  String get workoutDetailViewExercise => 'Ver exercício';

  @override
  String get workoutDetailSelectDate => 'Selecione a nova data';

  @override
  String workoutDetailDuration(int min, int sec) {
    return '$min' + 'min ' + '$sec' + 's';
  }

  @override
  String get activeWorkoutTitle => 'Treino';

  @override
  String get activeWorkoutFinishWorkout => 'Finalizar';

  @override
  String get activeWorkoutAddExercise => 'Adicionar Exercício';

  @override
  String get activeWorkoutEmptyTitle => 'Nenhum exercício ainda';

  @override
  String get activeWorkoutEmptySubtitle =>
      'Adicione exercícios para começar seu treino';

  @override
  String get activeWorkoutImportRoutine => 'Importar de Rotina';

  @override
  String get activeWorkoutEditSet => 'Editar Série';

  @override
  String get activeWorkoutWarmup => 'Aquecimento';

  @override
  String get activeWorkoutRemoveExercise => 'Remover Exercício?';

  @override
  String activeWorkoutRemoveExerciseContent(Object name) {
    return 'Remover "$name" do treino?';
  }

  @override
  String activeWorkoutRemoved(Object name) {
    return '$name removido do treino';
  }

  @override
  String get activeWorkoutResetTimer => 'Resetar Timer?';

  @override
  String get activeWorkoutResetTimerContent =>
      'Isso vai limpar o tempo de início e fim do treino.';

  @override
  String get activeWorkoutReset => 'Resetar';

  @override
  String get activeWorkoutWeight => 'Peso (kg)';

  @override
  String get activeWorkoutReps => 'Repetições';

  @override
  String get activeWorkoutDistance => 'Distância (km)';

  @override
  String get activeWorkoutTime => 'Tempo';

  @override
  String get activeWorkoutNoRoutineFound =>
      'Nenhuma rotina encontrada. Crie uma primeiro!';

  @override
  String get activeWorkoutNoRoutineDays => 'Esta rotina não tem dias.';

  @override
  String get activeWorkoutRoutineImported =>
      '✅ Exercícios importados da rotina!';

  @override
  String get activeWorkoutSelectRoutine => 'Selecione a Rotina';

  @override
  String get activeWorkoutBack => 'Voltar';

  @override
  String get activeWorkoutStart => 'Iniciar';

  @override
  String get activeWorkoutStartTimerTooltip =>
      'Iniciar cronômetro do treino';

  @override
  String activeWorkoutSetsSummary(int completed, int total) {
    return '$completed/$total séries';
  }

  @override
  String get activeWorkoutOK => 'OK';

  @override
  String get activeWorkoutRemove => 'Remover';

  @override
  String get activeWorkoutCustom => 'Personalizado';

  @override
  String get activeWorkoutCustomTime => 'Tempo Personalizado';

  @override
  String get activeWorkoutSelectDay => 'Selecione o dia para importar';

  @override
  String get activeWorkoutAddSet => 'Adicionar Série';

  @override
  String get workoutDetailSetNumber => '#';

  @override
  String get workoutDetailRpe => 'RPE';

  @override
  String get notificationRestChannelName => 'Timer de Descanso';

  @override
  String get notificationRestChannelDesc =>
      'Notificações do temporizador de descanso entre séries';

  @override
  String get notificationWorkoutChannelName => 'Timer de Treino';

  @override
  String get notificationWorkoutChannelDesc =>
      'Notificações do temporizador de treino ativo';

  @override
  String get exportServiceBackupText => 'Workout Notes - Backup de Treinos';

  @override
  String get exportServiceCsvText => 'Workout Notes - Exportação de Treinos';

  @override
  String get exportServiceCsvHeaderDate => 'Data';

  @override
  String get exportServiceCsvHeaderExercise => 'Exercício';

  @override
  String get exportServiceCsvHeaderCategory => 'Categoria';

  @override
  String get exportServiceCsvHeaderWeight => 'Peso';

  @override
  String get exportServiceCsvHeaderReps => 'Repetições';

  @override
  String get exportServiceCsvHeaderDistance => 'Distância';

  @override
  String get exportServiceCsvHeaderTime => 'Tempo (s)';

  @override
  String get exportServiceCsvHeaderWarmup => 'Aquecimento';

  @override
  String get exportServiceCsvHeaderRpe => 'RPE';

  @override
  String get exportServiceCsvHeaderSetNote => 'Nota';

  @override
  String get exportServiceCsvHeaderWorkoutNote => 'Observação do Treino';

  @override
  String get exportServiceCsvYes => 'Sim';

  @override
  String get exportServiceCsvNo => 'Não';

  @override
  String exportServiceWorkoutSummary(Object date) {
    return '🏋️ Treino - $date\n';
  }

  @override
  String exportServiceWorkoutNote(Object note) {
    return '📝 $note\n';
  }
}
