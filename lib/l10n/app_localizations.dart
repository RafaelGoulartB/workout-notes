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

  /// No description provided for @tabSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get tabSleep;

  /// No description provided for @sleepTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepTitle;

  /// No description provided for @sleepEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No sleep logged'**
  String get sleepEmptyTitle;

  /// No description provided for @sleepEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor your nights to track duration, actual sleep, and consistency.'**
  String get sleepEmptySubtitle;

  /// No description provided for @sleepDuration.
  ///
  /// In en, this message translates to:
  /// **'Sleep duration'**
  String get sleepDuration;

  /// No description provided for @sleepActualDuration.
  ///
  /// In en, this message translates to:
  /// **'Actual sleep'**
  String get sleepActualDuration;

  /// No description provided for @sleepBedtime.
  ///
  /// In en, this message translates to:
  /// **'Bedtime'**
  String get sleepBedtime;

  /// No description provided for @sleepWakeTime.
  ///
  /// In en, this message translates to:
  /// **'Wake-up time'**
  String get sleepWakeTime;

  /// No description provided for @sleepDeleted.
  ///
  /// In en, this message translates to:
  /// **'Sleep record deleted'**
  String get sleepDeleted;

  /// No description provided for @sleepDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this sleep record?'**
  String get sleepDeleteConfirm;

  /// No description provided for @sleepSummary.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get sleepSummary;

  /// No description provided for @sleepLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest record'**
  String get sleepLatest;

  /// No description provided for @sleepAverage7Days.
  ///
  /// In en, this message translates to:
  /// **'Average · 7 days'**
  String get sleepAverage7Days;

  /// No description provided for @sleepAverage30Days.
  ///
  /// In en, this message translates to:
  /// **'Average · 30 days'**
  String get sleepAverage30Days;

  /// No description provided for @sleepActualAverage.
  ///
  /// In en, this message translates to:
  /// **'Actual sleep average'**
  String get sleepActualAverage;

  /// No description provided for @sleepMinimum.
  ///
  /// In en, this message translates to:
  /// **'Minimum · 30 days'**
  String get sleepMinimum;

  /// No description provided for @sleepMaximum.
  ///
  /// In en, this message translates to:
  /// **'Maximum · 30 days'**
  String get sleepMaximum;

  /// No description provided for @sleepConsistency.
  ///
  /// In en, this message translates to:
  /// **'Consistency'**
  String get sleepConsistency;

  /// No description provided for @sleepEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Efficiency'**
  String get sleepEfficiency;

  /// No description provided for @sleepDaysRecorded.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} days recorded'**
  String sleepDaysRecorded(Object count, Object total);

  /// No description provided for @sleepNoActual.
  ///
  /// In en, this message translates to:
  /// **'No actual sleep'**
  String get sleepNoActual;

  /// No description provided for @sleepDailyChart.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get sleepDailyChart;

  /// No description provided for @sleepTrendChart.
  ///
  /// In en, this message translates to:
  /// **'Trend · 30 days'**
  String get sleepTrendChart;

  /// No description provided for @sleepChartRecorded.
  ///
  /// In en, this message translates to:
  /// **'Recorded duration'**
  String get sleepChartRecorded;

  /// No description provided for @sleepChartActual.
  ///
  /// In en, this message translates to:
  /// **'Actual sleep'**
  String get sleepChartActual;

  /// No description provided for @sleepHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get sleepHistory;

  /// No description provided for @sleepEntries.
  ///
  /// In en, this message translates to:
  /// **'{count} records'**
  String sleepEntries(Object count);

  /// No description provided for @sleepNeedTwoEntries.
  ///
  /// In en, this message translates to:
  /// **'Add at least 2 records to see the trend.'**
  String get sleepNeedTwoEntries;

  /// No description provided for @sleepLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more records'**
  String sleepLoadMore(Object count);

  /// No description provided for @sleepLoadMoreCount.
  ///
  /// In en, this message translates to:
  /// **'Load {count} more'**
  String sleepLoadMoreCount(Object count);

  /// No description provided for @sleepDetails.
  ///
  /// In en, this message translates to:
  /// **'Sleep details'**
  String get sleepDetails;

  /// No description provided for @sleepDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete record'**
  String get sleepDelete;

  /// No description provided for @sleepDurationValue.
  ///
  /// In en, this message translates to:
  /// **'{hours}h {minutes}min'**
  String sleepDurationValue(Object hours, Object minutes);

  /// No description provided for @sleepGoalTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep goal'**
  String get sleepGoalTitle;

  /// No description provided for @sleepGoalTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get sleepGoalTarget;

  /// No description provided for @sleepGoalReached.
  ///
  /// In en, this message translates to:
  /// **'Goal reached'**
  String get sleepGoalReached;

  /// No description provided for @sleepGoalMissed.
  ///
  /// In en, this message translates to:
  /// **'Goal missed'**
  String get sleepGoalMissed;

  /// No description provided for @sleepGoalInfo.
  ///
  /// In en, this message translates to:
  /// **'A personal target for comparing your nights. It is not a clinical recommendation.'**
  String get sleepGoalInfo;

  /// No description provided for @sleepMetricSleep.
  ///
  /// In en, this message translates to:
  /// **'Sleep'**
  String get sleepMetricSleep;

  /// No description provided for @sleepMetricTimeInBed.
  ///
  /// In en, this message translates to:
  /// **'Time in bed'**
  String get sleepMetricTimeInBed;

  /// No description provided for @sleepGoalDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Set sleep goal'**
  String get sleepGoalDialogTitle;

  /// No description provided for @sleepGoalDialogDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose how much sleep you want to aim for each night.'**
  String get sleepGoalDialogDescription;

  /// No description provided for @sleepGoalSaved.
  ///
  /// In en, this message translates to:
  /// **'Sleep goal saved'**
  String get sleepGoalSaved;

  /// No description provided for @sleepGoalCurrent.
  ///
  /// In en, this message translates to:
  /// **'{duration} per night'**
  String sleepGoalCurrent(String duration);

  /// No description provided for @sleepGoalBody.
  ///
  /// In en, this message translates to:
  /// **'This target is used to compare your latest night and highlight progress.'**
  String get sleepGoalBody;

  /// No description provided for @sleepMonitorOpen.
  ///
  /// In en, this message translates to:
  /// **'Open monitoring'**
  String get sleepMonitorOpen;

  /// No description provided for @sleepMonitorElapsed.
  ///
  /// In en, this message translates to:
  /// **'Active for {duration}'**
  String sleepMonitorElapsed(String duration);

  /// No description provided for @sleepWeeklySummary.
  ///
  /// In en, this message translates to:
  /// **'Weekly summary'**
  String get sleepWeeklySummary;

  /// No description provided for @sleepAverageSleep.
  ///
  /// In en, this message translates to:
  /// **'Average sleep'**
  String get sleepAverageSleep;

  /// No description provided for @sleepRegularity.
  ///
  /// In en, this message translates to:
  /// **'Regularity'**
  String get sleepRegularity;

  /// No description provided for @sleepRegularityInfo.
  ///
  /// In en, this message translates to:
  /// **'An app consistency score based on bedtime and wake-up variation. It is not a clinical measurement.'**
  String get sleepRegularityInfo;

  /// No description provided for @sleepNightsRecorded.
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} nights recorded'**
  String sleepNightsRecorded(Object count, Object total);

  /// No description provided for @sleepScheduleChart.
  ///
  /// In en, this message translates to:
  /// **'Sleep schedule'**
  String get sleepScheduleChart;

  /// No description provided for @sleepScheduleChartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Bedtime to wake-up time over the last 7 days'**
  String get sleepScheduleChartSubtitle;

  /// No description provided for @sleepScheduleNoTimes.
  ///
  /// In en, this message translates to:
  /// **'Add bedtime and wake-up times to see your weekly schedule.'**
  String get sleepScheduleNoTimes;

  /// No description provided for @sleepScheduleSemantics.
  ///
  /// In en, this message translates to:
  /// **'Weekly sleep schedule with {count} nights'**
  String sleepScheduleSemantics(Object count);

  /// No description provided for @sleepDurationChart.
  ///
  /// In en, this message translates to:
  /// **'Sleep duration'**
  String get sleepDurationChart;

  /// No description provided for @sleepDurationChartSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Recorded and actual or estimated sleep by night'**
  String get sleepDurationChartSubtitle;

  /// No description provided for @sleepChartActualOrEstimated.
  ///
  /// In en, this message translates to:
  /// **'Actual / estimated'**
  String get sleepChartActualOrEstimated;

  /// No description provided for @sleepDurationChartSemantics.
  ///
  /// In en, this message translates to:
  /// **'Weekly chart comparing recorded and actual or estimated sleep duration'**
  String get sleepDurationChartSemantics;

  /// No description provided for @sleepPreviousWeek.
  ///
  /// In en, this message translates to:
  /// **'Previous week'**
  String get sleepPreviousWeek;

  /// No description provided for @sleepNextWeek.
  ///
  /// In en, this message translates to:
  /// **'Next week'**
  String get sleepNextWeek;

  /// No description provided for @sleepNoRecordForDay.
  ///
  /// In en, this message translates to:
  /// **'No sleep record for this day'**
  String get sleepNoRecordForDay;

  /// No description provided for @sleepMonitorCta.
  ///
  /// In en, this message translates to:
  /// **'Monitor sleep'**
  String get sleepMonitorCta;

  /// No description provided for @sleepMonitorCtaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Analyze quiet and noise locally during the night.'**
  String get sleepMonitorCtaSubtitle;

  /// No description provided for @sleepMonitorOpenActive.
  ///
  /// In en, this message translates to:
  /// **'Monitoring in progress'**
  String get sleepMonitorOpenActive;

  /// No description provided for @sleepMonitorRecovered.
  ///
  /// In en, this message translates to:
  /// **'{count} monitoring session(s) recovered.'**
  String sleepMonitorRecovered(Object count);

  /// No description provided for @sleepMonitorTitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor sleep'**
  String get sleepMonitorTitle;

  /// No description provided for @sleepMonitorAndroidOnly.
  ///
  /// In en, this message translates to:
  /// **'Monitoring is available only on Android.'**
  String get sleepMonitorAndroidOnly;

  /// No description provided for @sleepMonitorRunning.
  ///
  /// In en, this message translates to:
  /// **'Monitoring in progress'**
  String get sleepMonitorRunning;

  /// No description provided for @sleepMonitorReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to monitor'**
  String get sleepMonitorReady;

  /// No description provided for @sleepMonitorMicrophone.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission'**
  String get sleepMonitorMicrophone;

  /// No description provided for @sleepMonitorStart.
  ///
  /// In en, this message translates to:
  /// **'Start monitoring'**
  String get sleepMonitorStart;

  /// No description provided for @sleepMonitorStartWithAlarm.
  ///
  /// In en, this message translates to:
  /// **'Start and wake at {time}'**
  String sleepMonitorStartWithAlarm(String time);

  /// No description provided for @sleepMonitorFinish.
  ///
  /// In en, this message translates to:
  /// **'Finish and view result'**
  String get sleepMonitorFinish;

  /// No description provided for @sleepMonitorDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard session'**
  String get sleepMonitorDiscard;

  /// No description provided for @sleepMonitorLocalProcessing.
  ///
  /// In en, this message translates to:
  /// **'Audio is processed locally and never recorded. Only aggregate metrics are kept.'**
  String get sleepMonitorLocalProcessing;

  /// No description provided for @sleepMonitorEstimateWarning.
  ///
  /// In en, this message translates to:
  /// **'Results are environment-based estimates and are not medical measurements. Quiet does not necessarily mean you were asleep.'**
  String get sleepMonitorEstimateWarning;

  /// No description provided for @sleepMonitorMicrophoneDenied.
  ///
  /// In en, this message translates to:
  /// **'Microphone permission is required to monitor this night.'**
  String get sleepMonitorMicrophoneDenied;

  /// No description provided for @sleepMonitorNotificationsLimited.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled; the service may be less visible while the screen is locked.'**
  String get sleepMonitorNotificationsLimited;

  /// No description provided for @sleepMonitorAudioUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The microphone could not be accessed. Check whether another app is using it.'**
  String get sleepMonitorAudioUnavailable;

  /// No description provided for @sleepMonitorAlreadyActive.
  ///
  /// In en, this message translates to:
  /// **'A monitoring session is already active.'**
  String get sleepMonitorAlreadyActive;

  /// No description provided for @sleepMonitorImportError.
  ///
  /// In en, this message translates to:
  /// **'The session could not be imported. It will be kept for another attempt.'**
  String get sleepMonitorImportError;

  /// No description provided for @sleepMonitorGenericError.
  ///
  /// In en, this message translates to:
  /// **'The monitoring session could not be started or finished.'**
  String get sleepMonitorGenericError;

  /// No description provided for @sleepMonitorWaitingSignal.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the first signal segment'**
  String get sleepMonitorWaitingSignal;

  /// No description provided for @sleepMonitorNoiseNow.
  ///
  /// In en, this message translates to:
  /// **'Relative noise detected'**
  String get sleepMonitorNoiseNow;

  /// No description provided for @sleepMonitorQuietNow.
  ///
  /// In en, this message translates to:
  /// **'Estimated quiet period'**
  String get sleepMonitorQuietNow;

  /// No description provided for @sleepMonitorInvalidSignal.
  ///
  /// In en, this message translates to:
  /// **'Signal temporarily unavailable'**
  String get sleepMonitorInvalidSignal;

  /// No description provided for @sleepAlarmSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Your wake-up time'**
  String get sleepAlarmSectionTitle;

  /// No description provided for @sleepAlarmTapToChange.
  ///
  /// In en, this message translates to:
  /// **'Tap the clock to change'**
  String get sleepAlarmTapToChange;

  /// No description provided for @sleepAlarmNext.
  ///
  /// In en, this message translates to:
  /// **'Next alarm'**
  String get sleepAlarmNext;

  /// No description provided for @sleepAlarmIn.
  ///
  /// In en, this message translates to:
  /// **'in {duration}'**
  String sleepAlarmIn(String duration);

  /// No description provided for @sleepAlarmSystemSound.
  ///
  /// In en, this message translates to:
  /// **'System alarm sound + vibration'**
  String get sleepAlarmSystemSound;

  /// No description provided for @sleepAlarmSystemSoundBody.
  ///
  /// In en, this message translates to:
  /// **'Uses your device\'s alarm volume and Do Not Disturb settings.'**
  String get sleepAlarmSystemSoundBody;

  /// No description provided for @sleepAlarmPreparation.
  ///
  /// In en, this message translates to:
  /// **'Prepare your phone'**
  String get sleepAlarmPreparation;

  /// No description provided for @sleepAlarmPreparationBody.
  ///
  /// In en, this message translates to:
  /// **'Leave it charging near the bed, with the microphone unobstructed.'**
  String get sleepAlarmPreparationBody;

  /// No description provided for @sleepAlarmScheduledFor.
  ///
  /// In en, this message translates to:
  /// **'Alarm set for {time}'**
  String sleepAlarmScheduledFor(String time);

  /// No description provided for @sleepAlarmRemaining.
  ///
  /// In en, this message translates to:
  /// **'Time until alarm'**
  String get sleepAlarmRemaining;

  /// No description provided for @sleepAlarmChange.
  ///
  /// In en, this message translates to:
  /// **'Change alarm'**
  String get sleepAlarmChange;

  /// No description provided for @sleepAlarmInvalidWindow.
  ///
  /// In en, this message translates to:
  /// **'Choose a time between 1 minute and 16 hours from now.'**
  String get sleepAlarmInvalidWindow;

  /// No description provided for @sleepAlarmExactPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow Alarms & reminders so the alarm can ring exactly on time.'**
  String get sleepAlarmExactPermission;

  /// No description provided for @sleepAlarmEnableExactPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow exact alarms'**
  String get sleepAlarmEnableExactPermission;

  /// No description provided for @sleepAlarmNotificationRequired.
  ///
  /// In en, this message translates to:
  /// **'Notifications are required to show and dismiss the wake-up alarm.'**
  String get sleepAlarmNotificationRequired;

  /// No description provided for @sleepAlarmFullScreenLimited.
  ///
  /// In en, this message translates to:
  /// **'Full-screen alarms are disabled. Sound and vibration will still use a highlighted notification.'**
  String get sleepAlarmFullScreenLimited;

  /// No description provided for @sleepAlarmEnableFullScreen.
  ///
  /// In en, this message translates to:
  /// **'Allow full-screen alarm'**
  String get sleepAlarmEnableFullScreen;

  /// No description provided for @sleepAlarmScheduleFailed.
  ///
  /// In en, this message translates to:
  /// **'The wake-up alarm could not be scheduled.'**
  String get sleepAlarmScheduleFailed;

  /// No description provided for @sleepMonitorResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Monitoring result'**
  String get sleepMonitorResultTitle;

  /// No description provided for @sleepMonitorResultMissing.
  ///
  /// In en, this message translates to:
  /// **'Result not found.'**
  String get sleepMonitorResultMissing;

  /// No description provided for @sleepMonitorSource.
  ///
  /// In en, this message translates to:
  /// **'Monitoring'**
  String get sleepMonitorSource;

  /// No description provided for @sleepMonitorTimeline.
  ///
  /// In en, this message translates to:
  /// **'Night timeline'**
  String get sleepMonitorTimeline;

  /// No description provided for @sleepMonitorTimeMonitored.
  ///
  /// In en, this message translates to:
  /// **'Time monitored'**
  String get sleepMonitorTimeMonitored;

  /// No description provided for @sleepMonitorQuietPeriod.
  ///
  /// In en, this message translates to:
  /// **'Quiet period'**
  String get sleepMonitorQuietPeriod;

  /// No description provided for @sleepMonitorNoisyPeriod.
  ///
  /// In en, this message translates to:
  /// **'Noisy period'**
  String get sleepMonitorNoisyPeriod;

  /// No description provided for @sleepMonitorNoiseEvents.
  ///
  /// In en, this message translates to:
  /// **'Noise events'**
  String get sleepMonitorNoiseEvents;

  /// No description provided for @sleepMonitorSignalCoverage.
  ///
  /// In en, this message translates to:
  /// **'Signal coverage'**
  String get sleepMonitorSignalCoverage;

  /// No description provided for @sleepMonitorQuiet.
  ///
  /// In en, this message translates to:
  /// **'Relative quiet'**
  String get sleepMonitorQuiet;

  /// No description provided for @sleepMonitorNoise.
  ///
  /// In en, this message translates to:
  /// **'Relative noise'**
  String get sleepMonitorNoise;

  /// No description provided for @sleepMonitorInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid signal'**
  String get sleepMonitorInvalid;

  /// No description provided for @sleepMonitorDataQuality.
  ///
  /// In en, this message translates to:
  /// **'MVP data quality'**
  String get sleepMonitorDataQuality;

  /// No description provided for @sleepMonitorDataAcceptable.
  ///
  /// In en, this message translates to:
  /// **'Night suitable for the next MVP phase'**
  String get sleepMonitorDataAcceptable;

  /// No description provided for @sleepMonitorDataAcceptableBody.
  ///
  /// In en, this message translates to:
  /// **'Duration and capture coverage are sufficient for evaluating the current monitor.'**
  String get sleepMonitorDataAcceptableBody;

  /// No description provided for @sleepMonitorDataInsufficient.
  ///
  /// In en, this message translates to:
  /// **'Night needs another monitoring round'**
  String get sleepMonitorDataInsufficient;

  /// No description provided for @sleepMonitorDataInsufficientBody.
  ///
  /// In en, this message translates to:
  /// **'For the next phase, record at least 4 hours with 90% timeline coverage and 80% valid signal.'**
  String get sleepMonitorDataInsufficientBody;

  /// No description provided for @sleepMonitorCapturedSegments.
  ///
  /// In en, this message translates to:
  /// **'Captured segments'**
  String get sleepMonitorCapturedSegments;

  /// No description provided for @sleepMonitorTimelineCoverage.
  ///
  /// In en, this message translates to:
  /// **'Timeline coverage'**
  String get sleepMonitorTimelineCoverage;

  /// No description provided for @sleepMonitorNoiseGraph.
  ///
  /// In en, this message translates to:
  /// **'Relative noise through the night'**
  String get sleepMonitorNoiseGraph;

  /// No description provided for @sleepMonitorNoiseScore.
  ///
  /// In en, this message translates to:
  /// **'Noise score'**
  String get sleepMonitorNoiseScore;

  /// No description provided for @sleepMonitorNoSegments.
  ///
  /// In en, this message translates to:
  /// **'No signal segments were recorded'**
  String get sleepMonitorNoSegments;

  /// No description provided for @sleepMonitorNoSegmentsBody.
  ///
  /// In en, this message translates to:
  /// **'This session cannot evaluate the MVP. The monitor will now stop with an error if the microphone stops returning data, instead of completing an empty night.'**
  String get sleepMonitorNoSegmentsBody;

  /// No description provided for @sleepMonitorAverageNoise.
  ///
  /// In en, this message translates to:
  /// **'Average noise score'**
  String get sleepMonitorAverageNoise;

  /// No description provided for @sleepMonitorPeakNoise.
  ///
  /// In en, this message translates to:
  /// **'Peak noise score'**
  String get sleepMonitorPeakNoise;

  /// No description provided for @sleepMonitorStartTime.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get sleepMonitorStartTime;

  /// No description provided for @sleepMonitorEndTime.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get sleepMonitorEndTime;

  /// No description provided for @sleepMonitorThreshold.
  ///
  /// In en, this message translates to:
  /// **'Noise threshold'**
  String get sleepMonitorThreshold;

  /// No description provided for @sleepMonitorExportDiagnostic.
  ///
  /// In en, this message translates to:
  /// **'Export diagnostic'**
  String get sleepMonitorExportDiagnostic;

  /// No description provided for @sleepMonitorExportDiagnosticTitle.
  ///
  /// In en, this message translates to:
  /// **'What should be included?'**
  String get sleepMonitorExportDiagnosticTitle;

  /// No description provided for @sleepMonitorExportDiagnosticBody.
  ///
  /// In en, this message translates to:
  /// **'The JSON file can be shared for technical analysis. Raw audio is never stored and cannot be exported.'**
  String get sleepMonitorExportDiagnosticBody;

  /// No description provided for @sleepMonitorExportTechnicalOnly.
  ///
  /// In en, this message translates to:
  /// **'Technical data only (recommended)'**
  String get sleepMonitorExportTechnicalOnly;

  /// No description provided for @sleepMonitorExportTechnicalOnlyBody.
  ///
  /// In en, this message translates to:
  /// **'Uses relative times and excludes the sleep date, exact timestamps, local IDs and your note.'**
  String get sleepMonitorExportTechnicalOnlyBody;

  /// No description provided for @sleepMonitorExportWithPersonal.
  ///
  /// In en, this message translates to:
  /// **'Include personal sleep data'**
  String get sleepMonitorExportWithPersonal;

  /// No description provided for @sleepMonitorExportWithPersonalBody.
  ///
  /// In en, this message translates to:
  /// **'Also includes exact date and time, local IDs, recorded durations and your personal sleep comment.'**
  String get sleepMonitorExportWithPersonalBody;

  /// No description provided for @sleepMonitorExportConfirm.
  ///
  /// In en, this message translates to:
  /// **'Generate and share'**
  String get sleepMonitorExportConfirm;

  /// No description provided for @sleepMonitorExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic generated. Choose where to share or save it.'**
  String get sleepMonitorExportSuccess;

  /// No description provided for @sleepMonitorExportError.
  ///
  /// In en, this message translates to:
  /// **'The diagnostic file could not be generated.'**
  String get sleepMonitorExportError;

  /// No description provided for @sleepMonitorTimeInBed.
  ///
  /// In en, this message translates to:
  /// **'Time in bed'**
  String get sleepMonitorTimeInBed;

  /// No description provided for @sleepMonitorDeleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get sleepMonitorDeleteSession;

  /// No description provided for @sleepMonitorDeleteSessionBody.
  ///
  /// In en, this message translates to:
  /// **'The metrics and timeline for this session will be deleted. The sleep record remains.'**
  String get sleepMonitorDeleteSessionBody;

  /// No description provided for @sleepMonitorDiscardTitle.
  ///
  /// In en, this message translates to:
  /// **'Discard session?'**
  String get sleepMonitorDiscardTitle;

  /// No description provided for @sleepMonitorDiscardBody.
  ///
  /// In en, this message translates to:
  /// **'The active session and its metrics will be deleted.'**
  String get sleepMonitorDiscardBody;

  /// No description provided for @sleepMonitorDigitalSilence.
  ///
  /// In en, this message translates to:
  /// **'Digital silence'**
  String get sleepMonitorDigitalSilence;

  /// No description provided for @sleepInferenceTitle.
  ///
  /// In en, this message translates to:
  /// **'Night analysis'**
  String get sleepInferenceTitle;

  /// No description provided for @sleepInferenceSleptAt.
  ///
  /// In en, this message translates to:
  /// **'Fell asleep'**
  String get sleepInferenceSleptAt;

  /// No description provided for @sleepInferenceOnsetUnknown.
  ///
  /// In en, this message translates to:
  /// **'Onset not identified'**
  String get sleepInferenceOnsetUnknown;

  /// No description provided for @sleepInferencePreparation.
  ///
  /// In en, this message translates to:
  /// **'Preparation'**
  String get sleepInferencePreparation;

  /// No description provided for @sleepInferenceSettling.
  ///
  /// In en, this message translates to:
  /// **'Settling'**
  String get sleepInferenceSettling;

  /// No description provided for @sleepInferenceAwakenings.
  ///
  /// In en, this message translates to:
  /// **'Woke up'**
  String get sleepInferenceAwakenings;

  /// No description provided for @sleepInferenceEstimatedSleep.
  ///
  /// In en, this message translates to:
  /// **'Estimated sleep'**
  String get sleepInferenceEstimatedSleep;

  /// No description provided for @sleepInferenceConfidence.
  ///
  /// In en, this message translates to:
  /// **'Confidence'**
  String get sleepInferenceConfidence;

  /// No description provided for @sleepInferenceConfidenceLow.
  ///
  /// In en, this message translates to:
  /// **'low'**
  String get sleepInferenceConfidenceLow;

  /// No description provided for @sleepInferenceConfidenceMedium.
  ///
  /// In en, this message translates to:
  /// **'medium'**
  String get sleepInferenceConfidenceMedium;

  /// No description provided for @sleepInferenceInsufficient.
  ///
  /// In en, this message translates to:
  /// **'This night\'s data is not sufficient to calculate sleep onset and awakenings safely.'**
  String get sleepInferenceInsufficient;

  /// No description provided for @sleepInferenceEventsTitle.
  ///
  /// In en, this message translates to:
  /// **'Night events'**
  String get sleepInferenceEventsTitle;

  /// No description provided for @sleepInferencePeak.
  ///
  /// In en, this message translates to:
  /// **'peak'**
  String get sleepInferencePeak;

  /// No description provided for @sleepInferenceEventTransient.
  ///
  /// In en, this message translates to:
  /// **'Transient activity'**
  String get sleepInferenceEventTransient;

  /// No description provided for @sleepInferenceEventProlonged.
  ///
  /// In en, this message translates to:
  /// **'Prolonged activity'**
  String get sleepInferenceEventProlonged;

  /// No description provided for @sleepInferenceEventAwakening.
  ///
  /// In en, this message translates to:
  /// **'Awakening'**
  String get sleepInferenceEventAwakening;

  /// No description provided for @sleepInferenceEventFinalActivity.
  ///
  /// In en, this message translates to:
  /// **'Activity before monitoring ended'**
  String get sleepInferenceEventFinalActivity;

  /// No description provided for @sleepInferenceReasonShort.
  ///
  /// In en, this message translates to:
  /// **'Short peak without enough duration to indicate an awakening.'**
  String get sleepInferenceReasonShort;

  /// No description provided for @sleepInferenceReasonSustained.
  ///
  /// In en, this message translates to:
  /// **'Sustained sound activity without a quiet recovery that indicates an awakening.'**
  String get sleepInferenceReasonSustained;

  /// No description provided for @sleepInferenceReasonAwakening.
  ///
  /// In en, this message translates to:
  /// **'Sustained activity followed by a return to quiet.'**
  String get sleepInferenceReasonAwakening;

  /// No description provided for @sleepInferenceReasonFinal.
  ///
  /// In en, this message translates to:
  /// **'Sustained activity during the final ten minutes.'**
  String get sleepInferenceReasonFinal;

  /// No description provided for @sleepInferenceBlockerTooShort.
  ///
  /// In en, this message translates to:
  /// **'Record at least four hours in a completed session.'**
  String get sleepInferenceBlockerTooShort;

  /// No description provided for @sleepInferenceBlockerLowTimelineCoverage.
  ///
  /// In en, this message translates to:
  /// **'Timeline coverage was below 90%.'**
  String get sleepInferenceBlockerLowTimelineCoverage;

  /// No description provided for @sleepInferenceBlockerLowSignalCoverage.
  ///
  /// In en, this message translates to:
  /// **'Valid signal coverage was below 80%.'**
  String get sleepInferenceBlockerLowSignalCoverage;

  /// No description provided for @sleepInferenceBlockerInvalidSegments.
  ///
  /// In en, this message translates to:
  /// **'More than 20% of the period contains invalid signal.'**
  String get sleepInferenceBlockerInvalidSegments;

  /// No description provided for @sleepInferenceBlockerDigitalSilence.
  ///
  /// In en, this message translates to:
  /// **'More than 20% of the period contains digital microphone silence.'**
  String get sleepInferenceBlockerDigitalSilence;

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
  /// **'Adds fictional workouts, measurements, and sleep to test the app'**
  String get settingsGenerateTestDataSubtitle;

  /// No description provided for @settingsGenerateTitle.
  ///
  /// In en, this message translates to:
  /// **'Generate Test Data?'**
  String get settingsGenerateTitle;

  /// No description provided for @settingsGenerateContent.
  ///
  /// In en, this message translates to:
  /// **'This will add fictional workouts, body measurements, and sleep records from recent months to test charts and features.\n\nUse \"Delete All History\" to remove them later.'**
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

  /// No description provided for @settingsGenerateSuccessDetailed.
  ///
  /// In en, this message translates to:
  /// **'✅ {workouts} workouts, {routines} routines, and {sleep} sleep nights generated!'**
  String settingsGenerateSuccessDetailed(
    Object routines,
    Object sleep,
    Object workouts,
  );

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

  /// No description provided for @settingsExportOptionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Export backup'**
  String get settingsExportOptionsTitle;

  /// No description provided for @settingsExportShareOption.
  ///
  /// In en, this message translates to:
  /// **'Share file'**
  String get settingsExportShareOption;

  /// No description provided for @settingsExportShareSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the system share sheet'**
  String get settingsExportShareSubtitle;

  /// No description provided for @settingsExportSaveOption.
  ///
  /// In en, this message translates to:
  /// **'Save on device'**
  String get settingsExportSaveOption;

  /// No description provided for @settingsExportSaveSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose Downloads, Drive, or another location'**
  String get settingsExportSaveSubtitle;

  /// No description provided for @settingsExportSaveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Save JSON backup'**
  String get settingsExportSaveDialogTitle;

  /// No description provided for @settingsExportSaveSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup saved successfully!\n{path}'**
  String settingsExportSaveSuccess(Object path);

  /// No description provided for @settingsExportSaveError.
  ///
  /// In en, this message translates to:
  /// **'Could not save backup: {error}'**
  String settingsExportSaveError(Object error);

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

  /// No description provided for @settingsImportLocalOption.
  ///
  /// In en, this message translates to:
  /// **'Backups saved on this device'**
  String get settingsImportLocalOption;

  /// No description provided for @settingsImportPickFileOption.
  ///
  /// In en, this message translates to:
  /// **'Select file from device'**
  String get settingsImportPickFileOption;

  /// No description provided for @settingsImportPickFileSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose a .json backup from Downloads, Drive, or storage'**
  String get settingsImportPickFileSubtitle;

  /// No description provided for @settingsImportPickerError.
  ///
  /// In en, this message translates to:
  /// **'Could not open the file picker: {error}'**
  String settingsImportPickerError(Object error);

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

  /// No description provided for @routinesEstimatedDuration.
  ///
  /// In en, this message translates to:
  /// **'Estimated time: {duration}'**
  String routinesEstimatedDuration(Object duration);

  /// No description provided for @workoutEstimatedCalories.
  ///
  /// In en, this message translates to:
  /// **'Estimated calories'**
  String get workoutEstimatedCalories;

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

  /// No description provided for @exerciseFormSectionBasic.
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get exerciseFormSectionBasic;

  /// No description provided for @exerciseFormSectionDefaults.
  ///
  /// In en, this message translates to:
  /// **'Defaults'**
  String get exerciseFormSectionDefaults;

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

  /// No description provided for @activeWorkoutCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get activeWorkoutCurrent;

  /// No description provided for @activeWorkoutLast.
  ///
  /// In en, this message translates to:
  /// **'Last'**
  String get activeWorkoutLast;

  /// No description provided for @activeWorkoutByMuscleGroup.
  ///
  /// In en, this message translates to:
  /// **'By muscle group'**
  String get activeWorkoutByMuscleGroup;

  /// No description provided for @workoutStatsDensity.
  ///
  /// In en, this message translates to:
  /// **'Density'**
  String get workoutStatsDensity;

  /// No description provided for @workoutStatsKgPerMin.
  ///
  /// In en, this message translates to:
  /// **'kg/min'**
  String get workoutStatsKgPerMin;

  /// No description provided for @workoutStatsEvolution.
  ///
  /// In en, this message translates to:
  /// **'Evolution'**
  String get workoutStatsEvolution;

  /// No description provided for @workoutStatsHighlights.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get workoutStatsHighlights;

  /// No description provided for @workoutStatsTopSet.
  ///
  /// In en, this message translates to:
  /// **'Top set'**
  String get workoutStatsTopSet;

  /// No description provided for @workoutStatsHighestVolume.
  ///
  /// In en, this message translates to:
  /// **'Highest volume'**
  String get workoutStatsHighestVolume;

  /// No description provided for @workoutStatsAverageRpe.
  ///
  /// In en, this message translates to:
  /// **'Average RPE'**
  String get workoutStatsAverageRpe;

  /// No description provided for @workoutStatsVsSimilarWorkout.
  ///
  /// In en, this message translates to:
  /// **'vs similar workout'**
  String get workoutStatsVsSimilarWorkout;

  /// No description provided for @workoutStatsMuscleVolume.
  ///
  /// In en, this message translates to:
  /// **'Muscle volume'**
  String get workoutStatsMuscleVolume;

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

  /// No description provided for @notificationRestTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Rest'**
  String get notificationRestTimerTitle;

  /// No description provided for @notificationRestCompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Rest Complete'**
  String get notificationRestCompleteTitle;

  /// No description provided for @notificationRestCompleteBody.
  ///
  /// In en, this message translates to:
  /// **'Rest time is over - time for the next set!'**
  String get notificationRestCompleteBody;

  /// No description provided for @notificationWorkoutTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Active workout'**
  String get notificationWorkoutTimerTitle;

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

  /// No description provided for @aiCoachSection.
  ///
  /// In en, this message translates to:
  /// **'AI COACH'**
  String get aiCoachSection;

  /// No description provided for @aiCoachEntry.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get aiCoachEntry;

  /// No description provided for @aiCoachEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Chat with a personal-trainer AI.'**
  String get aiCoachEntrySubtitle;

  /// No description provided for @aiCoachConfigureEntry.
  ///
  /// In en, this message translates to:
  /// **'Configure AI'**
  String get aiCoachConfigureEntry;

  /// No description provided for @aiCoachConfigureEntrySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Providers, model, system prompt.'**
  String get aiCoachConfigureEntrySubtitle;

  /// No description provided for @aiChatTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Coach'**
  String get aiChatTitle;

  /// No description provided for @aiChatInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask your trainer something…'**
  String get aiChatInputHint;

  /// No description provided for @aiChatInputHintDisabled.
  ///
  /// In en, this message translates to:
  /// **'Configure a provider to start'**
  String get aiChatInputHintDisabled;

  /// No description provided for @aiChatNewChat.
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get aiChatNewChat;

  /// No description provided for @aiChatHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get aiChatHistory;

  /// No description provided for @aiChatSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get aiChatSettings;

  /// No description provided for @aiChatChooseProvider.
  ///
  /// In en, this message translates to:
  /// **'Switch provider'**
  String get aiChatChooseProvider;

  /// No description provided for @aiChatRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get aiChatRetry;

  /// No description provided for @aiChatCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get aiChatCopy;

  /// No description provided for @aiChatCopied.
  ///
  /// In en, this message translates to:
  /// **'Message copied'**
  String get aiChatCopied;

  /// No description provided for @aiChatErrorGeneric.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong.'**
  String get aiChatErrorGeneric;

  /// No description provided for @aiChatErrorTimeout.
  ///
  /// In en, this message translates to:
  /// **'The AI took too long to respond.'**
  String get aiChatErrorTimeout;

  /// No description provided for @aiChatErrorNoProvider.
  ///
  /// In en, this message translates to:
  /// **'No AI provider configured.'**
  String get aiChatErrorNoProvider;

  /// No description provided for @aiChatErrorInvalidToken.
  ///
  /// In en, this message translates to:
  /// **'Invalid or missing API token.'**
  String get aiChatErrorInvalidToken;

  /// No description provided for @aiChatErrorMissingModel.
  ///
  /// In en, this message translates to:
  /// **'Select a model in Settings → AI Coach.'**
  String get aiChatErrorMissingModel;

  /// No description provided for @aiChatErrorNotFound.
  ///
  /// In en, this message translates to:
  /// **'Model or endpoint not found.'**
  String get aiChatErrorNotFound;

  /// No description provided for @aiChatErrorInvalidResponse.
  ///
  /// In en, this message translates to:
  /// **'The AI provider returned an invalid response.'**
  String get aiChatErrorInvalidResponse;

  /// No description provided for @aiChatErrorRequest.
  ///
  /// In en, this message translates to:
  /// **'The request to the AI could not be completed.'**
  String get aiChatErrorRequest;

  /// No description provided for @aiChatErrorUserMessage.
  ///
  /// In en, this message translates to:
  /// **'The user message could not be found.'**
  String get aiChatErrorUserMessage;

  /// No description provided for @aiChatProcessing.
  ///
  /// In en, this message translates to:
  /// **'Processing…'**
  String get aiChatProcessing;

  /// No description provided for @aiChatWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Hi! I\'m your AI Coach.'**
  String get aiChatWelcomeTitle;

  /// No description provided for @aiChatWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Ask about your progress, request a workout analysis, or ask for progression suggestions.'**
  String get aiChatWelcomeSubtitle;

  /// No description provided for @aiChatSending.
  ///
  /// In en, this message translates to:
  /// **'Sending…'**
  String get aiChatSending;

  /// No description provided for @aiChatReading.
  ///
  /// In en, this message translates to:
  /// **'Reading {count} source(s)…'**
  String aiChatReading(Object count);

  /// No description provided for @aiChatFinalising.
  ///
  /// In en, this message translates to:
  /// **'Finalising…'**
  String get aiChatFinalising;

  /// No description provided for @aiChatActiveModel.
  ///
  /// In en, this message translates to:
  /// **'{provider} • {model}'**
  String aiChatActiveModel(Object model, Object provider);

  /// No description provided for @aiChatNoModel.
  ///
  /// In en, this message translates to:
  /// **'{provider} • (no model)'**
  String aiChatNoModel(Object provider);

  /// No description provided for @aiToolApplied.
  ///
  /// In en, this message translates to:
  /// **'Tool applied'**
  String get aiToolApplied;

  /// No description provided for @aiToolNoContent.
  ///
  /// In en, this message translates to:
  /// **'(no content)'**
  String get aiToolNoContent;

  /// No description provided for @aiToolError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get aiToolError;

  /// No description provided for @aiToolUnknown.
  ///
  /// In en, this message translates to:
  /// **'unknown'**
  String get aiToolUnknown;

  /// No description provided for @aiToolListRecentWorkouts.
  ///
  /// In en, this message translates to:
  /// **'Listing recent workouts'**
  String get aiToolListRecentWorkouts;

  /// No description provided for @aiToolGetWorkoutDetail.
  ///
  /// In en, this message translates to:
  /// **'Loading workout details'**
  String get aiToolGetWorkoutDetail;

  /// No description provided for @aiToolListExercises.
  ///
  /// In en, this message translates to:
  /// **'Searching exercises'**
  String get aiToolListExercises;

  /// No description provided for @aiToolGetExerciseHistory.
  ///
  /// In en, this message translates to:
  /// **'Exercise history'**
  String get aiToolGetExerciseHistory;

  /// No description provided for @aiToolGetExerciseRecords.
  ///
  /// In en, this message translates to:
  /// **'Personal records'**
  String get aiToolGetExerciseRecords;

  /// No description provided for @aiToolWeeklyVolume.
  ///
  /// In en, this message translates to:
  /// **'Weekly volume'**
  String get aiToolWeeklyVolume;

  /// No description provided for @aiToolProgressTrend.
  ///
  /// In en, this message translates to:
  /// **'Progress trend'**
  String get aiToolProgressTrend;

  /// No description provided for @aiToolListRoutines.
  ///
  /// In en, this message translates to:
  /// **'Listing routines'**
  String get aiToolListRoutines;

  /// No description provided for @aiToolGetRoutineDetail.
  ///
  /// In en, this message translates to:
  /// **'Loading routine details'**
  String get aiToolGetRoutineDetail;

  /// No description provided for @aiToolBodyMeasurements.
  ///
  /// In en, this message translates to:
  /// **'Body measurements'**
  String get aiToolBodyMeasurements;

  /// No description provided for @aiToolCardioSummary.
  ///
  /// In en, this message translates to:
  /// **'Cardio summary'**
  String get aiToolCardioSummary;

  /// No description provided for @aiToolListGoals.
  ///
  /// In en, this message translates to:
  /// **'Active goals'**
  String get aiToolListGoals;

  /// No description provided for @aiToolGoalHistory.
  ///
  /// In en, this message translates to:
  /// **'Goal history'**
  String get aiToolGoalHistory;

  /// No description provided for @aiToolProposeRoutineChange.
  ///
  /// In en, this message translates to:
  /// **'Preparing routine proposal'**
  String get aiToolProposeRoutineChange;

  /// No description provided for @aiChatPreparingProposal.
  ///
  /// In en, this message translates to:
  /// **'Preparing routine preview…'**
  String get aiChatPreparingProposal;

  /// No description provided for @aiChatApplyingProposal.
  ///
  /// In en, this message translates to:
  /// **'Applying approved changes…'**
  String get aiChatApplyingProposal;

  /// No description provided for @aiRoutineProposalCreate.
  ///
  /// In en, this message translates to:
  /// **'New routine'**
  String get aiRoutineProposalCreate;

  /// No description provided for @aiRoutineProposalUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update routine'**
  String get aiRoutineProposalUpdate;

  /// No description provided for @aiRoutineProposalAwaiting.
  ///
  /// In en, this message translates to:
  /// **'Awaiting approval'**
  String get aiRoutineProposalAwaiting;

  /// No description provided for @aiRoutineProposalApplying.
  ///
  /// In en, this message translates to:
  /// **'Applying'**
  String get aiRoutineProposalApplying;

  /// No description provided for @aiRoutineProposalApplied.
  ///
  /// In en, this message translates to:
  /// **'Applied'**
  String get aiRoutineProposalApplied;

  /// No description provided for @aiRoutineProposalRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get aiRoutineProposalRejected;

  /// No description provided for @aiRoutineProposalStale.
  ///
  /// In en, this message translates to:
  /// **'Outdated'**
  String get aiRoutineProposalStale;

  /// No description provided for @aiRoutineProposalFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get aiRoutineProposalFailed;

  /// No description provided for @aiRoutineProposalPreview.
  ///
  /// In en, this message translates to:
  /// **'Review the changes before applying them.'**
  String get aiRoutineProposalPreview;

  /// No description provided for @aiRoutineProposalApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve and apply'**
  String get aiRoutineProposalApprove;

  /// No description provided for @aiRoutineProposalReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get aiRoutineProposalReject;

  /// No description provided for @aiRoutineProposalView.
  ///
  /// In en, this message translates to:
  /// **'View routine'**
  String get aiRoutineProposalView;

  /// No description provided for @aiRoutineProposalDetails.
  ///
  /// In en, this message translates to:
  /// **'View details'**
  String get aiRoutineProposalDetails;

  /// No description provided for @aiRoutineProposalHideDetails.
  ///
  /// In en, this message translates to:
  /// **'Hide details'**
  String get aiRoutineProposalHideDetails;

  /// No description provided for @aiRoutineProposalAdded.
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get aiRoutineProposalAdded;

  /// No description provided for @aiRoutineProposalRemoved.
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get aiRoutineProposalRemoved;

  /// No description provided for @aiRoutineProposalChanges.
  ///
  /// In en, this message translates to:
  /// **'Proposed changes'**
  String get aiRoutineProposalChanges;

  /// No description provided for @aiRoutineProposalRemovalWarning.
  ///
  /// In en, this message translates to:
  /// **'This proposal removes {count} item(s).'**
  String aiRoutineProposalRemovalWarning(Object count);

  /// No description provided for @aiRoutineProposalConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Apply removals?'**
  String get aiRoutineProposalConfirmTitle;

  /// No description provided for @aiRoutineProposalConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'{count} item(s) will be removed from the routine. This cannot be undone automatically.'**
  String aiRoutineProposalConfirmBody(Object count);

  /// No description provided for @aiRoutineProposalConfirmApply.
  ///
  /// In en, this message translates to:
  /// **'Apply changes'**
  String get aiRoutineProposalConfirmApply;

  /// No description provided for @aiRoutineProposalStaleBody.
  ///
  /// In en, this message translates to:
  /// **'The routine changed since this preview. Ask the AI to create a new proposal.'**
  String get aiRoutineProposalStaleBody;

  /// No description provided for @aiRoutineProposalRejectedBody.
  ///
  /// In en, this message translates to:
  /// **'No changes were applied.'**
  String get aiRoutineProposalRejectedBody;

  /// No description provided for @aiRoutineProposalAppliedBody.
  ///
  /// In en, this message translates to:
  /// **'Changes were applied successfully.'**
  String get aiRoutineProposalAppliedBody;

  /// No description provided for @aiRoutineProposalRetrySummary.
  ///
  /// In en, this message translates to:
  /// **'Generate summary'**
  String get aiRoutineProposalRetrySummary;

  /// No description provided for @aiProviderPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'Provider and model'**
  String get aiProviderPickerTitle;

  /// No description provided for @aiProviderPickerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search model'**
  String get aiProviderPickerSearch;

  /// No description provided for @aiHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Conversation history'**
  String get aiHistoryTitle;

  /// No description provided for @aiHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No conversations yet'**
  String get aiHistoryEmpty;

  /// No description provided for @aiHistoryEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation in the AI Coach chat.'**
  String get aiHistoryEmptySubtitle;

  /// No description provided for @aiHistoryDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete conversation?'**
  String get aiHistoryDeleteTitle;

  /// No description provided for @aiHistoryDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone. \"{title}\" will be removed.'**
  String aiHistoryDeleteBody(Object title);

  /// No description provided for @aiHistoryPinned.
  ///
  /// In en, this message translates to:
  /// **'Pinned'**
  String get aiHistoryPinned;

  /// No description provided for @aiHistoryRecent.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get aiHistoryRecent;

  /// No description provided for @aiHistoryActions.
  ///
  /// In en, this message translates to:
  /// **'Conversation actions'**
  String get aiHistoryActions;

  /// No description provided for @aiHistoryRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get aiHistoryRename;

  /// No description provided for @aiHistoryPin.
  ///
  /// In en, this message translates to:
  /// **'Pin'**
  String get aiHistoryPin;

  /// No description provided for @aiHistoryUnpin.
  ///
  /// In en, this message translates to:
  /// **'Unpin'**
  String get aiHistoryUnpin;

  /// No description provided for @aiHistoryRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename conversation'**
  String get aiHistoryRenameTitle;

  /// No description provided for @aiHistoryRenameLabel.
  ///
  /// In en, this message translates to:
  /// **'Conversation name'**
  String get aiHistoryRenameLabel;

  /// No description provided for @aiHistoryRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter a name'**
  String get aiHistoryRenameHint;

  /// No description provided for @aiHistoryRenameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a conversation name'**
  String get aiHistoryRenameRequired;

  /// No description provided for @aiHistoryActionError.
  ///
  /// In en, this message translates to:
  /// **'Could not update the conversation. Try again.'**
  String get aiHistoryActionError;

  /// No description provided for @aiHistoryYesterday.
  ///
  /// In en, this message translates to:
  /// **'yesterday'**
  String get aiHistoryYesterday;

  /// No description provided for @aiCoachFabTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open AI Coach'**
  String get aiCoachFabTooltip;

  /// No description provided for @aiCoachConfigureBeforeChat.
  ///
  /// In en, this message translates to:
  /// **'Configure an AI provider before opening the chat.'**
  String get aiCoachConfigureBeforeChat;

  /// No description provided for @aiSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Coach settings'**
  String get aiSettingsTitle;

  /// No description provided for @aiSettingsFabTitle.
  ///
  /// In en, this message translates to:
  /// **'Show AI Coach button'**
  String get aiSettingsFabTitle;

  /// No description provided for @aiSettingsFabSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Display the AI Coach shortcut on app screens.'**
  String get aiSettingsFabSubtitle;

  /// No description provided for @aiSettingsProvidersCard.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get aiSettingsProvidersCard;

  /// No description provided for @aiSettingsProvidersHelp.
  ///
  /// In en, this message translates to:
  /// **'Add any OpenAI-compatible endpoint (OpenAI, Ollama, OpenRouter, Groq, LM Studio…).'**
  String get aiSettingsProvidersHelp;

  /// No description provided for @aiSettingsAddProvider.
  ///
  /// In en, this message translates to:
  /// **'Add provider'**
  String get aiSettingsAddProvider;

  /// No description provided for @aiSettingsNoProviders.
  ///
  /// In en, this message translates to:
  /// **'No providers'**
  String get aiSettingsNoProviders;

  /// No description provided for @aiSettingsNoProvidersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add a provider to start using the AI Coach.'**
  String get aiSettingsNoProvidersSubtitle;

  /// No description provided for @aiSettingsActivate.
  ///
  /// In en, this message translates to:
  /// **'Activate'**
  String get aiSettingsActivate;

  /// No description provided for @aiSettingsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get aiSettingsEdit;

  /// No description provided for @aiSettingsRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get aiSettingsRemove;

  /// No description provided for @aiSettingsRemoveConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove {name}?'**
  String aiSettingsRemoveConfirmTitle(Object name);

  /// No description provided for @aiSettingsRemoveConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'The token will also be deleted.'**
  String get aiSettingsRemoveConfirmBody;

  /// No description provided for @aiSettingsBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get aiSettingsBaseUrl;

  /// No description provided for @aiSettingsModel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get aiSettingsModel;

  /// No description provided for @aiSettingsModelValue.
  ///
  /// In en, this message translates to:
  /// **'Model: {model}'**
  String aiSettingsModelValue(Object model);

  /// No description provided for @aiSettingsProviderName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get aiSettingsProviderName;

  /// No description provided for @aiSettingsNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a name.'**
  String get aiSettingsNameRequired;

  /// No description provided for @aiSettingsBaseUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Enter a base URL.'**
  String get aiSettingsBaseUrlRequired;

  /// No description provided for @aiSettingsNoModelsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No models available'**
  String get aiSettingsNoModelsEmpty;

  /// No description provided for @aiSettingsToken.
  ///
  /// In en, this message translates to:
  /// **'API token'**
  String get aiSettingsToken;

  /// No description provided for @aiSettingsTokenHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the current token'**
  String get aiSettingsTokenHint;

  /// No description provided for @aiSettingsNameHint.
  ///
  /// In en, this message translates to:
  /// **'OpenAI, Ollama local, OpenRouter…'**
  String get aiSettingsNameHint;

  /// No description provided for @aiSettingsBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://api.openai.com/v1'**
  String get aiSettingsBaseUrlHint;

  /// No description provided for @aiSettingsNewProvider.
  ///
  /// In en, this message translates to:
  /// **'New provider'**
  String get aiSettingsNewProvider;

  /// No description provided for @aiSettingsEditProvider.
  ///
  /// In en, this message translates to:
  /// **'Edit provider'**
  String get aiSettingsEditProvider;

  /// No description provided for @aiSettingsFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Fetch models'**
  String get aiSettingsFetchModels;

  /// No description provided for @aiSettingsNoModels.
  ///
  /// In en, this message translates to:
  /// **'No models loaded. Tap \"Fetch models\" to list the available ones for {url}.'**
  String aiSettingsNoModels(Object url);

  /// No description provided for @aiSettingsContextMode.
  ///
  /// In en, this message translates to:
  /// **'Context mode'**
  String get aiSettingsContextMode;

  /// No description provided for @aiSettingsContextModeHelp.
  ///
  /// In en, this message translates to:
  /// **'How much data is sent to the AI each turn. More context = better answers, more tokens.'**
  String get aiSettingsContextModeHelp;

  /// No description provided for @aiSettingsContextModeMinimal.
  ///
  /// In en, this message translates to:
  /// **'Minimal'**
  String get aiSettingsContextModeMinimal;

  /// No description provided for @aiSettingsContextModeMinimalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Only totals and streak. AI uses tools for details.'**
  String get aiSettingsContextModeMinimalSubtitle;

  /// No description provided for @aiSettingsContextModeStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get aiSettingsContextModeStandard;

  /// No description provided for @aiSettingsContextModeStandardSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Summary + goals + top exercises. Good balance.'**
  String get aiSettingsContextModeStandardSubtitle;

  /// No description provided for @aiSettingsContextModeFull.
  ///
  /// In en, this message translates to:
  /// **'Full'**
  String get aiSettingsContextModeFull;

  /// No description provided for @aiSettingsContextModeFullSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Everything: categories, body trend, detailed volume.'**
  String get aiSettingsContextModeFullSubtitle;

  /// No description provided for @aiSettingsSystemPrompt.
  ///
  /// In en, this message translates to:
  /// **'System prompt'**
  String get aiSettingsSystemPrompt;

  /// No description provided for @aiSettingsSystemPromptHelp.
  ///
  /// In en, this message translates to:
  /// **'Defines the personality and behaviour of the AI Coach.'**
  String get aiSettingsSystemPromptHelp;

  /// No description provided for @aiSettingsRestoreDefault.
  ///
  /// In en, this message translates to:
  /// **'Restore default'**
  String get aiSettingsRestoreDefault;

  /// No description provided for @aiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get aiSettingsSaved;

  /// No description provided for @aiSettingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get aiSettingsAbout;

  /// No description provided for @aiSettingsAboutBody.
  ///
  /// In en, this message translates to:
  /// **'The AI Coach sends a summary of your data each turn and has access to 13 read tools. It cannot edit your data. Conversations are stored locally.'**
  String get aiSettingsAboutBody;

  /// No description provided for @sleepSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sleep settings'**
  String get sleepSettingsTitle;

  /// No description provided for @sleepSettingsGoalSection.
  ///
  /// In en, this message translates to:
  /// **'SLEEP GOAL'**
  String get sleepSettingsGoalSection;

  /// No description provided for @sleepSettingsMissionSection.
  ///
  /// In en, this message translates to:
  /// **'ALARM MISSION'**
  String get sleepSettingsMissionSection;

  /// No description provided for @sleepMissionToggle.
  ///
  /// In en, this message translates to:
  /// **'Barcode mission'**
  String get sleepMissionToggle;

  /// No description provided for @sleepMissionToggleBody.
  ///
  /// In en, this message translates to:
  /// **'A protected alarm requires a mission when you choose that mode.'**
  String get sleepMissionToggleBody;

  /// No description provided for @sleepMissionNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'No barcode registered'**
  String get sleepMissionNotConfigured;

  /// No description provided for @sleepMissionConfigured.
  ///
  /// In en, this message translates to:
  /// **'Registered code: {format}'**
  String sleepMissionConfigured(String format);

  /// No description provided for @sleepMissionScan.
  ///
  /// In en, this message translates to:
  /// **'Scan code'**
  String get sleepMissionScan;

  /// No description provided for @sleepMissionReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace code'**
  String get sleepMissionReplace;

  /// No description provided for @sleepMissionRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove code'**
  String get sleepMissionRemove;

  /// No description provided for @sleepMissionRemoveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove the registered code? Protected alarms already started will not change.'**
  String get sleepMissionRemoveConfirm;

  /// No description provided for @sleepMissionScanError.
  ///
  /// In en, this message translates to:
  /// **'The barcode could not be read.'**
  String get sleepMissionScanError;

  /// No description provided for @sleepMissionCameraDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to read the mission.'**
  String get sleepMissionCameraDenied;

  /// No description provided for @sleepMonitorModeSection.
  ///
  /// In en, this message translates to:
  /// **'HOW TO MONITOR'**
  String get sleepMonitorModeSection;

  /// No description provided for @sleepMonitorModeAlarmNoMission.
  ///
  /// In en, this message translates to:
  /// **'Monitor + alarm without mission'**
  String get sleepMonitorModeAlarmNoMission;

  /// No description provided for @sleepMonitorModeAlarmWithMission.
  ///
  /// In en, this message translates to:
  /// **'Monitor + alarm with mission'**
  String get sleepMonitorModeAlarmWithMission;

  /// No description provided for @sleepMonitorModeOnly.
  ///
  /// In en, this message translates to:
  /// **'Monitor only, without alarm'**
  String get sleepMonitorModeOnly;

  /// No description provided for @sleepMonitorModeAlarmNoMissionBody.
  ///
  /// In en, this message translates to:
  /// **'The alarm rings at the selected time and can be dismissed normally.'**
  String get sleepMonitorModeAlarmNoMissionBody;

  /// No description provided for @sleepMonitorModeAlarmWithMissionBody.
  ///
  /// In en, this message translates to:
  /// **'To dismiss it, scan the registered code or complete the emergency action with 500 taps.'**
  String get sleepMonitorModeAlarmWithMissionBody;

  /// No description provided for @sleepMonitorModeOnlyBody.
  ///
  /// In en, this message translates to:
  /// **'Monitors the environment without scheduling an alarm.'**
  String get sleepMonitorModeOnlyBody;

  /// No description provided for @sleepMonitorModeMissionUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Configure a barcode mission to unlock this mode.'**
  String get sleepMonitorModeMissionUnavailable;

  /// No description provided for @sleepMonitorStartOnly.
  ///
  /// In en, this message translates to:
  /// **'Start monitoring only'**
  String get sleepMonitorStartOnly;

  /// No description provided for @sleepMonitorStartWithMission.
  ///
  /// In en, this message translates to:
  /// **'Start and wake at {time} with mission'**
  String sleepMonitorStartWithMission(String time);

  /// No description provided for @sleepMonitorProtectedStop.
  ///
  /// In en, this message translates to:
  /// **'Stop monitoring only'**
  String get sleepMonitorProtectedStop;

  /// No description provided for @sleepMonitorProtectedStopBody.
  ///
  /// In en, this message translates to:
  /// **'The alarm and mission will remain active for this time.'**
  String get sleepMonitorProtectedStopBody;

  /// No description provided for @sleepMonitorMissionPending.
  ///
  /// In en, this message translates to:
  /// **'Mission pending'**
  String get sleepMonitorMissionPending;

  /// No description provided for @sleepMonitorMissionReady.
  ///
  /// In en, this message translates to:
  /// **'Mission configured'**
  String get sleepMonitorMissionReady;

  /// No description provided for @sleepMissionFormatUnknown.
  ///
  /// In en, this message translates to:
  /// **'barcode'**
  String get sleepMissionFormatUnknown;

  /// No description provided for @sleepMissionRemoved.
  ///
  /// In en, this message translates to:
  /// **'Mission removed for new sessions.'**
  String get sleepMissionRemoved;

  /// No description provided for @sleepMissionSaved.
  ///
  /// In en, this message translates to:
  /// **'Code registered successfully.'**
  String get sleepMissionSaved;

  /// No description provided for @sleepMissionOpenSettings.
  ///
  /// In en, this message translates to:
  /// **'Open camera settings'**
  String get sleepMissionOpenSettings;

  /// No description provided for @aiEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Configure an AI provider'**
  String get aiEmptyTitle;

  /// No description provided for @aiEmptySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add an OpenAI-compatible endpoint (OpenAI, Ollama, OpenRouter…) to start using the AI Coach.'**
  String get aiEmptySubtitle;

  /// No description provided for @aiEmptyConfigure.
  ///
  /// In en, this message translates to:
  /// **'Configure provider'**
  String get aiEmptyConfigure;
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
