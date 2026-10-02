import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/screens/run/run_voice_settings_screen.dart';
import 'package:workout_notes/services/run_voice_settings_store.dart';

import 'support/test_db.dart';

Future<void> _open(WidgetTester tester, {String locale = 'en'}) async {
  tester.view.physicalSize = const Size(390, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const RunVoiceSettingsScreen(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester, RunVoiceSettings settings) async {
  await tester.runAsync(() => RunVoiceSettingsStore.instance.save(settings));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await installTestDb();
  });
  tearDown(uninstallTestDb);

  testWidgets('renders the coach tiles and distance cue options', (
    tester,
  ) async {
    await _save(tester, const RunVoiceSettings.defaults());
    await _open(tester);

    expect(find.text('Coach detail'), findsOneWidget);
    expect(find.text('Voice speed'), findsOneWidget);
    expect(find.text('Voice volume'), findsOneWidget);
    expect(find.text('While speaking'), findsOneWidget);
    expect(find.text('Beeps'), findsOneWidget);
    expect(find.text('Vibration'), findsOneWidget);
    expect(find.text('Distance cues'), findsOneWidget);
    expect(find.text('Elapsed time'), findsOneWidget);
    expect(find.text('Split pace'), findsOneWidget);
    expect(find.text('Average pace'), findsOneWidget);
    expect(find.text('Time cues'), findsOneWidget);
    expect(find.text('Auto-pause style'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('distance cue options hide when distance cues are off', (
    tester,
  ) async {
    await _save(
      tester,
      const RunVoiceSettings.defaults().copyWith(
        announceDistance: false,
        announceAutoPause: false,
      ),
    );
    await _open(tester);

    expect(find.text('Distance cues'), findsOneWidget);
    expect(find.text('Elapsed time'), findsNothing);
    expect(find.text('Split pace'), findsNothing);
    expect(find.text('Average pace'), findsNothing);
    expect(find.text('Auto-pause style'), findsNothing);
    expect(find.text('Time cues'), findsOneWidget);
  });

  testWidgets('picking a coach detail level updates the setting', (
    tester,
  ) async {
    await _save(tester, const RunVoiceSettings.defaults());
    await _open(tester);

    await tester.tap(find.text('Coach detail'));
    await tester.pumpAndSettle();
    expect(find.text('Minimal'), findsOneWidget);
    expect(
      find.text('Only step changes, pace corrections and the finish'),
      findsOneWidget,
    );
    await tester.tap(find.text('Detailed'));
    await tester.pumpAndSettle();

    final saved = await RunVoiceSettingsStore.instance.load();
    expect(saved.verbosity, RunVoiceVerbosity.detailed);
  });

  testWidgets('renders in Portuguese', (tester) async {
    await _save(tester, const RunVoiceSettings.defaults());
    await _open(tester, locale: 'pt');

    expect(find.text('Nível de detalhe'), findsOneWidget);
    expect(find.text('Velocidade da voz'), findsOneWidget);
    expect(find.text('Avisos de tempo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
