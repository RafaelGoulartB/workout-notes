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

  /// No description provided for @workoutHomeSectionQuickActions.
  ///
  /// In en, this message translates to:
  /// **'QUICK ACTIONS'**
  String get workoutHomeSectionQuickActions;

  /// No description provided for @workoutHomeSectionTools.
  ///
  /// In en, this message translates to:
  /// **'TOOLS'**
  String get workoutHomeSectionTools;

  /// No description provided for @workoutHomeSectionHistory.
  ///
  /// In en, this message translates to:
  /// **'HISTORY'**
  String get workoutHomeSectionHistory;

  /// No description provided for @workoutHomeActiveBannerSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{duration} elapsed · tap to continue'**
  String workoutHomeActiveBannerSubtitle(Object duration);

  /// No description provided for @workoutHomeActiveBannerAction.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get workoutHomeActiveBannerAction;

  /// No description provided for @workoutHomeLastWorkout.
  ///
  /// In en, this message translates to:
  /// **'Last workout'**
  String get workoutHomeLastWorkout;

  /// No description provided for @workoutHomeLastWorkoutAgo.
  ///
  /// In en, this message translates to:
  /// **'{when} ago'**
  String workoutHomeLastWorkoutAgo(Object when);

  /// No description provided for @workoutHomeLastWorkoutToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get workoutHomeLastWorkoutToday;

  /// No description provided for @workoutHomeLastWorkoutYesterday.
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get workoutHomeLastWorkoutYesterday;

  /// No description provided for @workoutHomeEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No workouts yet'**
  String get workoutHomeEmptyTitle;

  /// No description provided for @workoutHomeEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Log your first workout to start tracking your progress'**
  String get workoutHomeEmptySubtitle;

  /// No description provided for @workoutHomeEmptyCta.
  ///
  /// In en, this message translates to:
  /// **'Start first workout'**
  String get workoutHomeEmptyCta;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearance;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In en, this message translates to:
  /// **'APPEARANCE'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsSectionWorkout.
  ///
  /// In en, this message translates to:
  /// **'WORKOUT'**
  String get settingsSectionWorkout;

  /// No description provided for @settingsSectionNotifications.
  ///
  /// In en, this message translates to:
  /// **'NOTIFICATIONS'**
  String get settingsSectionNotifications;

  /// No description provided for @settingsSectionData.
  ///
  /// In en, this message translates to:
  /// **'DATA'**
  String get settingsSectionData;

  /// No description provided for @settingsAboutDescription.
  ///
  /// In en, this message translates to:
  /// **'A complete workout tracker with routines, progress charts, body measurements and CSV export.'**
  String get settingsAboutDescription;

  /// No description provided for @settingsAboutOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get settingsAboutOk;

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

  /// No description provided for @settingsGenerateSuccess.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} workouts generated!'**
  String settingsGenerateSuccess(Object count);

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

  /// No description provided for @settingsImportBackup.
  ///
  /// In en, this message translates to:
  /// **'Import Backup'**
  String get settingsImportBackup;

  /// No description provided for @settingsImportBackupSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore all data from a JSON backup'**
  String get settingsImportBackupSubtitle;

  /// No description provided for @settingsImportWarning.
  ///
  /// In en, this message translates to:
  /// **'This will replace ALL your current data (workouts, exercises, routines, measurements, settings) with the backup data.\n\nThis action cannot be undone.'**
  String get settingsImportWarning;

  /// No description provided for @settingsImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsImport;

  /// No description provided for @settingsImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} records imported! Restart the app to apply changes.'**
  String settingsImportSuccess(Object count);

  /// No description provided for @settingsImportError.
  ///
  /// In en, this message translates to:
  /// **'Import error: {error}'**
  String settingsImportError(Object error);

  /// No description provided for @settingsNoBackupFile.
  ///
  /// In en, this message translates to:
  /// **'No backup file selected'**
  String get settingsNoBackupFile;

  /// No description provided for @settingsImportPasteTitle.
  ///
  /// In en, this message translates to:
  /// **'Paste Backup'**
  String get settingsImportPasteTitle;

  /// No description provided for @settingsImportPasteHint.
  ///
  /// In en, this message translates to:
  /// **'Copy the .json file content and paste here'**
  String get settingsImportPasteHint;

  /// No description provided for @settingsImportPasteOption.
  ///
  /// In en, this message translates to:
  /// **'Paste backup content'**
  String get settingsImportPasteOption;

  /// No description provided for @settingsImportPasteSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Copy the JSON from another device and paste here'**
  String get settingsImportPasteSubtitle;

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

  /// No description provided for @progressBodyMeasurementsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'View detailed trends, photos, and body composition charts'**
  String get progressBodyMeasurementsSubtitle;

  /// No description provided for @progressCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get progressCardio;

  /// No description provided for @progressCardioSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Distance, pace, and cardiovascular tracking'**
  String get progressCardioSubtitle;

  /// No description provided for @progressCardioWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly Distance'**
  String get progressCardioWeekly;

  /// No description provided for @progressCardioByModality.
  ///
  /// In en, this message translates to:
  /// **'Distance by Modality'**
  String get progressCardioByModality;

  /// No description provided for @progressCardioPace.
  ///
  /// In en, this message translates to:
  /// **'Pace Trend'**
  String get progressCardioPace;

  /// No description provided for @progressCardioPRs.
  ///
  /// In en, this message translates to:
  /// **'Cardio Records'**
  String get progressCardioPRs;

  /// No description provided for @progressCardioTotal.
  ///
  /// In en, this message translates to:
  /// **'Total: {distance} this month'**
  String progressCardioTotal(Object distance);

  /// No description provided for @progressCardioAvgPace.
  ///
  /// In en, this message translates to:
  /// **'Avg pace: {pace}'**
  String progressCardioAvgPace(Object pace);

  /// No description provided for @progressCardioNoData.
  ///
  /// In en, this message translates to:
  /// **'No cardio workouts yet'**
  String get progressCardioNoData;

  /// No description provided for @progressCardioNoDataCta.
  ///
  /// In en, this message translates to:
  /// **'Start a cardio workout'**
  String get progressCardioNoDataCta;

  /// No description provided for @progressFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get progressFilterAll;

  /// No description provided for @progressFilterStrength.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get progressFilterStrength;

  /// No description provided for @progressFilterCardio.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get progressFilterCardio;

  /// No description provided for @progressSelectExercise.
  ///
  /// In en, this message translates to:
  /// **'Select exercise'**
  String get progressSelectExercise;

  /// No description provided for @cardioLongestDistance.
  ///
  /// In en, this message translates to:
  /// **'Longest Distance'**
  String get cardioLongestDistance;

  /// No description provided for @cardioLongestDuration.
  ///
  /// In en, this message translates to:
  /// **'Longest Duration'**
  String get cardioLongestDuration;

  /// No description provided for @cardioBestPace.
  ///
  /// In en, this message translates to:
  /// **'Best Pace'**
  String get cardioBestPace;

  /// No description provided for @settingsDistanceUnit.
  ///
  /// In en, this message translates to:
  /// **'Distance Unit'**
  String get settingsDistanceUnit;

  /// No description provided for @settingsDistanceUnitKm.
  ///
  /// In en, this message translates to:
  /// **'km'**
  String get settingsDistanceUnitKm;

  /// No description provided for @settingsDistanceUnitMi.
  ///
  /// In en, this message translates to:
  /// **'mi (miles)'**
  String get settingsDistanceUnitMi;

  /// No description provided for @workoutHomeCardioDistance.
  ///
  /// In en, this message translates to:
  /// **'Cardio Dist.'**
  String get workoutHomeCardioDistance;

  /// No description provided for @workoutHomeCardioTime.
  ///
  /// In en, this message translates to:
  /// **'Cardio Time'**
  String get workoutHomeCardioTime;

  /// No description provided for @commonDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get commonDistance;

  /// No description provided for @commonPace.
  ///
  /// In en, this message translates to:
  /// **'Pace'**
  String get commonPace;

  /// No description provided for @commonTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get commonTotal;

  /// No description provided for @progressBodyComposition.
  ///
  /// In en, this message translates to:
  /// **'Body Composition Evolution'**
  String get progressBodyComposition;

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

  /// No description provided for @progressDensityAverage.
  ///
  /// In en, this message translates to:
  /// **'Average: {avg} kg/min'**
  String progressDensityAverage(Object avg);

  /// No description provided for @progressWeekAbbreviation.
  ///
  /// In en, this message translates to:
  /// **'W'**
  String get progressWeekAbbreviation;

  /// No description provided for @progressBodyWeight.
  ///
  /// In en, this message translates to:
  /// **'Body Weight'**
  String get progressBodyWeight;

  /// No description provided for @progressNoChartData.
  ///
  /// In en, this message translates to:
  /// **'No data available for this chart'**
  String get progressNoChartData;

  /// No description provided for @progressHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout History'**
  String get progressHistoryTitle;

  /// No description provided for @progressHistoryDate.
  ///
  /// In en, this message translates to:
  /// **'Date'**
  String get progressHistoryDate;

  /// No description provided for @progressHistorySetsReps.
  ///
  /// In en, this message translates to:
  /// **'Sets × Reps'**
  String get progressHistorySetsReps;

  /// No description provided for @progressLoadError.
  ///
  /// In en, this message translates to:
  /// **'Error loading data'**
  String get progressLoadError;

  /// No description provided for @progressHeatmapNoData.
  ///
  /// In en, this message translates to:
  /// **'No data for {year}'**
  String progressHeatmapNoData(Object year);

  /// No description provided for @progressChartTitleProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressChartTitleProgress;

  /// No description provided for @progressChartTitleVolumePerWorkout.
  ///
  /// In en, this message translates to:
  /// **'Volume per Workout'**
  String get progressChartTitleVolumePerWorkout;

  /// No description provided for @progressChartTitleRepsPerWorkout.
  ///
  /// In en, this message translates to:
  /// **'Reps per Workout'**
  String get progressChartTitleRepsPerWorkout;

  /// No description provided for @progressRecoveryFeeling.
  ///
  /// In en, this message translates to:
  /// **'Feeling Over Time'**
  String get progressRecoveryFeeling;

  /// No description provided for @progressRecoveryFeelingVsVolume.
  ///
  /// In en, this message translates to:
  /// **'Feeling vs Average Volume'**
  String get progressRecoveryFeelingVsVolume;

  /// No description provided for @progressBodyWeightVsVolume.
  ///
  /// In en, this message translates to:
  /// **'Body Weight vs Workout Volume'**
  String get progressBodyWeightVsVolume;

  /// No description provided for @progressVolumeByMonth.
  ///
  /// In en, this message translates to:
  /// **'Volume by Month'**
  String get progressVolumeByMonth;

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

  /// No description provided for @bodyTrackerQuickMeasure.
  ///
  /// In en, this message translates to:
  /// **'Quick Measure'**
  String get bodyTrackerQuickMeasure;

  /// No description provided for @bodyTrackerQuickMeasureSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Fill in the measurements you want to record. Leave blank to skip.'**
  String get bodyTrackerQuickMeasureSubtitle;

  /// No description provided for @bodyTrackerSaveAll.
  ///
  /// In en, this message translates to:
  /// **'Save Measurements'**
  String get bodyTrackerSaveAll;

  /// No description provided for @bodyTrackerAddSingle.
  ///
  /// In en, this message translates to:
  /// **'Add {type}'**
  String bodyTrackerAddSingle(Object type);

  /// No description provided for @bodyTrackerEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No measurements yet'**
  String get bodyTrackerEmptyTitle;

  /// No description provided for @bodyTrackerEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start tracking your body measurements to see your progress over time.'**
  String get bodyTrackerEmptySubtitle;

  /// No description provided for @bodyTrackerBodyMap.
  ///
  /// In en, this message translates to:
  /// **'BODY MAP'**
  String get bodyTrackerBodyMap;

  /// No description provided for @bodyTrackerLastValue.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get bodyTrackerLastValue;

  /// No description provided for @bodyTrackerCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get bodyTrackerCurrent;

  /// No description provided for @bodyTrackerAverage.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get bodyTrackerAverage;

  /// No description provided for @bodyTrackerMin.
  ///
  /// In en, this message translates to:
  /// **'Min'**
  String get bodyTrackerMin;

  /// No description provided for @bodyTrackerMax.
  ///
  /// In en, this message translates to:
  /// **'Max'**
  String get bodyTrackerMax;

  /// No description provided for @bodyTrackerTrendLine.
  ///
  /// In en, this message translates to:
  /// **'Trend'**
  String get bodyTrackerTrendLine;

  /// No description provided for @bodyTrackerHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get bodyTrackerHistory;

  /// No description provided for @bodyTrackerEntries.
  ///
  /// In en, this message translates to:
  /// **'entries'**
  String get bodyTrackerEntries;

  /// No description provided for @bodyTrackerNeedTwoMeasurements.
  ///
  /// In en, this message translates to:
  /// **'Add at least 2 measurements to see the chart'**
  String get bodyTrackerNeedTwoMeasurements;

  /// No description provided for @bodyTrackerPhoto.
  ///
  /// In en, this message translates to:
  /// **'Photo (optional)'**
  String get bodyTrackerPhoto;

  /// No description provided for @bodyTrackerCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get bodyTrackerCamera;

  /// No description provided for @bodyTrackerGallery.
  ///
  /// In en, this message translates to:
  /// **'Gallery'**
  String get bodyTrackerGallery;

  /// No description provided for @bodyTrackerInvalidValue.
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get bodyTrackerInvalidValue;

  /// No description provided for @bodyTrackerFasting.
  ///
  /// In en, this message translates to:
  /// **'Fasting'**
  String get bodyTrackerFasting;

  /// No description provided for @bodyTrackerFasted.
  ///
  /// In en, this message translates to:
  /// **'Fasted'**
  String get bodyTrackerFasted;

  /// No description provided for @bodyTrackerQuickCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Quick note (optional)'**
  String get bodyTrackerQuickCommentHint;

  /// No description provided for @bodyTrackerSavedBatch.
  ///
  /// In en, this message translates to:
  /// **'✅ {count} measurements saved!'**
  String bodyTrackerSavedBatch(Object count);

  /// No description provided for @bodyTrackerLeftAbbr.
  ///
  /// In en, this message translates to:
  /// **'L'**
  String get bodyTrackerLeftAbbr;

  /// No description provided for @bodyTrackerRightAbbr.
  ///
  /// In en, this message translates to:
  /// **'R'**
  String get bodyTrackerRightAbbr;

  /// No description provided for @bodyTrackerLastLabel.
  ///
  /// In en, this message translates to:
  /// **'Last: '**
  String get bodyTrackerLastLabel;

  /// No description provided for @bodyTrackerMorning.
  ///
  /// In en, this message translates to:
  /// **'Morning'**
  String get bodyTrackerMorning;

  /// No description provided for @bodyTrackerAfternoon.
  ///
  /// In en, this message translates to:
  /// **'Afternoon'**
  String get bodyTrackerAfternoon;

  /// No description provided for @bodyTrackerEvening.
  ///
  /// In en, this message translates to:
  /// **'Evening'**
  String get bodyTrackerEvening;

  /// No description provided for @bodyTrackerNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get bodyTrackerNight;

  /// No description provided for @bodyTrackerCalf.
  ///
  /// In en, this message translates to:
  /// **'Calf'**
  String get bodyTrackerCalf;

  /// No description provided for @bodyTrackerForearm.
  ///
  /// In en, this message translates to:
  /// **'Forearm'**
  String get bodyTrackerForearm;

  /// No description provided for @bodyTrackerNeck.
  ///
  /// In en, this message translates to:
  /// **'Neck'**
  String get bodyTrackerNeck;

  /// No description provided for @bodyTrackerLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get bodyTrackerLeft;

  /// No description provided for @bodyTrackerRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get bodyTrackerRight;

  /// No description provided for @bodyTrackerSelectMeasurement.
  ///
  /// In en, this message translates to:
  /// **'Select Measurement'**
  String get bodyTrackerSelectMeasurement;

  /// No description provided for @bodyTrackerCustomize.
  ///
  /// In en, this message translates to:
  /// **'Customize'**
  String get bodyTrackerCustomize;

  /// No description provided for @bodyTrackerCustomizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Customize Measurements'**
  String get bodyTrackerCustomizeTitle;

  /// No description provided for @bodyTrackerCustomizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select the measurements you want to track'**
  String get bodyTrackerCustomizeSubtitle;

  /// No description provided for @bodyTrackerLeanMass.
  ///
  /// In en, this message translates to:
  /// **'Lean Mass'**
  String get bodyTrackerLeanMass;

  /// No description provided for @bodyTrackerFatMass.
  ///
  /// In en, this message translates to:
  /// **'Fat Mass'**
  String get bodyTrackerFatMass;

  /// No description provided for @bodyTrackerHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get bodyTrackerHealthy;

  /// No description provided for @bodyTrackerModerate.
  ///
  /// In en, this message translates to:
  /// **'Moderate Risk'**
  String get bodyTrackerModerate;

  /// No description provided for @bodyTrackerHigh.
  ///
  /// In en, this message translates to:
  /// **'High Risk'**
  String get bodyTrackerHigh;

  /// No description provided for @bodyTrackerAsymmetry.
  ///
  /// In en, this message translates to:
  /// **'Difference: {diff} {unit} ({largerSide} larger)'**
  String bodyTrackerAsymmetry(Object diff, Object largerSide, Object unit);

  /// No description provided for @bodyTrackerTrendComparison.
  ///
  /// In en, this message translates to:
  /// **'Left vs Right'**
  String get bodyTrackerTrendComparison;

  /// No description provided for @bodyTrackerLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more entries'**
  String bodyTrackerLoadMore(Object count);

  /// No description provided for @bodyTrackerLoadMoreCount.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String bodyTrackerLoadMoreCount(Object count);

  /// No description provided for @bodyTrackerWHR.
  ///
  /// In en, this message translates to:
  /// **'WHR'**
  String get bodyTrackerWHR;

  /// No description provided for @bodyTrackerEstimatedComposition.
  ///
  /// In en, this message translates to:
  /// **'Estimated Body Composition'**
  String get bodyTrackerEstimatedComposition;

  /// No description provided for @bodyTrackerTimeOfDay.
  ///
  /// In en, this message translates to:
  /// **'Time of day'**
  String get bodyTrackerTimeOfDay;

  /// No description provided for @bodyTrackerNotInformed.
  ///
  /// In en, this message translates to:
  /// **'Not informed'**
  String get bodyTrackerNotInformed;

  /// No description provided for @commonOptional.
  ///
  /// In en, this message translates to:
  /// **'optional'**
  String get commonOptional;

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

  /// No description provided for @routinesEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No routines yet'**
  String get routinesEmptyTitle;

  /// No description provided for @routinesEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Create a routine to train faster'**
  String get routinesEmptySubtitle;

  /// No description provided for @routinesRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get routinesRename;

  /// No description provided for @routinesNewDay.
  ///
  /// In en, this message translates to:
  /// **'New Day'**
  String get routinesNewDay;

  /// No description provided for @routinesDayName.
  ///
  /// In en, this message translates to:
  /// **'Day Name'**
  String get routinesDayName;

  /// No description provided for @routinesDayNameHint.
  ///
  /// In en, this message translates to:
  /// **'Ex: Push Day, Monday'**
  String get routinesDayNameHint;

  /// No description provided for @routinesAddDay.
  ///
  /// In en, this message translates to:
  /// **'Add Day'**
  String get routinesAddDay;

  /// No description provided for @routinesDeleteDay.
  ///
  /// In en, this message translates to:
  /// **'Delete Day'**
  String get routinesDeleteDay;

  /// No description provided for @routinesEditDay.
  ///
  /// In en, this message translates to:
  /// **'Edit Day'**
  String get routinesEditDay;

  /// No description provided for @routinesDayEmpty.
  ///
  /// In en, this message translates to:
  /// **'No days yet'**
  String get routinesDayEmpty;

  /// No description provided for @routinesDayEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add days to your routine'**
  String get routinesDayEmptySubtitle;

  /// No description provided for @routinesNoExercises.
  ///
  /// In en, this message translates to:
  /// **'No exercises added'**
  String get routinesNoExercises;

  /// No description provided for @routinesAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get routinesAddExercise;

  /// No description provided for @routinesRestTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Rest Time'**
  String get routinesRestTimeTitle;

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

  /// No description provided for @workoutDetailEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit Workout'**
  String get workoutDetailEdit;

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

  /// No description provided for @workoutDetailKg.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get workoutDetailKg;

  /// No description provided for @workoutDetailViewExercise.
  ///
  /// In en, this message translates to:
  /// **'View exercise'**
  String get workoutDetailViewExercise;

  /// No description provided for @workoutDetailSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select the new date'**
  String get workoutDetailSelectDate;

  /// No description provided for @workoutDetailCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy Workout'**
  String get workoutDetailCopy;

  /// No description provided for @workoutDetailCopyDateChanged.
  ///
  /// In en, this message translates to:
  /// **'✅ Workout copied!'**
  String get workoutDetailCopyDateChanged;

  /// No description provided for @workoutDetailGoToWorkout.
  ///
  /// In en, this message translates to:
  /// **'Go to workout'**
  String get workoutDetailGoToWorkout;

  /// No description provided for @workoutDetailDuration.
  ///
  /// In en, this message translates to:
  /// **'{min}min {sec}s'**
  String workoutDetailDuration(Object min, Object sec);

  /// No description provided for @activeWorkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Workout'**
  String get activeWorkoutTitle;

  /// No description provided for @activeWorkoutFinishWorkout.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get activeWorkoutFinishWorkout;

  /// No description provided for @activeWorkoutFinished.
  ///
  /// In en, this message translates to:
  /// **'💪 Workout finished!'**
  String get activeWorkoutFinished;

  /// No description provided for @activeWorkoutFinishedWithPRs.
  ///
  /// In en, this message translates to:
  /// **'🎉 Workout finished! {count} personal record(s)!'**
  String activeWorkoutFinishedWithPRs(Object count);

  /// No description provided for @activeWorkoutAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get activeWorkoutAddExercise;

  /// No description provided for @activeWorkoutEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No exercises yet'**
  String get activeWorkoutEmptyTitle;

  /// No description provided for @activeWorkoutEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add exercises to start your workout'**
  String get activeWorkoutEmptySubtitle;

  /// No description provided for @activeWorkoutImportRoutine.
  ///
  /// In en, this message translates to:
  /// **'Import from Routine'**
  String get activeWorkoutImportRoutine;

  /// No description provided for @activeWorkoutEditSet.
  ///
  /// In en, this message translates to:
  /// **'Edit Set'**
  String get activeWorkoutEditSet;

  /// No description provided for @activeWorkoutWarmup.
  ///
  /// In en, this message translates to:
  /// **'Warm-up'**
  String get activeWorkoutWarmup;

  /// No description provided for @activeWorkoutRemoveExercise.
  ///
  /// In en, this message translates to:
  /// **'Remove Exercise?'**
  String get activeWorkoutRemoveExercise;

  /// No description provided for @activeWorkoutRemoveExerciseContent.
  ///
  /// In en, this message translates to:
  /// **'Remove \"{name}\" from the workout?'**
  String activeWorkoutRemoveExerciseContent(Object name);

  /// No description provided for @activeWorkoutRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} removed from workout'**
  String activeWorkoutRemoved(Object name);

  /// No description provided for @activeWorkoutResetTimer.
  ///
  /// In en, this message translates to:
  /// **'Reset Timer?'**
  String get activeWorkoutResetTimer;

  /// No description provided for @activeWorkoutResetTimerContent.
  ///
  /// In en, this message translates to:
  /// **'This will clear the start and end time of the workout.'**
  String get activeWorkoutResetTimerContent;

  /// No description provided for @activeWorkoutReset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get activeWorkoutReset;

  /// No description provided for @activeWorkoutWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get activeWorkoutWeight;

  /// No description provided for @activeWorkoutReps.
  ///
  /// In en, this message translates to:
  /// **'Reps'**
  String get activeWorkoutReps;

  /// No description provided for @activeWorkoutDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance (km)'**
  String get activeWorkoutDistance;

  /// No description provided for @activeWorkoutTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get activeWorkoutTime;

  /// No description provided for @activeWorkoutTimerDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get activeWorkoutTimerDuration;

  /// No description provided for @activeWorkoutTimerStartLabel.
  ///
  /// In en, this message translates to:
  /// **'Started at'**
  String get activeWorkoutTimerStartLabel;

  /// No description provided for @activeWorkoutTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Timer'**
  String get activeWorkoutTimerTitle;

  /// No description provided for @activeWorkoutNoRoutineFound.
  ///
  /// In en, this message translates to:
  /// **'No routine found. Create one first!'**
  String get activeWorkoutNoRoutineFound;

  /// No description provided for @activeWorkoutNoRoutineDays.
  ///
  /// In en, this message translates to:
  /// **'This routine has no days.'**
  String get activeWorkoutNoRoutineDays;

  /// No description provided for @activeWorkoutRoutineImported.
  ///
  /// In en, this message translates to:
  /// **'✅ Exercises imported from routine!'**
  String get activeWorkoutRoutineImported;

  /// No description provided for @activeWorkoutSelectRoutine.
  ///
  /// In en, this message translates to:
  /// **'Select Routine'**
  String get activeWorkoutSelectRoutine;

  /// No description provided for @activeWorkoutBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get activeWorkoutBack;

  /// No description provided for @activeWorkoutStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get activeWorkoutStart;

  /// No description provided for @activeWorkoutStartTimerTooltip.
  ///
  /// In en, this message translates to:
  /// **'Start workout timer'**
  String get activeWorkoutStartTimerTooltip;

  /// No description provided for @activeWorkoutSetsSummary.
  ///
  /// In en, this message translates to:
  /// **'{completed}/{total} sets'**
  String activeWorkoutSetsSummary(Object completed, Object total);

  /// No description provided for @activeWorkoutOK.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get activeWorkoutOK;

  /// No description provided for @activeWorkoutRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get activeWorkoutRemove;

  /// No description provided for @activeWorkoutCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get activeWorkoutCustom;

  /// No description provided for @activeWorkoutCustomTime.
  ///
  /// In en, this message translates to:
  /// **'Custom Time'**
  String get activeWorkoutCustomTime;

  /// No description provided for @activeWorkoutSelectDay.
  ///
  /// In en, this message translates to:
  /// **'Select the day to import'**
  String get activeWorkoutSelectDay;

  /// No description provided for @activeWorkoutAddSet.
  ///
  /// In en, this message translates to:
  /// **'Add Set'**
  String get activeWorkoutAddSet;

  /// No description provided for @activeWorkoutCompleted.
  ///
  /// In en, this message translates to:
  /// **'Workout Completed!'**
  String get activeWorkoutCompleted;

  /// No description provided for @activeWorkoutSummarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Great job! Here\'s the summary:'**
  String get activeWorkoutSummarySubtitle;

  /// No description provided for @activeWorkoutPersonalRecords.
  ///
  /// In en, this message translates to:
  /// **'New Personal Records'**
  String get activeWorkoutPersonalRecords;

  /// No description provided for @activeWorkoutHowWasWorkout.
  ///
  /// In en, this message translates to:
  /// **'How was the workout?'**
  String get activeWorkoutHowWasWorkout;

  /// No description provided for @activeWorkoutCommentHint.
  ///
  /// In en, this message translates to:
  /// **'Workout note (optional)...'**
  String get activeWorkoutCommentHint;

  /// No description provided for @activeWorkoutFeeling1.
  ///
  /// In en, this message translates to:
  /// **'Bad'**
  String get activeWorkoutFeeling1;

  /// No description provided for @activeWorkoutFeeling2.
  ///
  /// In en, this message translates to:
  /// **'Ok'**
  String get activeWorkoutFeeling2;

  /// No description provided for @activeWorkoutFeeling3.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get activeWorkoutFeeling3;

  /// No description provided for @activeWorkoutFeeling4.
  ///
  /// In en, this message translates to:
  /// **'Great'**
  String get activeWorkoutFeeling4;

  /// No description provided for @activeWorkoutFeeling5.
  ///
  /// In en, this message translates to:
  /// **'Excellent!'**
  String get activeWorkoutFeeling5;

  /// No description provided for @activeWorkoutSetLabel.
  ///
  /// In en, this message translates to:
  /// **'Set {number}'**
  String activeWorkoutSetLabel(Object number);

  /// No description provided for @workoutDetailSetNumber.
  ///
  /// In en, this message translates to:
  /// **'#'**
  String get workoutDetailSetNumber;

  /// No description provided for @workoutDetailRpe.
  ///
  /// In en, this message translates to:
  /// **'RPE'**
  String get workoutDetailRpe;

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

  /// No description provided for @routinesDayDashboard.
  ///
  /// In en, this message translates to:
  /// **'Day Dashboard'**
  String get routinesDayDashboard;

  /// No description provided for @routinesNoExercisesHint.
  ///
  /// In en, this message translates to:
  /// **'Add exercises to build your workout template'**
  String get routinesNoExercisesHint;

  /// No description provided for @routinesDayDashboardSets.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get routinesDayDashboardSets;

  /// No description provided for @routinesDayDashboardVolume.
  ///
  /// In en, this message translates to:
  /// **'kg volume'**
  String get routinesDayDashboardVolume;

  /// No description provided for @routinesDayDashboardGroups.
  ///
  /// In en, this message translates to:
  /// **'groups'**
  String get routinesDayDashboardGroups;

  /// No description provided for @routinesWeeklyView.
  ///
  /// In en, this message translates to:
  /// **'Weekly View'**
  String get routinesWeeklyView;

  /// No description provided for @routinesPerDay.
  ///
  /// In en, this message translates to:
  /// **'Per Day'**
  String get routinesPerDay;

  /// No description provided for @routinesDaySets.
  ///
  /// In en, this message translates to:
  /// **'{count} sets'**
  String routinesDaySets(Object count);

  /// No description provided for @routinesDayGroups.
  ///
  /// In en, this message translates to:
  /// **'{count} groups'**
  String routinesDayGroups(Object count);

  /// No description provided for @routinesInsightMuscleGroups.
  ///
  /// In en, this message translates to:
  /// **'📋 {count} muscle groups this week'**
  String routinesInsightMuscleGroups(Object count);

  /// No description provided for @routinesInsightBalanced.
  ///
  /// In en, this message translates to:
  /// **'⚖️ Balanced week! All groups with similar volume.'**
  String get routinesInsightBalanced;

  /// No description provided for @routinesInsightHighDiff.
  ///
  /// In en, this message translates to:
  /// **'💪 {highest} ({highestSets}s) is far above {lowest} ({lowestSets}s). Consider redistributing.'**
  String routinesInsightHighDiff(
    Object highest,
    Object highestSets,
    Object lowest,
    Object lowestSets,
  );

  /// No description provided for @routinesInsightFocus.
  ///
  /// In en, this message translates to:
  /// **'📊 Focus on {highest} ({pct}% of sets). {lowest} with {lowestSets}s — lower volume.'**
  String routinesInsightFocus(
    Object highest,
    Object lowest,
    Object lowestSets,
    Object pct,
  );

  /// No description provided for @routinesInsightAverage.
  ///
  /// In en, this message translates to:
  /// **'Average of {avg} sets/day over {days} training days.'**
  String routinesInsightAverage(Object avg, Object days);

  /// No description provided for @routinesWeeklyVolume.
  ///
  /// In en, this message translates to:
  /// **'{volume}kg volume'**
  String routinesWeeklyVolume(Object volume);

  /// No description provided for @routinesWeeklyDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String routinesWeeklyDays(Object count);

  /// No description provided for @routinesNotes.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get routinesNotes;

  /// No description provided for @routinesNotesHint.
  ///
  /// In en, this message translates to:
  /// **'Optional routine description'**
  String get routinesNotesHint;

  /// No description provided for @reorderHint.
  ///
  /// In en, this message translates to:
  /// **'Press and hold an exercise to reorder'**
  String get reorderHint;

  /// No description provided for @reorderMovedToTop.
  ///
  /// In en, this message translates to:
  /// **'Moved to top'**
  String get reorderMovedToTop;

  /// No description provided for @reorderMovedToBottom.
  ///
  /// In en, this message translates to:
  /// **'Moved to bottom'**
  String get reorderMovedToBottom;

  /// No description provided for @editWorkoutTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Workout'**
  String get editWorkoutTitle;

  /// No description provided for @editWorkoutDateTime.
  ///
  /// In en, this message translates to:
  /// **'Date and Time'**
  String get editWorkoutDateTime;

  /// No description provided for @editWorkoutStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get editWorkoutStart;

  /// No description provided for @editWorkoutEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get editWorkoutEnd;

  /// No description provided for @editWorkoutDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get editWorkoutDuration;

  /// No description provided for @editWorkoutChangeDate.
  ///
  /// In en, this message translates to:
  /// **'Change Date'**
  String get editWorkoutChangeDate;

  /// No description provided for @editWorkoutChangeStart.
  ///
  /// In en, this message translates to:
  /// **'Change start time'**
  String get editWorkoutChangeStart;

  /// No description provided for @editWorkoutChangeEnd.
  ///
  /// In en, this message translates to:
  /// **'Change end time'**
  String get editWorkoutChangeEnd;

  /// No description provided for @editWorkoutChangeStartDate.
  ///
  /// In en, this message translates to:
  /// **'Change start date and time'**
  String get editWorkoutChangeStartDate;

  /// No description provided for @editWorkoutChangeEndDate.
  ///
  /// In en, this message translates to:
  /// **'Change end date and time'**
  String get editWorkoutChangeEndDate;

  /// No description provided for @editWorkoutSelectDate.
  ///
  /// In en, this message translates to:
  /// **'Select date'**
  String get editWorkoutSelectDate;

  /// No description provided for @editWorkoutSelectTime.
  ///
  /// In en, this message translates to:
  /// **'Select time'**
  String get editWorkoutSelectTime;

  /// No description provided for @editWorkoutEndAfterStart.
  ///
  /// In en, this message translates to:
  /// **'End time must be after start time'**
  String get editWorkoutEndAfterStart;

  /// No description provided for @editWorkoutInvalidRange.
  ///
  /// In en, this message translates to:
  /// **'Invalid date range'**
  String get editWorkoutInvalidRange;

  /// No description provided for @editWorkoutSaved.
  ///
  /// In en, this message translates to:
  /// **'Workout updated'**
  String get editWorkoutSaved;

  /// No description provided for @editWorkoutReorderHint.
  ///
  /// In en, this message translates to:
  /// **'Press and hold an exercise to reorder'**
  String get editWorkoutReorderHint;

  /// No description provided for @editWorkoutAddExercise.
  ///
  /// In en, this message translates to:
  /// **'Add Exercise'**
  String get editWorkoutAddExercise;

  /// No description provided for @progressGoals.
  ///
  /// In en, this message translates to:
  /// **'Goals'**
  String get progressGoals;

  /// No description provided for @progressGoalsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Track and beat your personal challenges'**
  String get progressGoalsSubtitle;

  /// No description provided for @goalScopeAnaerobic.
  ///
  /// In en, this message translates to:
  /// **'Strength'**
  String get goalScopeAnaerobic;

  /// No description provided for @goalScopeAerobic.
  ///
  /// In en, this message translates to:
  /// **'Cardio'**
  String get goalScopeAerobic;

  /// No description provided for @goalMetricVolume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get goalMetricVolume;

  /// No description provided for @goalMetricDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get goalMetricDays;

  /// No description provided for @goalMetricDistance.
  ///
  /// In en, this message translates to:
  /// **'Distance'**
  String get goalMetricDistance;

  /// No description provided for @goalMetricTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get goalMetricTime;

  /// No description provided for @goalPeriodWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly'**
  String get goalPeriodWeekly;

  /// No description provided for @goalPeriodMonthly.
  ///
  /// In en, this message translates to:
  /// **'Monthly'**
  String get goalPeriodMonthly;

  /// No description provided for @goalCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New Goal'**
  String get goalCreateTitle;

  /// No description provided for @goalEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Goal'**
  String get goalEditTitle;

  /// No description provided for @goalLabelTitle.
  ///
  /// In en, this message translates to:
  /// **'Title (optional)'**
  String get goalLabelTitle;

  /// No description provided for @goalTitleHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Hypertrophy month'**
  String get goalTitleHint;

  /// No description provided for @goalChooseMetric.
  ///
  /// In en, this message translates to:
  /// **'Pick a metric'**
  String get goalChooseMetric;

  /// No description provided for @goalChoosePeriod.
  ///
  /// In en, this message translates to:
  /// **'Period'**
  String get goalChoosePeriod;

  /// No description provided for @goalTargetValue.
  ///
  /// In en, this message translates to:
  /// **'Target value'**
  String get goalTargetValue;

  /// No description provided for @goalTargetHint.
  ///
  /// In en, this message translates to:
  /// **'Numeric value'**
  String get goalTargetHint;

  /// No description provided for @goalCurrentProgress.
  ///
  /// In en, this message translates to:
  /// **'Current progress'**
  String get goalCurrentProgress;

  /// No description provided for @goalDaysRemaining.
  ///
  /// In en, this message translates to:
  /// **'{days, plural, =1{1 day left} other{{days} days left}}'**
  String goalDaysRemaining(num days);

  /// No description provided for @goalCompleted.
  ///
  /// In en, this message translates to:
  /// **'Goal reached! 🎉'**
  String get goalCompleted;

  /// No description provided for @goalKeepGoing.
  ///
  /// In en, this message translates to:
  /// **'Keep pushing!'**
  String get goalKeepGoing;

  /// No description provided for @goalHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get goalHistory;

  /// No description provided for @goalEmpty.
  ///
  /// In en, this message translates to:
  /// **'No goals yet'**
  String get goalEmpty;

  /// No description provided for @goalEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Tap + to create your first goal'**
  String get goalEmptySubtitle;

  /// No description provided for @goalDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete goal'**
  String get goalDelete;

  /// No description provided for @goalDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this goal?'**
  String get goalDeleteConfirm;

  /// No description provided for @goalDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get goalDeleteMessage;

  /// No description provided for @goalPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get goalPaused;

  /// No description provided for @goalPausedBadge.
  ///
  /// In en, this message translates to:
  /// **'PAUSED'**
  String get goalPausedBadge;

  /// No description provided for @goalAchievementRate.
  ///
  /// In en, this message translates to:
  /// **'{rate}% success'**
  String goalAchievementRate(Object rate);

  /// No description provided for @goalGridAdd.
  ///
  /// In en, this message translates to:
  /// **'Add goal'**
  String get goalGridAdd;

  /// No description provided for @goalSuggestedTarget.
  ///
  /// In en, this message translates to:
  /// **'Suggested: {value}'**
  String goalSuggestedTarget(Object value);

  /// No description provided for @goalPickScope.
  ///
  /// In en, this message translates to:
  /// **'Energy System'**
  String get goalPickScope;

  /// No description provided for @goalPickScopeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Strength or Cardio?'**
  String get goalPickScopeSubtitle;

  /// No description provided for @goalStep1.
  ///
  /// In en, this message translates to:
  /// **'Scope'**
  String get goalStep1;

  /// No description provided for @goalStep2.
  ///
  /// In en, this message translates to:
  /// **'Metric'**
  String get goalStep2;

  /// No description provided for @goalStep3.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get goalStep3;

  /// No description provided for @goalNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No past periods'**
  String get goalNoHistory;

  /// No description provided for @goalNoHistoryHint.
  ///
  /// In en, this message translates to:
  /// **'History will appear after the first cycle completes'**
  String get goalNoHistoryHint;

  /// No description provided for @goalResume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get goalResume;

  /// No description provided for @goalPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get goalPause;

  /// No description provided for @goalSaved.
  ///
  /// In en, this message translates to:
  /// **'Goal saved'**
  String get goalSaved;

  /// No description provided for @goalDeleted.
  ///
  /// In en, this message translates to:
  /// **'Goal deleted'**
  String get goalDeleted;

  /// No description provided for @goalValueVolumeKg.
  ///
  /// In en, this message translates to:
  /// **'{value} kg'**
  String goalValueVolumeKg(Object value);

  /// No description provided for @goalValueDistance.
  ///
  /// In en, this message translates to:
  /// **'{value} km'**
  String goalValueDistance(Object value);

  /// No description provided for @goalValueTime.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String goalValueTime(Object value);

  /// No description provided for @goalValueDays.
  ///
  /// In en, this message translates to:
  /// **'{value} days'**
  String goalValueDays(Object value);

  /// No description provided for @goalValueDaysShort.
  ///
  /// In en, this message translates to:
  /// **'{value}d'**
  String goalValueDaysShort(Object value);

  /// No description provided for @goalMotivationNear.
  ///
  /// In en, this message translates to:
  /// **'Almost there — you got this!'**
  String get goalMotivationNear;

  /// No description provided for @goalMotivationMid.
  ///
  /// In en, this message translates to:
  /// **'On track. Keep going!'**
  String get goalMotivationMid;

  /// No description provided for @goalMotivationEarly.
  ///
  /// In en, this message translates to:
  /// **'Let\'s start! Every workout counts.'**
  String get goalMotivationEarly;

  /// No description provided for @goalMotivationDone.
  ///
  /// In en, this message translates to:
  /// **'Amazing! You crushed your goal!'**
  String get goalMotivationDone;

  /// No description provided for @goalContributingWorkouts.
  ///
  /// In en, this message translates to:
  /// **'Workouts this period'**
  String get goalContributingWorkouts;

  /// No description provided for @goalNoContributors.
  ///
  /// In en, this message translates to:
  /// **'No workouts in this period yet'**
  String get goalNoContributors;

  /// No description provided for @progressPeriodWeek.
  ///
  /// In en, this message translates to:
  /// **'Week'**
  String get progressPeriodWeek;

  /// No description provided for @progressPeriodMonth.
  ///
  /// In en, this message translates to:
  /// **'Month'**
  String get progressPeriodMonth;

  /// No description provided for @progressPeriodYear.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get progressPeriodYear;

  /// No description provided for @progressVolumeTypeWeight.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get progressVolumeTypeWeight;

  /// No description provided for @progressVolumeTypeSets.
  ///
  /// In en, this message translates to:
  /// **'Sets'**
  String get progressVolumeTypeSets;

  /// No description provided for @progressVolumeTrend.
  ///
  /// In en, this message translates to:
  /// **'Trend'**
  String get progressVolumeTrend;

  /// No description provided for @progressVolumeTrendLast12Weeks.
  ///
  /// In en, this message translates to:
  /// **'Last 12 weeks'**
  String get progressVolumeTrendLast12Weeks;

  /// No description provided for @progressVolumeTrendLast12Months.
  ///
  /// In en, this message translates to:
  /// **'Last 12 months'**
  String get progressVolumeTrendLast12Months;

  /// No description provided for @progressVolumeTrendLast5Years.
  ///
  /// In en, this message translates to:
  /// **'Last 5 years'**
  String get progressVolumeTrendLast5Years;

  /// No description provided for @progressVolumeUnitSets.
  ///
  /// In en, this message translates to:
  /// **'sets'**
  String get progressVolumeUnitSets;

  /// No description provided for @progressVolumeUnitWeight.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get progressVolumeUnitWeight;

  /// No description provided for @progressVolumeViewPie.
  ///
  /// In en, this message translates to:
  /// **'Pie'**
  String get progressVolumeViewPie;

  /// No description provided for @progressVolumeViewList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get progressVolumeViewList;

  /// No description provided for @progressVolumeTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get progressVolumeTotal;
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
