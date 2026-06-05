import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout Notes'**
  String get appTitle;

  /// No description provided for @tabWorkout.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get tabWorkout;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get commonDiscard;

  /// No description provided for @commonKeepEditing.
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get commonKeepEditing;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String commonError(Object error);

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get commonAll;

  /// No description provided for @commonExercises.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get commonExercises;

  /// No description provided for @commonVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get commonVolume;

  /// No description provided for @commonSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get commonSets;

  /// No description provided for @commonReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get commonReps;

  /// No description provided for @commonCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get commonCompleted;

  /// No description provided for @commonInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get commonInProgress;

  /// No description provided for @commonConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Are you sure?'**
  String get commonConfirmDelete;

  /// No description provided for @commonActionCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get commonActionCannotBeUndone;

  /// No description provided for @accentColorRed.
  ///
  /// In en, this message translates to:
  /// **'Deep Red'**
  String get accentColorRed;

  /// No description provided for @accentColorDarkOrange.
  ///
  /// In en, this message translates to:
  /// **'Dark Orange'**
  String get accentColorDarkOrange;

  /// No description provided for @accentColorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get accentColorOrange;

  /// No description provided for @accentColorAmber.
  ///
  /// In en, this message translates to:
  /// **'Amber'**
  String get accentColorAmber;

  /// No description provided for @accentColorDeepPurple.
  ///
  /// In en, this message translates to:
  /// **'Deep Purple'**
  String get accentColorDeepPurple;

  /// No description provided for @accentColorDarkBlue.
  ///
  /// In en, this message translates to:
  /// **'Dark Blue'**
  String get accentColorDarkBlue;

  /// No description provided for @accentColorGraphite.
  ///
  /// In en, this message translates to:
  /// **'Graphite'**
  String get accentColorGraphite;

  /// No description provided for @accentColorForestGreen.
  ///
  /// In en, this message translates to:
  /// **'Forest Green'**
  String get accentColorForestGreen;

  /// No description provided for @workoutHomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get workoutHomeTitle;

  /// No description provided for @workoutHomeHistoryTooltip.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get workoutHomeHistoryTooltip;

  /// No description provided for @workoutHomeSettingsTooltip.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get workoutHomeSettingsTooltip;

  /// No description provided for @workoutHomeMonthWorkouts.
  ///
  /// In en, this message translates to:
  /// **'Workouts this Month'**
  String get workoutHomeMonthWorkouts;

  /// No description provided for @workoutHomeVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get workoutHomeVolume;

  /// No description provided for @workoutHomeStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get workoutHomeStreak;

  /// No description provided for @workoutHomeDay.
  ///
  /// In en, this message translates to:
  /// **'day'**
  String get workoutHomeDay;

  /// No description provided for @workoutHomeDays.
  ///
  /// In en, this message translates to:
  /// **'days'**
  String get workoutHomeDays;

  /// No description provided for @workoutHomeNewWorkout.
  ///
  /// In en, this message translates to:
  /// **'New Workout'**
  String get workoutHomeNewWorkout;

  /// No description provided for @workoutHomeStartNow.
  ///
  /// In en, this message translates to:
  /// **'Start now'**
  String get workoutHomeStartNow;

  /// No description provided for @workoutHomeQuickAdd.
  ///
  /// In en, this message translates to:
  /// **'Quick Add'**
  String get workoutHomeQuickAdd;

  /// No description provided for @workoutHomeQuickAddSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Quick add'**
  String get workoutHomeQuickAddSubtitle;

  /// No description provided for @workoutHomeNavigation.
  ///
  /// In en, this message translates to:
  /// **'NAVIGATION'**
  String get workoutHomeNavigation;

  /// No description provided for @workoutHomeExercises.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get workoutHomeExercises;

  /// No description provided for @workoutHomeRoutines.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get workoutHomeRoutines;

  /// No description provided for @workoutHomeProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get workoutHomeProgress;

  /// No description provided for @workoutHomeBodyMeasurements.
  ///
  /// In en, this message translates to:
  /// **'Measurements'**
  String get workoutHomeBodyMeasurements;

  /// No description provided for @workoutHomeInProgress.
  ///
  /// In en, this message translates to:
  /// **'IN PROGRESS'**
  String get workoutHomeInProgress;

  /// No description provided for @workoutHomeNoActiveWorkout.
  ///
  /// In en, this message translates to:
  /// **'No workout in progress'**
  String get workoutHomeNoActiveWorkout;

  /// No description provided for @workoutHomeUpcoming.
  ///
  /// In en, this message translates to:
  /// **'UPCOMING WORKOUTS'**
  String get workoutHomeUpcoming;

  /// No description provided for @workoutHomeCompleted.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED WORKOUTS'**
  String get workoutHomeCompleted;

  /// No description provided for @workoutHomeOngoing.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get workoutHomeOngoing;

  /// No description provided for @workoutHomeContinueWorkout.
  ///
  /// In en, this message translates to:
  /// **'Continue Workout'**
  String get workoutHomeContinueWorkout;

  /// No description provided for @workoutHomeDeleteWorkout.
  ///
  /// In en, this message translates to:
  /// **'Delete Workout'**
  String get workoutHomeDeleteWorkout;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsThemeColor.
  ///
  /// In en, this message translates to:
  /// **'Theme Color'**
  String get settingsThemeColor;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// No description provided for @settingsSystemSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Follow device setting'**
  String get settingsSystemSubtitle;

  /// No description provided for @settingsLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsLight;

  /// No description provided for @settingsLightSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Force light mode'**
  String get settingsLightSubtitle;

  /// No description provided for @settingsDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsDark;

  /// No description provided for @settingsDarkSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Force dark mode'**
  String get settingsDarkSubtitle;

  /// No description provided for @settingsUnits.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get settingsUnits;

  /// No description provided for @settingsUnitSystem.
  ///
  /// In en, this message translates to:
  /// **'Unit System'**
  String get settingsUnitSystem;

  /// No description provided for @settingsUnitKgCm.
  ///
  /// In en, this message translates to:
  /// **'kg / cm'**
  String get settingsUnitKgCm;

  /// No description provided for @settingsUnitLbsIn.
  ///
  /// In en, this message translates to:
  /// **'lbs / in'**
  String get settingsUnitLbsIn;

  /// No description provided for @settingsTimer.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get settingsTimer;

  /// No description provided for @settingsDefaultRest.
  ///
  /// In en, this message translates to:
  /// **'Default Rest'**
  String get settingsDefaultRest;

  /// No description provided for @settingsSeconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get settingsSeconds;

  /// No description provided for @settingsAutoStartRest.
  ///
  /// In en, this message translates to:
  /// **'Auto-start Rest Timer'**
  String get settingsAutoStartRest;

  /// No description provided for @settingsAutoStartRestSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start automatically after each set'**
  String get settingsAutoStartRestSubtitle;

  /// No description provided for @settingsAutoStartWorkoutTimer.
  ///
  /// In en, this message translates to:
  /// **'Auto-start Workout Timer'**
  String get settingsAutoStartWorkoutTimer;

  /// No description provided for @settingsAutoStartWorkoutTimerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start timer after 1st set, stop after last set'**
  String get settingsAutoStartWorkoutTimerSubtitle;

  /// No description provided for @settingsNotifications.
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// No description provided for @settingsRestTimerNotif.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer'**
  String get settingsRestTimerNotif;

  /// No description provided for @settingsRestTimerNotifSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Notification between sets'**
  String get settingsRestTimerNotifSubtitle;

  /// No description provided for @settingsWorkoutTimerNotif.
  ///
  /// In en, this message translates to:
  /// **'Workout Timer'**
  String get settingsWorkoutTimerNotif;

  /// No description provided for @settingsWorkoutTimerNotifSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Active workout notification'**
  String get settingsWorkoutTimerNotifSubtitle;

  /// No description provided for @settingsAlertOptions.
  ///
  /// In en, this message translates to:
  /// **'Alert options'**
  String get settingsAlertOptions;

  /// No description provided for @settingsSound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get settingsSound;

  /// No description provided for @settingsRestSoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play sound when rest starts and ends'**
  String get settingsRestSoundSubtitle;

  /// No description provided for @settingsWorkoutSoundSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play sound when workout starts'**
  String get settingsWorkoutSoundSubtitle;

  /// No description provided for @settingsVibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get settingsVibration;

  /// No description provided for @settingsRestVibrationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate when rest starts and ends'**
  String get settingsRestVibrationSubtitle;

  /// No description provided for @settingsWorkoutVibrationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate when workout starts'**
  String get settingsWorkoutVibrationSubtitle;

  /// No description provided for @settingsDisplay.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settingsDisplay;

  /// No description provided for @settingsKeepScreenOn.
  ///
  /// In en, this message translates to:
  /// **'Keep Screen On'**
  String get settingsKeepScreenOn;

  /// No description provided for @settingsKeepScreenOnSubtitle.
  ///
  /// In en, this message translates to:
  /// **'During workout'**
  String get settingsKeepScreenOnSubtitle;

  /// No description provided for @settingsData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsData;

  /// No description provided for @settingsExportBackup.
  ///
  /// In en, this message translates to:
  /// **'Export Backup'**
  String get settingsExportBackup;

  /// No description provided for @settingsExportBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Full JSON backup to save or transfer'**
  String get settingsExportBackupSubtitle;

  /// No description provided for @settingsGenerateTestData.
  ///
  /// In en, this message translates to:
  /// **'Generate Test Data'**
  String get settingsGenerateTestData;

  /// No description provided for @settingsGenerateTestDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adds fictional workouts to test the app'**
  String get settingsGenerateTestDataSubtitle;

  /// No description provided for @settingsGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate Test Data?'**
  String get settingsGenerateTitle;

  /// No description provided for @settingsGenerateContent.
  ///
  /// In en, this message translates to:
  /// **'This will add fictional workouts from recent months to test charts and features.\n\nUse \"Delete All History\" to remove them later.'**
  String get settingsGenerateContent;

  /// No description provided for @settingsGenerate.
  ///
  /// In en, this message translates to:
  /// **'Generate'**
  String get settingsGenerate;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @settingsAboutSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Workout Notes v1.0'**
  String get settingsAboutSubtitle;

  /// No description provided for @settingsDeleteAllHistory.
  ///
  /// In en, this message translates to:
  /// **'Delete All Workout History'**
  String get settingsDeleteAllHistory;

  /// No description provided for @settingsDeleteHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete All History?'**
  String get settingsDeleteHistoryTitle;

  /// No description provided for @settingsDeleteHistoryContent.
  ///
  /// In en, this message translates to:
  /// **'All workouts, sets and registered exercises will be deleted. This action cannot be undone.'**
  String get settingsDeleteHistoryContent;

  /// No description provided for @settingsDeleteEverything.
  ///
  /// In en, this message translates to:
  /// **'Delete Everything'**
  String get settingsDeleteEverything;

  /// No description provided for @settingsDeleteHistorySuccess.
  ///
  /// In en, this message translates to:
  /// **'History deleted'**
  String get settingsDeleteHistorySuccess;

  /// No description provided for @settingsExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'✅ Backup exported!'**
  String get settingsExportSuccess;

  /// No description provided for @settingsExportError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String settingsExportError(Object error);

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsEnglish.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsEnglish;

  /// No description provided for @settingsPortuguese.
  ///
  /// In en, this message translates to:
  /// **'Português (Brasil)'**
  String get settingsPortuguese;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'App interface language'**
  String get settingsLanguageSubtitle;

  /// No description provided for @calendarTitle.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get calendarTitle;

  /// No description provided for @calendarSun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get calendarSun;

  /// No description provided for @calendarMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get calendarMon;

  /// No description provided for @calendarTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get calendarTue;

  /// No description provided for @calendarWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get calendarWed;

  /// No description provided for @calendarThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get calendarThu;

  /// No description provided for @calendarFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get calendarFri;

  /// No description provided for @calendarSat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get calendarSat;

  /// No description provided for @calendarNoWorkouts.
  ///
  /// In en, this message translates to:
  /// **'No workouts on {date}'**
  String calendarNoWorkouts(Object date);

  /// No description provided for @calendarCreateWorkout.
  ///
  /// In en, this message translates to:
  /// **'Create Workout'**
  String get calendarCreateWorkout;

  /// No description provided for @calendarNoTime.
  ///
  /// In en, this message translates to:
  /// **'No time'**
  String get calendarNoTime;

  /// No description provided for @calendarInProgress.
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get calendarInProgress;

  /// No description provided for @calendarWorkoutCreated.
  ///
  /// In en, this message translates to:
  /// **'✅ Workout created for this day!'**
  String get calendarWorkoutCreated;

  /// No description provided for @calendarSelectNewDate.
  ///
  /// In en, this message translates to:
  /// **'Select the new date'**
  String get calendarSelectNewDate;

  /// No description provided for @exportTitle.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportTitle;

  /// No description provided for @exportJsonBackup.
  ///
  /// In en, this message translates to:
  /// **'Full Backup (JSON)'**
  String get exportJsonBackup;

  /// No description provided for @exportJsonBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exports all data: workouts, exercises, routines, measurements and settings'**
  String get exportJsonBackupSubtitle;

  /// No description provided for @exportCsv.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsv;

  /// No description provided for @exportCsvSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Exports workout history (date, exercise, weight, reps) - filterable by exercise and date'**
  String get exportCsvSubtitle;

  /// No description provided for @exportShareSummary.
  ///
  /// In en, this message translates to:
  /// **'Share Summary'**
  String get exportShareSummary;

  /// No description provided for @exportShareSummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Generates a text summary of a specific workout to share'**
  String get exportShareSummarySubtitle;

  /// No description provided for @exportTips.
  ///
  /// In en, this message translates to:
  /// **'Tips'**
  String get exportTips;

  /// No description provided for @exportTipsContent.
  ///
  /// In en, this message translates to:
  /// **'• JSON backup contains all app data\n• CSV is ideal for analysis in Excel/Google Sheets\n• Files are saved temporarily and shared via native share sheet'**
  String get exportTipsContent;

  /// No description provided for @exportCsvDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsvDialogTitle;

  /// No description provided for @exportCsvExerciseLabel.
  ///
  /// In en, this message translates to:
  /// **'Exercise (optional - empty exports all)'**
  String get exportCsvExerciseLabel;

  /// No description provided for @exportCsvExerciseHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for all'**
  String get exportCsvExerciseHint;

  /// No description provided for @exportCsvStartDate.
  ///
  /// In en, this message translates to:
  /// **'Start date'**
  String get exportCsvStartDate;

  /// No description provided for @exportCsvEndDate.
  ///
  /// In en, this message translates to:
  /// **'End date'**
  String get exportCsvEndDate;

  /// No description provided for @exportCsvButton.
  ///
  /// In en, this message translates to:
  /// **'Export CSV'**
  String get exportCsvButton;

  /// No description provided for @exportShareWorkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Workout'**
  String get exportShareWorkoutTitle;

  /// No description provided for @exportNoWorkouts.
  ///
  /// In en, this message translates to:
  /// **'No workouts to share'**
  String get exportNoWorkouts;

  /// No description provided for @exportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup exported successfully!'**
  String get exportSuccess;

  /// No description provided for @exportCsvSuccess.
  ///
  /// In en, this message translates to:
  /// **'CSV exported successfully!'**
  String get exportCsvSuccess;

  /// No description provided for @exportError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String exportError(Object error);

  /// No description provided for @progressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressTitle;

  /// No description provided for @progressMonthlyReport.
  ///
  /// In en, this message translates to:
  /// **'MONTHLY REPORT OF {month}'**
  String progressMonthlyReport(Object month);

  /// No description provided for @progressWorkouts.
  ///
  /// In en, this message translates to:
  /// **'Workouts'**
  String get progressWorkouts;

  /// No description provided for @progressSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get progressSets;

  /// No description provided for @progressDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get progressDays;

  /// No description provided for @progressAverageFeeling.
  ///
  /// In en, this message translates to:
  /// **'Average feeling: {rating} ★'**
  String progressAverageFeeling(Object rating);

  /// No description provided for @progressVsLastMonth.
  ///
  /// In en, this message translates to:
  /// **'{delta} vs last month'**
  String progressVsLastMonth(Object delta);

  /// No description provided for @progressStreak.
  ///
  /// In en, this message translates to:
  /// **'Streak'**
  String get progressStreak;

  /// No description provided for @progressFrequency.
  ///
  /// In en, this message translates to:
  /// **'Frequency & Consistency'**
  String get progressFrequency;

  /// No description provided for @progressVolumeGroups.
  ///
  /// In en, this message translates to:
  /// **'Volume & Muscle Groups'**
  String get progressVolumeGroups;

  /// No description provided for @progressExerciseHistory.
  ///
  /// In en, this message translates to:
  /// **'Exercise History'**
  String get progressExerciseHistory;

  /// No description provided for @progressDurationEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Duration & Efficiency'**
  String get progressDurationEfficiency;

  /// No description provided for @progressRecovery.
  ///
  /// In en, this message translates to:
  /// **'Recovery & Well-being'**
  String get progressRecovery;

  /// No description provided for @progressBodyMeasurements.
  ///
  /// In en, this message translates to:
  /// **'Body Measurements'**
  String get progressBodyMeasurements;

  /// No description provided for @progressYearHeatmap.
  ///
  /// In en, this message translates to:
  /// **'Annual heatmap'**
  String get progressYearHeatmap;

  /// No description provided for @progressWeeklyFrequency.
  ///
  /// In en, this message translates to:
  /// **'Weekly frequency (last 12 weeks)'**
  String get progressWeeklyFrequency;

  /// No description provided for @progressDayOfWeek.
  ///
  /// In en, this message translates to:
  /// **'Day of week'**
  String get progressDayOfWeek;

  /// No description provided for @progressTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get progressTimeOfDay;

  /// No description provided for @progressMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get progressMorning;

  /// No description provided for @progressAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get progressAfternoon;

  /// No description provided for @progressEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get progressEvening;

  /// No description provided for @progressDawn.
  ///
  /// In en, this message translates to:
  /// **'Dawn'**
  String get progressDawn;

  /// No description provided for @progressNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get progressNoData;

  /// No description provided for @progressVolumeByGroup.
  ///
  /// In en, this message translates to:
  /// **'Volume by Group'**
  String get progressVolumeByGroup;

  /// No description provided for @progressEnergySystem.
  ///
  /// In en, this message translates to:
  /// **'Energy System'**
  String get progressEnergySystem;

  /// No description provided for @progressAerobic.
  ///
  /// In en, this message translates to:
  /// **'Aerobic'**
  String get progressAerobic;

  /// No description provided for @progressAnaerobic.
  ///
  /// In en, this message translates to:
  /// **'Anaerobic'**
  String get progressAnaerobic;

  /// No description provided for @progressTopExercises.
  ///
  /// In en, this message translates to:
  /// **'Top Exercises by Volume'**
  String get progressTopExercises;

  /// No description provided for @progressNoExercises.
  ///
  /// In en, this message translates to:
  /// **'No exercises registered'**
  String get progressNoExercises;

  /// No description provided for @progressTapForHistory.
  ///
  /// In en, this message translates to:
  /// **'Tap an exercise to view full history'**
  String get progressTapForHistory;

  /// No description provided for @progressDuration.
  ///
  /// In en, this message translates to:
  /// **'Workout Duration'**
  String get progressDuration;

  /// No description provided for @progressAverage.
  ///
  /// In en, this message translates to:
  /// **'Average: {avg}min'**
  String progressAverage(Object avg);

  /// No description provided for @progressDensity.
  ///
  /// In en, this message translates to:
  /// **'Density (Volume per Minute)'**
  String get progressDensity;

  /// No description provided for @progressBodyWeight.
  ///
  /// In en, this message translates to:
  /// **'Body Weight'**
  String get progressBodyWeight;

  /// No description provided for @bodyTrackerTitle.
  ///
  /// In en, this message translates to:
  /// **'Body Measurements'**
  String get bodyTrackerTitle;

  /// No description provided for @bodyTrackerWeight.
  ///
  /// In en, this message translates to:
  /// **'Body Weight'**
  String get bodyTrackerWeight;

  /// No description provided for @bodyTrackerBodyFat.
  ///
  /// In en, this message translates to:
  /// **'% Body Fat'**
  String get bodyTrackerBodyFat;

  /// No description provided for @bodyTrackerWaist.
  ///
  /// In en, this message translates to:
  /// **'Waist'**
  String get bodyTrackerWaist;

  /// No description provided for @bodyTrackerChest.
  ///
  /// In en, this message translates to:
  /// **'Chest'**
  String get bodyTrackerChest;

  /// No description provided for @bodyTrackerArm.
  ///
  /// In en, this message translates to:
  /// **'Arm'**
  String get bodyTrackerArm;

  /// No description provided for @bodyTrackerThigh.
  ///
  /// In en, this message translates to:
  /// **'Thigh'**
  String get bodyTrackerThigh;

  /// No description provided for @bodyTrackerHip.
  ///
  /// In en, this message translates to:
  /// **'Hip'**
  String get bodyTrackerHip;

  /// No description provided for @bodyTrackerAdd.
  ///
  /// In en, this message translates to:
  /// **'Add Measurement'**
  String get bodyTrackerAdd;

  /// No description provided for @bodyTrackerAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Add {type}'**
  String bodyTrackerAddTitle(Object type);

  /// No description provided for @bodyTrackerValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get bodyTrackerValue;

  /// No description provided for @bodyTrackerDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get bodyTrackerDate;

  /// No description provided for @bodyTrackerComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get bodyTrackerComment;

  /// No description provided for @bodyTrackerSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bodyTrackerSave;

  /// No description provided for @bodyTrackerSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ Measurement saved!'**
  String get bodyTrackerSaved;

  /// No description provided for @bodyTrackerDeleted.
  ///
  /// In en, this message translates to:
  /// **'Measurement deleted'**
  String get bodyTrackerDeleted;

  /// No description provided for @bodyTrackerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this measurement?'**
  String get bodyTrackerDeleteConfirm;

  /// No description provided for @routinesTitle.
  ///
  /// In en, this message translates to:
  /// **'Routines'**
  String get routinesTitle;

  /// No description provided for @routinesNew.
  ///
  /// In en, this message translates to:
  /// **'New Routine'**
  String get routinesNew;

  /// No description provided for @routinesName.
  ///
  /// In en, this message translates to:
  /// **'Routine Name'**
  String get routinesName;

  /// No description provided for @routinesNameHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Push Pull Legs'**
  String get routinesNameHint;

  /// No description provided for @routinesCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get routinesCreate;

  /// No description provided for @routinesEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Routine'**
  String get routinesEdit;

  /// No description provided for @routinesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Routine'**
  String get routinesDelete;

  /// No description provided for @routinesDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{name}\"?'**
  String routinesDeleteConfirm(Object name);

  /// No description provided for @routinesDeleteContent.
  ///
  /// In en, this message translates to:
  /// **'All routine data will be lost.'**
  String get routinesDeleteContent;

  /// No description provided for @restTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer'**
  String get restTimerTitle;

  /// No description provided for @restTimerStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get restTimerStop;

  /// No description provided for @restTimerComplete.
  ///
  /// In en, this message translates to:
  /// **'COMPLETED'**
  String get restTimerComplete;

  /// No description provided for @restTimerPaused.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get restTimerPaused;

  /// No description provided for @restTimerResting.
  ///
  /// In en, this message translates to:
  /// **'RESTING'**
  String get restTimerResting;

  /// No description provided for @restTimerReady.
  ///
  /// In en, this message translates to:
  /// **'READY'**
  String get restTimerReady;

  /// No description provided for @restTimerResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get restTimerResume;

  /// No description provided for @restTimerPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get restTimerPause;

  /// No description provided for @restTimerStartRest.
  ///
  /// In en, this message translates to:
  /// **'Start rest'**
  String get restTimerStartRest;

  /// No description provided for @exerciseLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Exercises'**
  String get exerciseLibraryTitle;

  /// No description provided for @exerciseLibraryFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get exerciseLibraryFavorites;

  /// No description provided for @exerciseLibrarySearch.
  ///
  /// In en, this message translates to:
  /// **'Search exercise...'**
  String get exerciseLibrarySearch;

  /// No description provided for @exerciseLibraryAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get exerciseLibraryAll;

  /// No description provided for @exerciseLibraryNoResults.
  ///
  /// In en, this message translates to:
  /// **'No exercises found'**
  String get exerciseLibraryNoResults;

  /// No description provided for @exerciseLibraryNoResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Try a different search or add a new one'**
  String get exerciseLibraryNoResultsHint;

  /// No description provided for @exerciseLibraryNew.
  ///
  /// In en, this message translates to:
  /// **'New Exercise'**
  String get exerciseLibraryNew;

  /// No description provided for @exerciseLibraryAerobic.
  ///
  /// In en, this message translates to:
  /// **'Aerobic'**
  String get exerciseLibraryAerobic;

  /// No description provided for @exerciseLibraryAnaerobic.
  ///
  /// In en, this message translates to:
  /// **'Anaerobic'**
  String get exerciseLibraryAnaerobic;

  /// No description provided for @exerciseFormTitleNew.
  ///
  /// In en, this message translates to:
  /// **'New Exercise'**
  String get exerciseFormTitleNew;

  /// No description provided for @exerciseFormTitleEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Exercise'**
  String get exerciseFormTitleEdit;

  /// No description provided for @exerciseFormName.
  ///
  /// In en, this message translates to:
  /// **'Exercise Name'**
  String get exerciseFormName;

  /// No description provided for @exerciseFormNameHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Incline Bench Press'**
  String get exerciseFormNameHint;

  /// No description provided for @exerciseFormCategory.
  ///
  /// In en, this message translates to:
  /// **'Muscle Group'**
  String get exerciseFormCategory;

  /// No description provided for @exerciseFormType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get exerciseFormType;

  /// No description provided for @exerciseFormEquipment.
  ///
  /// In en, this message translates to:
  /// **'Equipment (optional)'**
  String get exerciseFormEquipment;

  /// No description provided for @exerciseFormEquipmentHint.
  ///
  /// In en, this message translates to:
  /// **'Barbell, Dumbbell, Machine...'**
  String get exerciseFormEquipmentHint;

  /// No description provided for @exerciseFormWeightIncrement.
  ///
  /// In en, this message translates to:
  /// **'Weight Increment (kg)'**
  String get exerciseFormWeightIncrement;

  /// No description provided for @exerciseFormWeightIncrementHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: 2.5'**
  String get exerciseFormWeightIncrementHint;

  /// No description provided for @exerciseFormDefaultRest.
  ///
  /// In en, this message translates to:
  /// **'Default Rest (seconds)'**
  String get exerciseFormDefaultRest;

  /// No description provided for @exerciseFormDefaultRestHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: 90'**
  String get exerciseFormDefaultRestHint;

  /// No description provided for @exerciseFormNotes.
  ///
  /// In en, this message translates to:
  /// **'Instructions / Tips (optional)'**
  String get exerciseFormNotes;

  /// No description provided for @exerciseFormNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Execution tips, proper form...'**
  String get exerciseFormNotesHint;

  /// No description provided for @exerciseFormNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get exerciseFormNameRequired;

  /// No description provided for @exerciseFormSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get exerciseFormSave;

  /// No description provided for @exerciseFormError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String exerciseFormError(Object error);

  /// No description provided for @exerciseFormTypeWeightReps.
  ///
  /// In en, this message translates to:
  /// **'Weight × Reps'**
  String get exerciseFormTypeWeightReps;

  /// No description provided for @exerciseFormTypeDistanceTime.
  ///
  /// In en, this message translates to:
  /// **'Distance × Time'**
  String get exerciseFormTypeDistanceTime;

  /// No description provided for @exerciseFormTypeWeightDistance.
  ///
  /// In en, this message translates to:
  /// **'Weight × Distance'**
  String get exerciseFormTypeWeightDistance;

  /// No description provided for @exerciseFormTypeWeightTime.
  ///
  /// In en, this message translates to:
  /// **'Weight × Time'**
  String get exerciseFormTypeWeightTime;

  /// No description provided for @exerciseFormTypeRepsDistance.
  ///
  /// In en, this message translates to:
  /// **'Reps × Distance'**
  String get exerciseFormTypeRepsDistance;

  /// No description provided for @exerciseFormTypeRepsTime.
  ///
  /// In en, this message translates to:
  /// **'Reps × Time'**
  String get exerciseFormTypeRepsTime;

  /// No description provided for @exerciseFormTypeWeightOnly.
  ///
  /// In en, this message translates to:
  /// **'Weight Only'**
  String get exerciseFormTypeWeightOnly;

  /// No description provided for @exerciseFormTypeRepsOnly.
  ///
  /// In en, this message translates to:
  /// **'Reps Only'**
  String get exerciseFormTypeRepsOnly;

  /// No description provided for @exerciseFormTypeDistanceOnly.
  ///
  /// In en, this message translates to:
  /// **'Distance Only'**
  String get exerciseFormTypeDistanceOnly;

  /// No description provided for @exerciseFormTypeTimeOnly.
  ///
  /// In en, this message translates to:
  /// **'Time Only'**
  String get exerciseFormTypeTimeOnly;

  /// No description provided for @quickAddTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Add'**
  String get quickAddTitle;

  /// No description provided for @quickAddHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Bench Press 80kg 3x10'**
  String get quickAddHint;

  /// No description provided for @quickAddSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get quickAddSave;

  /// No description provided for @quickAddAcceptedFormats.
  ///
  /// In en, this message translates to:
  /// **'Accepted formats:'**
  String get quickAddAcceptedFormats;

  /// No description provided for @quickAddSetsIdentified.
  ///
  /// In en, this message translates to:
  /// **'{count} set(s) identified'**
  String quickAddSetsIdentified(Object count);

  /// No description provided for @quickAddRecentExercises.
  ///
  /// In en, this message translates to:
  /// **'Recent Exercises'**
  String get quickAddRecentExercises;

  /// No description provided for @quickAddExerciseNotFound.
  ///
  /// In en, this message translates to:
  /// **'Exercise \"{name}\" not found'**
  String quickAddExerciseNotFound(Object name);

  /// No description provided for @quickAddCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get quickAddCreate;

  /// No description provided for @quickAddSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ {name} • {count} sets registered'**
  String quickAddSaved(Object count, Object name);

  /// No description provided for @quickAddCreatedAndSaved.
  ///
  /// In en, this message translates to:
  /// **'✅ {name} created and registered!'**
  String quickAddCreatedAndSaved(Object name);

  /// No description provided for @quickAddFormatError.
  ///
  /// In en, this message translates to:
  /// **'Format: ExerciseName Weight [SetsxReps]'**
  String get quickAddFormatError;

  /// No description provided for @quickAddWeightNotFound.
  ///
  /// In en, this message translates to:
  /// **'Weight not found. Use: Name Weight [SetsxReps]'**
  String get quickAddWeightNotFound;

  /// No description provided for @quickAddNoSets.
  ///
  /// In en, this message translates to:
  /// **'No sets identified'**
  String get quickAddNoSets;

  /// No description provided for @exerciseDetailEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get exerciseDetailEdit;

  /// No description provided for @exerciseDetailHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get exerciseDetailHistory;

  /// No description provided for @exerciseDetailCharts.
  ///
  /// In en, this message translates to:
  /// **'Charts'**
  String get exerciseDetailCharts;

  /// No description provided for @exerciseDetailChart1RM.
  ///
  /// In en, this message translates to:
  /// **'1RM'**
  String get exerciseDetailChart1RM;

  /// No description provided for @exerciseDetailChartMaxWeight.
  ///
  /// In en, this message translates to:
  /// **'Max Weight'**
  String get exerciseDetailChartMaxWeight;

  /// No description provided for @exerciseDetailChartVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get exerciseDetailChartVolume;

  /// No description provided for @exerciseDetailChartTotalReps.
  ///
  /// In en, this message translates to:
  /// **'Total Reps'**
  String get exerciseDetailChartTotalReps;

  /// No description provided for @workoutDetailContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue Workout'**
  String get workoutDetailContinue;

  /// No description provided for @workoutDetailDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete Workout'**
  String get workoutDetailDelete;

  /// No description provided for @workoutDetailDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete Workout?'**
  String get workoutDetailDeleteConfirm;

  /// No description provided for @workoutDetailEditDate.
  ///
  /// In en, this message translates to:
  /// **'Change Date'**
  String get workoutDetailEditDate;

  /// No description provided for @workoutDetailShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get workoutDetailShare;

  /// No description provided for @workoutDetailNoSets.
  ///
  /// In en, this message translates to:
  /// **'No sets'**
  String get workoutDetailNoSets;

  /// No description provided for @workoutDetailWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get workoutDetailWeight;

  /// No description provided for @workoutDetailDateChanged.
  ///
  /// In en, this message translates to:
  /// **'✅ Date changed!'**
  String get workoutDetailDateChanged;

  /// No description provided for @notificationRestChannelName.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer'**
  String get notificationRestChannelName;

  /// No description provided for @notificationRestChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Rest timer notifications between sets'**
  String get notificationRestChannelDesc;

  /// No description provided for @notificationWorkoutChannelName.
  ///
  /// In en, this message translates to:
  /// **'Workout Timer'**
  String get notificationWorkoutChannelName;

  /// No description provided for @notificationWorkoutChannelDesc.
  ///
  /// In en, this message translates to:
  /// **'Active workout timer notifications'**
  String get notificationWorkoutChannelDesc;

  /// No description provided for @exportServiceBackupText.
  ///
  /// In en, this message translates to:
  /// **'Workout Notes - Workout Backup'**
  String get exportServiceBackupText;

  /// No description provided for @exportServiceCsvText.
  ///
  /// In en, this message translates to:
  /// **'Workout Notes - Workout Export'**
  String get exportServiceCsvText;

  /// No description provided for @exportServiceCsvHeaderDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get exportServiceCsvHeaderDate;

  /// No description provided for @exportServiceCsvHeaderExercise.
  ///
  /// In en, this message translates to:
  /// **'Exercise'**
  String get exportServiceCsvHeaderExercise;

  /// No description provided for @exportServiceCsvHeaderCategory.
  ///
  /// In en, this message translates to:
  /// **'Category'**
  String get exportServiceCsvHeaderCategory;

  /// No description provided for @exportServiceCsvHeaderWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get exportServiceCsvHeaderWeight;

  /// No description provided for @exportServiceCsvHeaderReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get exportServiceCsvHeaderReps;

  /// No description provided for @exportServiceCsvHeaderDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get exportServiceCsvHeaderDistance;

  /// No description provided for @exportServiceCsvHeaderTime.
  ///
  /// In en, this message translates to:
  /// **'Time (s)'**
  String get exportServiceCsvHeaderTime;

  /// No description provided for @exportServiceCsvHeaderWarmup.
  ///
  /// In en, this message translates to:
  /// **'Warm-up'**
  String get exportServiceCsvHeaderWarmup;

  /// No description provided for @exportServiceCsvHeaderRpe.
  ///
  /// In en, this message translates to:
  /// **'RPE'**
  String get exportServiceCsvHeaderRpe;

  /// No description provided for @exportServiceCsvHeaderSetNote.
  ///
  /// In en, this message translates to:
  /// **'Set Note'**
  String get exportServiceCsvHeaderSetNote;

  /// No description provided for @exportServiceCsvHeaderWorkoutNote.
  ///
  /// In en, this message translates to:
  /// **'Workout Note'**
  String get exportServiceCsvHeaderWorkoutNote;

  /// No description provided for @exportServiceCsvYes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get exportServiceCsvYes;

  /// No description provided for @exportServiceCsvNo.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get exportServiceCsvNo;

  /// No description provided for @exportServiceWorkoutSummary.
  ///
  /// In en, this message translates to:
  /// **'🏋️ Workout - {date}\n'**
  String exportServiceWorkoutSummary(Object date);

  /// No description provided for @exportServiceWorkoutNote.
  ///
  /// In en, this message translates to:
  /// **'📝 {note}\n'**
  String exportServiceWorkoutNote(Object note);

  /// No description provided for @noticePermissionTitle.
  ///
  /// In en, this message translates to:
  /// **'Rest Timer Permission'**
  String get noticePermissionTitle;

  /// No description provided for @noticePermissionBody.
  ///
  /// In en, this message translates to:
  /// **'This app needs notification permission to alert you when rest time is over during workouts.'**
  String get noticePermissionBody;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
