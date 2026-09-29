import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/workout/set_editor_fields.dart';

Widget _app(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _pumpPace(
  WidgetTester tester, {
  required double distance,
  required int timeSeconds,
}) async {
  await tester.pumpWidget(
    _app(
      WorkoutSetFieldControls(
        exerciseType: 'distanceTime',
        weight: 0,
        reps: 0,
        distance: distance,
        timeSeconds: timeSeconds,
        showPace: true,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('pace display rounds the whole pace before splitting m:ss', (
    tester,
  ) async {
    // 3596 s over 10 km is 359.6 s/km, which is 6:00 and not 5:00.
    await _pumpPace(tester, distance: 10, timeSeconds: 3596);
    expect(find.text('Pace: 6:00 /km'), findsOneWidget);
  });

  testWidgets('pace display zero-pads the seconds', (tester) async {
    await _pumpPace(tester, distance: 5, timeSeconds: 1505);
    expect(find.text('Pace: 5:01 /km'), findsOneWidget);
  });
}
