import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/sleep/sleep_settings_screen.dart';
import 'package:workout_notes/services/alarm_wake_settings_service.dart';
import 'package:workout_notes/services/sleep_diagnostic_store.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/traditional_alarm_service.dart';
import 'package:workout_notes/widgets/settings/settings.dart';

import 'support/test_db.dart';

const _sleepChannel = MethodChannel('workout_notes/sleep_monitor/methods');
const _alarmChannel = MethodChannel('workout_notes/traditional_alarms/methods');
const _pathChannel = MethodChannel('plugins.flutter.io/path_provider');

class _FakeFilePicker extends FilePickerPlatform {
  final saved = <({String fileName, Uint8List bytes})>[];
  Error? error;

  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    final failure = error;
    if (failure != null) throw failure;
    saved.add((fileName: fileName, bytes: bytes));
    return Uri.file('/tmp/$fileName');
  }
}

Widget _app({String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const SleepSettingsScreen(),
);

/// Lets real async work (sqflite and file IO) finish between pumps.
Future<void> _settle(WidgetTester tester, [int rounds = 8]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _pumpUntil(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await _settle(tester, 1);
    if (finder.evaluate().isNotEmpty) return;
  }
  fail('Timed out waiting for $finder');
}

Future<void> _pumpUntilGone(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 60; i++) {
    await _settle(tester, 1);
    if (finder.evaluate().isEmpty) return;
  }
  fail('Timed out waiting for $finder to disappear');
}

/// The switch inside the settings tile titled [title].
Finder _switchOf(String title) => find.descendant(
  of: find.widgetWithText(SettingsSwitchTile, title),
  matching: find.byType(Switch),
);

bool _isOn(WidgetTester tester, String title) =>
    tester.widget<Switch>(_switchOf(title)).value;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final en = lookupAppLocalizations(const Locale('en'));
  late List<MethodCall> calls;
  late Directory supportDir;
  late _FakeFilePicker picker;
  late FilePickerPlatform originalPicker;
  Map<String, Object?>? scanResult;

  Future<String?> setting(String key) =>
      DatabaseHelper.instance.settingsRepo.getSetting(key);

  Future<void> putSetting(String key, String value) =>
      DatabaseHelper.instance.settingsRepo.setSetting(key, value);

  /// Pumps the screen on a tall surface so every section is built.
  Future<void> openScreen(WidgetTester tester, {String locale = 'en'}) async {
    await tester.binding.setSurfaceSize(const Size(500, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(locale: locale));
    await _pumpUntil(tester, find.byType(ListView));
  }

  /// Like [testWidgets], but as Android so the native facades are used.
  void androidTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await installTestDb();
    calls = [];
    scanResult = null;
    supportDir = Directory.systemTemp.createTempSync('sleep_settings_test');
    picker = _FakeFilePicker();
    originalPicker = FilePickerPlatform.instance;
    FilePickerPlatform.instance = picker;
    messenger.setMockMethodCallHandler(_pathChannel, (call) async {
      return supportDir.path;
    });
    messenger.setMockMethodCallHandler(_sleepChannel, (call) async {
      calls.add(call);
      if (call.method == 'scanBarcodeForMission') return scanResult;
      return null;
    });
    messenger.setMockMethodCallHandler(_alarmChannel, (call) async {
      calls.add(call);
      return null;
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_pathChannel, null);
    messenger.setMockMethodCallHandler(_sleepChannel, null);
    messenger.setMockMethodCallHandler(_alarmChannel, null);
    FilePickerPlatform.instance = originalPicker;
    if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    await uninstallTestDb();
  });

  Iterable<MethodCall> called(String method) =>
      calls.where((call) => call.method == method);

  testWidgets('shows the defaults for a fresh install', (tester) async {
    await openScreen(tester);

    expect(find.text('Sleep settings'), findsOneWidget);
    expect(find.text('8h 0min per night'), findsOneWidget);
    expect(find.text('30 min before the wake time · Balanced'), findsOneWidget);
    expect(find.text('Starts soft and rises over 2 min'), findsOneWidget);
    expect(_isOn(tester, 'Maximum volume at the end'), isTrue);
    expect(_isOn(tester, 'Allow snoozes'), isTrue);
    expect(find.text('3 time(s)'), findsOneWidget);
    expect(_isOn(tester, 'Keep sleep diagnostics'), isFalse);
    expect(find.text('Export latest sleep diagnostic'), findsNothing);
    expect(_isOn(tester, 'Barcode mission'), isFalse);
    expect(find.text('No barcode registered'), findsOneWidget);
    expect(find.text('Scan code'), findsOneWidget);
    expect(find.text('Remove code'), findsNothing);
  });

  testWidgets('shows previously saved preferences', (tester) async {
    await tester.runAsync(() async {
      await putSetting(SleepGoalService.settingKey, '420');
      await putSetting(AlarmWakeSettingsService.windowKey, '0');
      await putSetting(AlarmWakeSettingsService.rampKey, '0');
      await putSetting(AlarmWakeSettingsService.boostKey, 'false');
      await putSetting(TraditionalAlarmService.globalSnoozeEnabledKey, 'false');
      await putSetting(TraditionalAlarmService.globalMaxSnoozesKey, '0');
      await SleepMissionService().saveScanResult({
        'hash': 'h',
        'salt': 's',
        'format': 'QR_CODE',
        'registered_at': '2026-09-20T07:30:00',
      });
      await SharedPreferences.getInstance().then(
        (prefs) => prefs.setBool(SleepDiagnosticStore.preferenceKey, true),
      );
    });
    await openScreen(tester);

    expect(find.text('7h 0min per night'), findsOneWidget);
    // The smart window is off, so its row says so; ramp off too.
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Full volume at once'), findsOneWidget);
    expect(_isOn(tester, 'Maximum volume at the end'), isFalse);
    expect(_isOn(tester, 'Allow snoozes'), isFalse);
    expect(find.text('Do not allow'), findsOneWidget);
    expect(_isOn(tester, 'Keep sleep diagnostics'), isTrue);
    expect(find.text('Export latest sleep diagnostic'), findsOneWidget);
    // A registered code shows its format and registration date, and the
    // scan row turns into replace / remove.
    expect(find.text('Registered code: QR_CODE'), findsOneWidget);
    expect(
      find.text(DateFormat.yMd('en').format(DateTime(2026, 9, 20, 7, 30))),
      findsOneWidget,
    );
    expect(find.text('Replace code'), findsOneWidget);
    expect(find.text('Remove code'), findsOneWidget);
    expect(find.text('Scan code'), findsNothing);
    expect(_isOn(tester, 'Barcode mission'), isTrue);
  });

  testWidgets('the sleep goal dialog saves or discards the slider value', (
    tester,
  ) async {
    await openScreen(tester);

    await tester.tap(find.text('Sleep goal'));
    await tester.pumpAndSettle();
    expect(find.text('Set sleep goal'), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(-800, 0));
    await tester.pump();
    // Dragging to the start gives the 4 h minimum, previewed in the dialog.
    expect(find.text('4h 0min'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('8h 0min per night'), findsOneWidget);
    expect(await tester.runAsync(() => setting('sleep_goal_minutes')), isNull);

    await tester.tap(find.text('Sleep goal'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(800, 0));
    await tester.pump();
    expect(find.text('12h 0min'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await _pumpUntil(tester, find.text('Sleep goal saved'));

    expect(find.text('12h 0min per night'), findsOneWidget);
    expect(await tester.runAsync(() => setting('sleep_goal_minutes')), '720');
  });

  testWidgets('diagnostics can be enabled, exported and switched off', (
    tester,
  ) async {
    await openScreen(tester);

    await tester.tap(find.text('Keep sleep diagnostics'));
    await _pumpUntil(tester, find.text('Export latest sleep diagnostic'));
    expect(_isOn(tester, 'Keep sleep diagnostics'), isTrue);
    final prefs = (await tester.runAsync(SharedPreferences.getInstance))!;
    expect(prefs.getBool(SleepDiagnosticStore.preferenceKey), isTrue);

    // Nothing recorded yet: explain instead of opening the save dialog.
    await tester.tap(find.text('Export latest sleep diagnostic'));
    await _pumpUntil(tester, find.text(en.sleepDiagnosticMissing));
    expect(picker.saved, isEmpty);
    ScaffoldMessenger.of(
      tester.element(find.text('Sleep settings')),
    ).clearSnackBars();
    await tester.pumpAndSettle();

    final archive = Directory('${supportDir.path}/sleep_diagnostics');
    final file = File('${archive.path}/night.json');
    await tester.runAsync(() async {
      await archive.create(recursive: true);
      await file.writeAsString('{"schema":"sleep-aggregate-replay"}');
    });
    await tester.tap(find.text('Export latest sleep diagnostic'));
    for (var i = 0; i < 60 && picker.saved.isEmpty; i++) {
      await _settle(tester, 1);
    }
    expect(picker.saved.single.fileName, 'sleep_diagnostic.json');
    expect(
      String.fromCharCodes(picker.saved.single.bytes),
      '{"schema":"sleep-aggregate-replay"}',
    );

    // A failing save dialog reports the error and keeps the screen usable.
    picker.error = StateError('no storage');
    await tester.tap(find.text('Export latest sleep diagnostic'));
    await _pumpUntil(tester, find.text(en.sleepDiagnosticError));
    expect(find.text('Sleep settings'), findsOneWidget);

    // Turning the option off hides the export row and deletes the archive.
    await tester.tap(find.text('Keep sleep diagnostics'));
    await _pumpUntilGone(tester, find.text('Export latest sleep diagnostic'));
    expect(prefs.getBool(SleepDiagnosticStore.preferenceKey), isFalse);
    expect(await tester.runAsync(file.exists), isFalse);
  });

  androidTest('enabling the mission without a code starts a scan', (
    tester,
  ) async {
    await openScreen(tester);

    await tester.tap(find.text('Barcode mission'));
    await _pumpUntil(tester, find.text('The barcode could not be read.'));

    expect(called('scanBarcodeForMission'), hasLength(1));
    expect(_isOn(tester, 'Barcode mission'), isFalse);
  });

  testWidgets('renders in Portuguese', (tester) async {
    await openScreen(tester, locale: 'pt');
    final pt = lookupAppLocalizations(const Locale('pt'));

    expect(find.text(pt.sleepSettingsTitle), findsOneWidget);
    expect(
      find.text(pt.sleepGoalCurrent(pt.sleepDurationValue(8, 0))),
      findsOneWidget,
    );
    expect(find.text(pt.sleepSmartWakeTitle), findsOneWidget);
    expect(find.text(pt.sleepSettingsSnoozeToggle), findsOneWidget);
    expect(find.text(pt.alarmSnoozeTimes(3)), findsOneWidget);
    expect(find.text(pt.sleepMissionNotConfigured), findsOneWidget);
    expect(find.text(pt.sleepMissionScan), findsOneWidget);
    expect(
      find.text(pt.sleepSettingsGoalSection.toUpperCase()),
      findsOneWidget,
    );
  });
}
