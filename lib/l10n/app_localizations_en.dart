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
  String get tabSleep => 'Sleep';

  @override
  String get sleepTitle => 'Sleep';

  @override
  String get sleepEmptyTitle => 'No sleep logged';

  @override
  String get sleepEmptySubtitle =>
      'Monitor your nights to track duration, actual sleep, and consistency.';

  @override
  String get sleepDuration => 'Sleep duration';

  @override
  String get sleepActualDuration => 'Actual sleep';

  @override
  String get sleepBedtime => 'Bedtime';

  @override
  String get sleepWakeTime => 'Wake-up time';

  @override
  String get sleepDeleted => 'Sleep record deleted';

  @override
  String get sleepDeleteConfirm => 'Delete this sleep record?';

  @override
  String get sleepSummary => 'Summary';

  @override
  String get sleepLatest => 'Latest record';

  @override
  String get sleepAverage7Days => 'Average · 7 days';

  @override
  String get sleepAverage30Days => 'Average · 30 days';

  @override
  String get sleepActualAverage => 'Actual sleep average';

  @override
  String get sleepMinimum => 'Minimum · 30 days';

  @override
  String get sleepMaximum => 'Maximum · 30 days';

  @override
  String get sleepConsistency => 'Consistency';

  @override
  String get sleepEfficiency => 'Efficiency';

  @override
  String sleepDaysRecorded(Object count, Object total) {
    return '$count of $total days recorded';
  }

  @override
  String get sleepNoActual => 'No actual sleep';

  @override
  String get sleepDailyChart => 'Last 7 days';

  @override
  String get sleepTrendChart => 'Trend · 30 days';

  @override
  String get sleepChartRecorded => 'Recorded duration';

  @override
  String get sleepChartActual => 'Actual sleep';

  @override
  String get sleepHistory => 'History';

  @override
  String sleepEntries(Object count) {
    return '$count records';
  }

  @override
  String get sleepNeedTwoEntries => 'Add at least 2 records to see the trend.';

  @override
  String sleepLoadMore(Object count) {
    return 'Load $count more records';
  }

  @override
  String sleepLoadMoreCount(Object count) {
    return 'Load $count more';
  }

  @override
  String get sleepDetails => 'Sleep details';

  @override
  String get sleepDelete => 'Delete record';

  @override
  String sleepDurationValue(Object hours, Object minutes) {
    return '${hours}h ${minutes}min';
  }

  @override
  String get sleepGoalTitle => 'Sleep goal';

  @override
  String get sleepGoalTarget => 'Target';

  @override
  String get sleepGoalReached => 'Goal reached';

  @override
  String get sleepGoalMissed => 'Goal missed';

  @override
  String get sleepGoalInfo =>
      'A personal target for comparing your nights. It is not a clinical recommendation.';

  @override
  String get sleepMetricSleep => 'Sleep';

  @override
  String get sleepMetricTimeInBed => 'Time in bed';

  @override
  String get sleepGoalDialogTitle => 'Set sleep goal';

  @override
  String get sleepGoalDialogDescription =>
      'Choose how much sleep you want to aim for each night.';

  @override
  String get sleepGoalSaved => 'Sleep goal saved';

  @override
  String sleepGoalCurrent(String duration) {
    return '$duration per night';
  }

  @override
  String get sleepGoalBody =>
      'This target is used to compare your latest night and highlight progress.';

  @override
  String get sleepMonitorOpen => 'Open monitoring';

  @override
  String sleepMonitorElapsed(String duration) {
    return 'Active for $duration';
  }

  @override
  String get sleepWeeklySummary => 'Weekly summary';

  @override
  String get sleepAverageSleep => 'Average sleep';

  @override
  String get sleepRegularity => 'Regularity';

  @override
  String get sleepRegularityInfo =>
      'An app consistency score based on bedtime and wake-up variation. It is not a clinical measurement.';

  @override
  String sleepNightsRecorded(Object count, Object total) {
    return '$count of $total nights recorded';
  }

  @override
  String get sleepScheduleChart => 'Sleep schedule';

  @override
  String get sleepScheduleChartSubtitle =>
      'Bedtime to wake-up time over the last 7 days';

  @override
  String get sleepScheduleNoTimes =>
      'Add bedtime and wake-up times to see your weekly schedule.';

  @override
  String sleepScheduleSemantics(Object count) {
    return 'Weekly sleep schedule with $count nights';
  }

  @override
  String get sleepDurationChart => 'Sleep duration';

  @override
  String get sleepDurationChartSubtitle =>
      'Recorded and actual or estimated sleep by night';

  @override
  String get sleepChartActualOrEstimated => 'Actual / estimated';

  @override
  String get sleepDurationChartSemantics =>
      'Weekly chart comparing recorded and actual or estimated sleep duration';

  @override
  String get sleepPreviousWeek => 'Previous week';

  @override
  String get sleepNextWeek => 'Next week';

  @override
  String get sleepNoRecordForDay => 'No sleep record for this day';

  @override
  String get sleepMonitorCta => 'Monitor sleep';

  @override
  String get sleepMonitorCtaSubtitle =>
      'Analyze quiet and noise locally during the night.';

  @override
  String get sleepMonitorOpenActive => 'Monitoring in progress';

  @override
  String sleepMonitorRecovered(Object count) {
    return '$count monitoring session(s) recovered.';
  }

  @override
  String get sleepMonitorTitle => 'Monitor sleep';

  @override
  String get sleepMonitorAndroidOnly =>
      'Monitoring is available only on Android.';

  @override
  String get sleepMonitorRunning => 'Monitoring in progress';

  @override
  String get sleepMonitorReady => 'Ready to monitor';

  @override
  String get sleepMonitorMicrophone => 'Microphone permission';

  @override
  String get sleepMonitorStart => 'Start monitoring';

  @override
  String sleepMonitorStartWithAlarm(String time) {
    return 'Start and wake at $time';
  }

  @override
  String get sleepMonitorFinish => 'Finish and view result';

  @override
  String get sleepMonitorDiscard => 'Discard session';

  @override
  String get sleepMonitorLocalProcessing =>
      'Audio is processed locally and never recorded. Only aggregate metrics are kept.';

  @override
  String get sleepMonitorEstimateWarning =>
      'Results are environment-based estimates and are not medical measurements. Quiet does not necessarily mean you were asleep.';

  @override
  String get sleepMonitorMicrophoneDenied =>
      'Microphone permission is required to monitor this night.';

  @override
  String get sleepMonitorNotificationsLimited =>
      'Notifications are disabled; the service may be less visible while the screen is locked.';

  @override
  String get sleepMonitorAudioUnavailable =>
      'The microphone could not be accessed. Check whether another app is using it.';

  @override
  String get sleepMonitorAlreadyActive =>
      'A monitoring session is already active.';

  @override
  String get sleepMonitorImportError =>
      'The session could not be imported. It will be kept for another attempt.';

  @override
  String get sleepMonitorGenericError =>
      'The monitoring session could not be started or finished.';

  @override
  String get sleepMonitorWaitingSignal =>
      'Waiting for the first signal segment';

  @override
  String get sleepMonitorNoiseNow => 'Relative noise detected';

  @override
  String get sleepMonitorQuietNow => 'Estimated quiet period';

  @override
  String get sleepMonitorInvalidSignal => 'Signal temporarily unavailable';

  @override
  String get sleepAlarmSectionTitle => 'Your wake-up time';

  @override
  String get sleepAlarmTapToChange => 'Tap the clock to change';

  @override
  String get sleepAlarmNext => 'Next alarm';

  @override
  String sleepAlarmIn(String duration) {
    return 'in $duration';
  }

  @override
  String get sleepAlarmSystemSound => 'System alarm sound + vibration';

  @override
  String get sleepAlarmSystemSoundBody =>
      'Uses your device\'s alarm volume and Do Not Disturb settings.';

  @override
  String get sleepAlarmPreparation => 'Prepare your phone';

  @override
  String get sleepAlarmPreparationBody =>
      'Leave it charging near the bed, with the microphone unobstructed.';

  @override
  String sleepAlarmScheduledFor(String time) {
    return 'Alarm set for $time';
  }

  @override
  String get sleepAlarmRemaining => 'Time until alarm';

  @override
  String get sleepAlarmChange => 'Change alarm';

  @override
  String get sleepAlarmInvalidWindow =>
      'Choose a time between 1 minute and 16 hours from now.';

  @override
  String get sleepAlarmExactPermission =>
      'Allow Alarms & reminders so the alarm can ring exactly on time.';

  @override
  String get sleepAlarmEnableExactPermission => 'Allow exact alarms';

  @override
  String get sleepAlarmNotificationRequired =>
      'Notifications are required to show and dismiss the wake-up alarm.';

  @override
  String get sleepAlarmFullScreenLimited =>
      'Full-screen alarms are disabled. Sound and vibration will still use a highlighted notification.';

  @override
  String get sleepAlarmEnableFullScreen => 'Allow full-screen alarm';

  @override
  String get sleepAlarmScheduleFailed =>
      'The wake-up alarm could not be scheduled.';

  @override
  String get sleepMonitorResultTitle => 'Monitoring result';

  @override
  String get sleepMonitorResultMissing => 'Result not found.';

  @override
  String get sleepMonitorSource => 'Monitoring';

  @override
  String get sleepMonitorTimeline => 'Night timeline';

  @override
  String get sleepMonitorTimeMonitored => 'Time monitored';

  @override
  String get sleepMonitorQuietPeriod => 'Quiet period';

  @override
  String get sleepMonitorNoisyPeriod => 'Noisy period';

  @override
  String get sleepMonitorNoiseEvents => 'Noise events';

  @override
  String get sleepMonitorSignalCoverage => 'Signal coverage';

  @override
  String get sleepMonitorQuiet => 'Relative quiet';

  @override
  String get sleepMonitorNoise => 'Relative noise';

  @override
  String get sleepMonitorInvalid => 'Invalid signal';

  @override
  String get sleepMonitorDataQuality => 'MVP data quality';

  @override
  String get sleepMonitorDataAcceptable =>
      'Night suitable for the next MVP phase';

  @override
  String get sleepMonitorDataAcceptableBody =>
      'Duration and capture coverage are sufficient for evaluating the current monitor.';

  @override
  String get sleepMonitorDataInsufficient =>
      'Night needs another monitoring round';

  @override
  String get sleepMonitorDataInsufficientBody =>
      'For the next phase, record at least 4 hours with 90% timeline coverage and 80% valid signal.';

  @override
  String get sleepMonitorCapturedSegments => 'Captured segments';

  @override
  String get sleepMonitorTimelineCoverage => 'Timeline coverage';

  @override
  String get sleepMonitorNoiseGraph => 'Relative noise through the night';

  @override
  String get sleepMonitorNoiseScore => 'Noise score';

  @override
  String get sleepMonitorNoSegments => 'No signal segments were recorded';

  @override
  String get sleepMonitorNoSegmentsBody =>
      'This session cannot evaluate the MVP. The monitor will now stop with an error if the microphone stops returning data, instead of completing an empty night.';

  @override
  String get sleepMonitorAverageNoise => 'Average noise score';

  @override
  String get sleepMonitorPeakNoise => 'Peak noise score';

  @override
  String get sleepMonitorStartTime => 'Started';

  @override
  String get sleepMonitorEndTime => 'Finished';

  @override
  String get sleepMonitorThreshold => 'Noise threshold';

  @override
  String get sleepMonitorExportDiagnostic => 'Export diagnostic';

  @override
  String get sleepMonitorExportDiagnosticTitle => 'What should be included?';

  @override
  String get sleepMonitorExportDiagnosticBody =>
      'The JSON file can be shared for technical analysis. Raw audio is never stored and cannot be exported.';

  @override
  String get sleepMonitorExportTechnicalOnly =>
      'Technical data only (recommended)';

  @override
  String get sleepMonitorExportTechnicalOnlyBody =>
      'Uses relative times and excludes the sleep date, exact timestamps, local IDs and your note.';

  @override
  String get sleepMonitorExportWithPersonal => 'Include personal sleep data';

  @override
  String get sleepMonitorExportWithPersonalBody =>
      'Also includes exact date and time, local IDs, recorded durations and your personal sleep comment.';

  @override
  String get sleepMonitorExportConfirm => 'Generate and share';

  @override
  String get sleepMonitorExportSuccess =>
      'Diagnostic generated. Choose where to share or save it.';

  @override
  String get sleepMonitorExportError =>
      'The diagnostic file could not be generated.';

  @override
  String get sleepMonitorTimeInBed => 'Time in bed';

  @override
  String get sleepMonitorDeleteSession => 'Delete session';

  @override
  String get sleepMonitorDeleteSessionBody =>
      'The metrics and timeline for this session will be deleted. The sleep record remains.';

  @override
  String get sleepMonitorDiscardTitle => 'Discard session?';

  @override
  String get sleepMonitorDiscardBody =>
      'The active session and its metrics will be deleted.';

  @override
  String get sleepMonitorDigitalSilence => 'Digital silence';

  @override
  String get sleepInferenceTitle => 'Night analysis';

  @override
  String get sleepInferenceSleptAt => 'Fell asleep';

  @override
  String get sleepInferenceOnsetUnknown => 'Onset not identified';

  @override
  String get sleepInferencePreparation => 'Preparation';

  @override
  String get sleepInferenceSettling => 'Settling';

  @override
  String get sleepInferenceAwakenings => 'Woke up';

  @override
  String get sleepInferenceEstimatedSleep => 'Estimated sleep';

  @override
  String get sleepInferenceConfidence => 'Confidence';

  @override
  String get sleepInferenceConfidenceLow => 'low';

  @override
  String get sleepInferenceConfidenceMedium => 'medium';

  @override
  String get sleepInferenceInsufficient =>
      'This night\'s data is not sufficient to calculate sleep onset and awakenings safely.';

  @override
  String get sleepInferenceEventsTitle => 'Night events';

  @override
  String get sleepInferencePeak => 'peak';

  @override
  String get sleepInferenceEventTransient => 'Transient activity';

  @override
  String get sleepInferenceEventProlonged => 'Prolonged activity';

  @override
  String get sleepInferenceEventAwakening => 'Awakening';

  @override
  String get sleepInferenceEventFinalActivity =>
      'Activity before monitoring ended';

  @override
  String get sleepInferenceReasonShort =>
      'Short peak without enough duration to indicate an awakening.';

  @override
  String get sleepInferenceReasonSustained =>
      'Sustained sound activity without a quiet recovery that indicates an awakening.';

  @override
  String get sleepInferenceReasonAwakening =>
      'Sustained activity followed by a return to quiet.';

  @override
  String get sleepInferenceReasonFinal =>
      'Sustained activity during the final ten minutes.';

  @override
  String get sleepInferenceBlockerTooShort =>
      'Record at least four hours in a completed session.';

  @override
  String get sleepInferenceBlockerLowTimelineCoverage =>
      'Timeline coverage was below 90%.';

  @override
  String get sleepInferenceBlockerLowSignalCoverage =>
      'Valid signal coverage was below 80%.';

  @override
  String get sleepInferenceBlockerInvalidSegments =>
      'More than 20% of the period contains invalid signal.';

  @override
  String get sleepInferenceBlockerDigitalSilence =>
      'More than 20% of the period contains digital microphone silence.';

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
      'Adds fictional workouts, measurements, and sleep to test the app';

  @override
  String get settingsGenerateTitle => 'Generate Test Data?';

  @override
  String get settingsGenerateContent =>
      'This will add fictional workouts, body measurements, and sleep records from recent months to test charts and features.\n\nUse \"Delete All History\" to remove them later.';

  @override
  String get settingsGenerate => 'Generate';

  @override
  String settingsGenerateSuccess(Object count) {
    return '✅ $count workouts generated!';
  }

  @override
  String settingsGenerateSuccessDetailed(
    Object routines,
    Object sleep,
    Object workouts,
  ) {
    return '✅ $workouts workouts, $routines routines, and $sleep sleep nights generated!';
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
  String get settingsExportOptionsTitle => 'Export backup';

  @override
  String get settingsExportShareOption => 'Share file';

  @override
  String get settingsExportShareSubtitle => 'Open the system share sheet';

  @override
  String get settingsExportSaveOption => 'Save on device';

  @override
  String get settingsExportSaveSubtitle =>
      'Choose Downloads, Drive, or another location';

  @override
  String get settingsExportSaveDialogTitle => 'Save JSON backup';

  @override
  String settingsExportSaveSuccess(Object path) {
    return 'Backup saved successfully!\n$path';
  }

  @override
  String settingsExportSaveError(Object error) {
    return 'Could not save backup: $error';
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
  String get settingsImportLocalOption => 'Backups saved on this device';

  @override
  String get settingsImportPickFileOption => 'Select file from device';

  @override
  String get settingsImportPickFileSubtitle =>
      'Choose a .json backup from Downloads, Drive, or storage';

  @override
  String settingsImportPickerError(Object error) {
    return 'Could not open the file picker: $error';
  }

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
  String routinesEstimatedDuration(Object duration) {
    return 'Estimated time: $duration';
  }

  @override
  String get workoutEstimatedCalories => 'Estimated calories';

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
  String get exerciseFormSectionBasic => 'Basics';

  @override
  String get exerciseFormSectionDefaults => 'Defaults';

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
  String get activeWorkoutCurrent => 'Current';

  @override
  String get activeWorkoutLast => 'Last';

  @override
  String get activeWorkoutByMuscleGroup => 'By muscle group';

  @override
  String get workoutStatsDensity => 'Density';

  @override
  String get workoutStatsKgPerMin => 'kg/min';

  @override
  String get workoutStatsEvolution => 'Evolution';

  @override
  String get workoutStatsHighlights => 'Highlights';

  @override
  String get workoutStatsTopSet => 'Top set';

  @override
  String get workoutStatsHighestVolume => 'Highest volume';

  @override
  String get workoutStatsAverageRpe => 'Average RPE';

  @override
  String get workoutStatsVsSimilarWorkout => 'vs similar workout';

  @override
  String get workoutStatsMuscleVolume => 'Muscle volume';

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
  String get notificationRestTimerTitle => 'Rest';

  @override
  String get notificationRestCompleteTitle => 'Rest Complete';

  @override
  String get notificationRestCompleteBody =>
      'Rest time is over - time for the next set!';

  @override
  String get notificationWorkoutTimerTitle => 'Active workout';

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

  @override
  String get aiCoachSection => 'AI COACH';

  @override
  String get aiCoachEntry => 'AI Coach';

  @override
  String get aiCoachEntrySubtitle => 'Chat with a personal-trainer AI.';

  @override
  String get aiCoachConfigureEntry => 'Configure AI';

  @override
  String get aiCoachConfigureEntrySubtitle =>
      'Providers, model, system prompt.';

  @override
  String get aiChatTitle => 'AI Coach';

  @override
  String get aiChatInputHint => 'Ask your trainer something…';

  @override
  String get aiChatInputHintDisabled => 'Configure a provider to start';

  @override
  String get aiChatNewChat => 'New conversation';

  @override
  String get aiChatHistory => 'History';

  @override
  String get aiChatSettings => 'Settings';

  @override
  String get aiChatChooseProvider => 'Switch provider';

  @override
  String get aiChatRetry => 'Retry';

  @override
  String get aiChatCopy => 'Copy';

  @override
  String get aiChatCopied => 'Message copied';

  @override
  String get aiChatErrorGeneric => 'Something went wrong.';

  @override
  String get aiChatErrorTimeout => 'The AI took too long to respond.';

  @override
  String get aiChatErrorNoProvider => 'No AI provider configured.';

  @override
  String get aiChatErrorInvalidToken => 'Invalid or missing API token.';

  @override
  String get aiChatErrorMissingModel =>
      'Select a model in Settings → AI Coach.';

  @override
  String get aiChatErrorNotFound => 'Model or endpoint not found.';

  @override
  String get aiChatErrorInvalidResponse =>
      'The AI provider returned an invalid response.';

  @override
  String get aiChatErrorRequest =>
      'The request to the AI could not be completed.';

  @override
  String get aiChatErrorUserMessage => 'The user message could not be found.';

  @override
  String get aiChatProcessing => 'Processing…';

  @override
  String get aiChatWelcomeTitle => 'Hi! I\'m your AI Coach.';

  @override
  String get aiChatWelcomeSubtitle =>
      'Ask about your progress, request a workout analysis, or ask for progression suggestions.';

  @override
  String get aiChatSending => 'Sending…';

  @override
  String aiChatReading(Object count) {
    return 'Reading $count source(s)…';
  }

  @override
  String get aiChatFinalising => 'Finalising…';

  @override
  String aiChatActiveModel(Object model, Object provider) {
    return '$provider • $model';
  }

  @override
  String aiChatNoModel(Object provider) {
    return '$provider • (no model)';
  }

  @override
  String get aiToolApplied => 'Tool applied';

  @override
  String get aiToolNoContent => '(no content)';

  @override
  String get aiToolError => 'Error';

  @override
  String get aiToolUnknown => 'unknown';

  @override
  String get aiToolListRecentWorkouts => 'Listing recent workouts';

  @override
  String get aiToolGetWorkoutDetail => 'Loading workout details';

  @override
  String get aiToolListExercises => 'Searching exercises';

  @override
  String get aiToolGetExerciseHistory => 'Exercise history';

  @override
  String get aiToolGetExerciseRecords => 'Personal records';

  @override
  String get aiToolWeeklyVolume => 'Weekly volume';

  @override
  String get aiToolProgressTrend => 'Progress trend';

  @override
  String get aiToolListRoutines => 'Listing routines';

  @override
  String get aiToolGetRoutineDetail => 'Loading routine details';

  @override
  String get aiToolBodyMeasurements => 'Body measurements';

  @override
  String get aiToolCardioSummary => 'Cardio summary';

  @override
  String get aiToolListGoals => 'Active goals';

  @override
  String get aiToolGoalHistory => 'Goal history';

  @override
  String get aiToolProposeRoutineChange => 'Preparing routine proposal';

  @override
  String get aiChatPreparingProposal => 'Preparing routine preview…';

  @override
  String get aiChatApplyingProposal => 'Applying approved changes…';

  @override
  String get aiRoutineProposalCreate => 'New routine';

  @override
  String get aiRoutineProposalUpdate => 'Update routine';

  @override
  String get aiRoutineProposalAwaiting => 'Awaiting approval';

  @override
  String get aiRoutineProposalApplying => 'Applying';

  @override
  String get aiRoutineProposalApplied => 'Applied';

  @override
  String get aiRoutineProposalRejected => 'Rejected';

  @override
  String get aiRoutineProposalStale => 'Outdated';

  @override
  String get aiRoutineProposalFailed => 'Failed';

  @override
  String get aiRoutineProposalPreview =>
      'Review the changes before applying them.';

  @override
  String get aiRoutineProposalApprove => 'Approve and apply';

  @override
  String get aiRoutineProposalReject => 'Reject';

  @override
  String get aiRoutineProposalView => 'View routine';

  @override
  String get aiRoutineProposalDetails => 'View details';

  @override
  String get aiRoutineProposalHideDetails => 'Hide details';

  @override
  String get aiRoutineProposalAdded => 'Added';

  @override
  String get aiRoutineProposalRemoved => 'Removed';

  @override
  String get aiRoutineProposalChanges => 'Proposed changes';

  @override
  String aiRoutineProposalRemovalWarning(Object count) {
    return 'This proposal removes $count item(s).';
  }

  @override
  String get aiRoutineProposalConfirmTitle => 'Apply removals?';

  @override
  String aiRoutineProposalConfirmBody(Object count) {
    return '$count item(s) will be removed from the routine. This cannot be undone automatically.';
  }

  @override
  String get aiRoutineProposalConfirmApply => 'Apply changes';

  @override
  String get aiRoutineProposalStaleBody =>
      'The routine changed since this preview. Ask the AI to create a new proposal.';

  @override
  String get aiRoutineProposalRejectedBody => 'No changes were applied.';

  @override
  String get aiRoutineProposalAppliedBody =>
      'Changes were applied successfully.';

  @override
  String get aiRoutineProposalRetrySummary => 'Generate summary';

  @override
  String get aiProviderPickerTitle => 'Provider and model';

  @override
  String get aiProviderPickerSearch => 'Search model';

  @override
  String get aiHistoryTitle => 'Conversation history';

  @override
  String get aiHistoryEmpty => 'No conversations yet';

  @override
  String get aiHistoryEmptySubtitle =>
      'Start a new conversation in the AI Coach chat.';

  @override
  String get aiHistoryDeleteTitle => 'Delete conversation?';

  @override
  String aiHistoryDeleteBody(Object title) {
    return 'This cannot be undone. \"$title\" will be removed.';
  }

  @override
  String get aiHistoryPinned => 'Pinned';

  @override
  String get aiHistoryRecent => 'Recent';

  @override
  String get aiHistoryActions => 'Conversation actions';

  @override
  String get aiHistoryRename => 'Rename';

  @override
  String get aiHistoryPin => 'Pin';

  @override
  String get aiHistoryUnpin => 'Unpin';

  @override
  String get aiHistoryRenameTitle => 'Rename conversation';

  @override
  String get aiHistoryRenameLabel => 'Conversation name';

  @override
  String get aiHistoryRenameHint => 'Enter a name';

  @override
  String get aiHistoryRenameRequired => 'Enter a conversation name';

  @override
  String get aiHistoryActionError =>
      'Could not update the conversation. Try again.';

  @override
  String get aiHistoryYesterday => 'yesterday';

  @override
  String get aiCoachFabTooltip => 'Open AI Coach';

  @override
  String get aiCoachConfigureBeforeChat =>
      'Configure an AI provider before opening the chat.';

  @override
  String get aiSettingsTitle => 'AI Coach settings';

  @override
  String get aiSettingsFabTitle => 'Show AI Coach button';

  @override
  String get aiSettingsFabSubtitle =>
      'Display the AI Coach shortcut on app screens.';

  @override
  String get aiSettingsProvidersCard => 'Providers';

  @override
  String get aiSettingsProvidersHelp =>
      'Add any OpenAI-compatible endpoint (OpenAI, Ollama, OpenRouter, Groq, LM Studio…).';

  @override
  String get aiSettingsAddProvider => 'Add provider';

  @override
  String get aiSettingsNoProviders => 'No providers';

  @override
  String get aiSettingsNoProvidersSubtitle =>
      'Add a provider to start using the AI Coach.';

  @override
  String get aiSettingsActivate => 'Activate';

  @override
  String get aiSettingsEdit => 'Edit';

  @override
  String get aiSettingsRemove => 'Remove';

  @override
  String aiSettingsRemoveConfirmTitle(Object name) {
    return 'Remove $name?';
  }

  @override
  String get aiSettingsRemoveConfirmBody => 'The token will also be deleted.';

  @override
  String get aiSettingsBaseUrl => 'Base URL';

  @override
  String get aiSettingsModel => 'Model';

  @override
  String aiSettingsModelValue(Object model) {
    return 'Model: $model';
  }

  @override
  String get aiSettingsProviderName => 'Name';

  @override
  String get aiSettingsNameRequired => 'Enter a name.';

  @override
  String get aiSettingsBaseUrlRequired => 'Enter a base URL.';

  @override
  String get aiSettingsNoModelsEmpty => 'No models available';

  @override
  String get aiSettingsToken => 'API token';

  @override
  String get aiSettingsTokenHint => 'Leave empty to keep the current token';

  @override
  String get aiSettingsNameHint => 'OpenAI, Ollama local, OpenRouter…';

  @override
  String get aiSettingsBaseUrlHint => 'https://api.openai.com/v1';

  @override
  String get aiSettingsNewProvider => 'New provider';

  @override
  String get aiSettingsEditProvider => 'Edit provider';

  @override
  String get aiSettingsFetchModels => 'Fetch models';

  @override
  String aiSettingsNoModels(Object url) {
    return 'No models loaded. Tap \"Fetch models\" to list the available ones for $url.';
  }

  @override
  String get aiSettingsContextMode => 'Context mode';

  @override
  String get aiSettingsContextModeHelp =>
      'How much data is sent to the AI each turn. More context = better answers, more tokens.';

  @override
  String get aiSettingsContextModeMinimal => 'Minimal';

  @override
  String get aiSettingsContextModeMinimalSubtitle =>
      'Only totals and streak. AI uses tools for details.';

  @override
  String get aiSettingsContextModeStandard => 'Standard';

  @override
  String get aiSettingsContextModeStandardSubtitle =>
      'Summary + goals + top exercises. Good balance.';

  @override
  String get aiSettingsContextModeFull => 'Full';

  @override
  String get aiSettingsContextModeFullSubtitle =>
      'Everything: categories, body trend, detailed volume.';

  @override
  String get aiSettingsSystemPrompt => 'System prompt';

  @override
  String get aiSettingsSystemPromptHelp =>
      'Defines the personality and behaviour of the AI Coach.';

  @override
  String get aiSettingsRestoreDefault => 'Restore default';

  @override
  String get aiSettingsSaved => 'Saved';

  @override
  String get aiSettingsAbout => 'About';

  @override
  String get aiSettingsAboutBody =>
      'The AI Coach sends a summary of your data each turn and has access to 13 read tools. It cannot edit your data. Conversations are stored locally.';

  @override
  String get sleepSettingsTitle => 'Sleep settings';

  @override
  String get sleepSettingsGoalSection => 'SLEEP GOAL';

  @override
  String get sleepSettingsMissionSection => 'ALARM MISSION';

  @override
  String get sleepMissionToggle => 'Barcode mission';

  @override
  String get sleepMissionToggleBody =>
      'A protected alarm requires a mission when you choose that mode.';

  @override
  String get sleepMissionNotConfigured => 'No barcode registered';

  @override
  String sleepMissionConfigured(String format) {
    return 'Registered code: $format';
  }

  @override
  String get sleepMissionScan => 'Scan code';

  @override
  String get sleepMissionReplace => 'Replace code';

  @override
  String get sleepMissionRemove => 'Remove code';

  @override
  String get sleepMissionRemoveConfirm =>
      'Remove the registered code? Protected alarms already started will not change.';

  @override
  String get sleepMissionScanError => 'The barcode could not be read.';

  @override
  String get sleepMissionCameraDenied =>
      'Camera permission is required to read the mission.';

  @override
  String get sleepMonitorModeSection => 'HOW TO MONITOR';

  @override
  String get sleepMonitorModeAlarmNoMission =>
      'Monitor + alarm without mission';

  @override
  String get sleepMonitorModeAlarmWithMission => 'Monitor + alarm with mission';

  @override
  String get sleepMonitorModeOnly => 'Monitor only, without alarm';

  @override
  String get sleepMonitorModeAlarmNoMissionBody =>
      'The alarm rings at the selected time and can be dismissed normally.';

  @override
  String get sleepMonitorModeAlarmWithMissionBody =>
      'To dismiss it, scan the registered code or complete the emergency action with 500 taps.';

  @override
  String get sleepMonitorModeOnlyBody =>
      'Monitors the environment without scheduling an alarm.';

  @override
  String get sleepMonitorModeMissionUnavailable =>
      'Configure a barcode mission to unlock this mode.';

  @override
  String get sleepMonitorStartOnly => 'Start monitoring only';

  @override
  String sleepMonitorStartWithMission(String time) {
    return 'Start and wake at $time with mission';
  }

  @override
  String get sleepMonitorProtectedStop => 'Stop monitoring only';

  @override
  String get sleepMonitorProtectedStopBody =>
      'The alarm and mission will remain active for this time.';

  @override
  String get sleepMonitorMissionPending => 'Mission pending';

  @override
  String get sleepMonitorMissionReady => 'Mission configured';

  @override
  String get sleepMissionFormatUnknown => 'barcode';

  @override
  String get sleepMissionRemoved => 'Mission removed for new sessions.';

  @override
  String get sleepMissionSaved => 'Code registered successfully.';

  @override
  String get sleepMissionOpenSettings => 'Open camera settings';

  @override
  String get alarmTitle => 'Alarms';

  @override
  String get alarmNew => 'New alarm';

  @override
  String get alarmEdit => 'Edit alarm';

  @override
  String get alarmEmptyTitle => 'No alarms';

  @override
  String get alarmEmptyBody => 'Create an alarm to wake up at the right time.';

  @override
  String get alarmDeleteTitle => 'Delete alarm?';

  @override
  String get alarmDeleteBody => 'This alarm will stop ringing.';

  @override
  String get alarmDelete => 'Delete';

  @override
  String get alarmPermissionRequired =>
      'Allow notifications and exact alarms to continue.';

  @override
  String get alarmUpdateError => 'Could not update the alarm.';

  @override
  String get alarmSaveError => 'Could not save the alarm.';

  @override
  String alarmNext(String time) {
    return 'Next: $time';
  }

  @override
  String get alarmMission => 'Mission';

  @override
  String alarmSnoozeChip(int minutes, int count) {
    return '$minutes min • ${count}x';
  }

  @override
  String get alarmOneShot => 'Once';

  @override
  String get alarmEveryDay => 'Every day';

  @override
  String get alarmRepeat => 'Repeat';

  @override
  String get alarmOneShotHelp => 'No days selected: this alarm will ring once.';

  @override
  String get alarmDaysHelp => 'Choose the days when this alarm should ring.';

  @override
  String get alarmSnoozeEnable => 'Allow snooze';

  @override
  String get alarmSnoozeEnableBody => 'Delay the alarm before dismissing it.';

  @override
  String get alarmSnoozeInterval => 'Snooze interval';

  @override
  String get alarmMaxSnoozes => 'Maximum snoozes';

  @override
  String get alarmNoSnoozes => 'Do not allow';

  @override
  String alarmSnoozeTimes(int count) {
    return '$count time(s)';
  }

  @override
  String get alarmRequireMission => 'Require a mission to dismiss';

  @override
  String get alarmRequireMissionBody =>
      'Requires the barcode configured in sleep monitoring.';

  @override
  String get alarmMissionNotConfigured =>
      'Set up a barcode mission in Sleep settings before using it.';

  @override
  String get alarmSaving => 'Saving…';

  @override
  String get alarmSave => 'Save alarm';

  @override
  String get alarmWeekMon => 'Mon';

  @override
  String get alarmWeekTue => 'Tue';

  @override
  String get alarmWeekWed => 'Wed';

  @override
  String get alarmWeekThu => 'Thu';

  @override
  String get alarmWeekFri => 'Fri';

  @override
  String get alarmWeekSat => 'Sat';

  @override
  String get alarmWeekSun => 'Sun';

  @override
  String get sleepSettingsAlarmsSection => 'ALARMS';

  @override
  String get sleepSettingsSnoozeToggle => 'Allow snoozes';

  @override
  String get sleepSettingsSnoozeToggleBody =>
      'Controls snoozes in sleep monitoring and the default for new alarms.';

  @override
  String get sleepSettingsMaxSnoozesBody =>
      'Sleep monitoring always uses this limit. Each traditional alarm can set its own limit.';

  @override
  String get sleepSettingsMaxSnoozesDialogBody =>
      'This limit is used by sleep monitoring and as the default for new alarms.';

  @override
  String get sleepSettingsAllowedSnoozes => 'Allowed snoozes';

  @override
  String get sleepMonitorSnoozesTitle => 'Alarm snoozes';

  @override
  String get sleepMonitorSnoozesDisabled => 'Disabled in Sleep settings.';

  @override
  String sleepMonitorSnoozesConfigured(int count) {
    return 'Up to $count snooze(s), according to Sleep settings.';
  }

  @override
  String get aiEmptyTitle => 'Configure an AI provider';

  @override
  String get aiEmptySubtitle =>
      'Add an OpenAI-compatible endpoint (OpenAI, Ollama, OpenRouter…) to start using the AI Coach.';

  @override
  String get aiEmptyConfigure => 'Configure provider';
}
