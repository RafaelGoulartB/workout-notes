import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/screens/run/run_record_screen.dart';
import 'package:workout_notes/services/stationary_bike_tracking_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await StationaryBikeTrackingService.instance.discard();
  });

  testWidgets('shows stationary bike as a secondary exercise choice', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const RunRecordScreen(
          initialActivityType: CardioActivityType.stationaryBike,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      find.byKey(const ValueKey('cardio-activity-selector')),
      findsOneWidget,
    );
    expect(find.text('Bicicleta estacionária'), findsOneWidget);
    expect(find.text('Treino indoor'), findsOneWidget);
    expect(find.textContaining('GPS pronto'), findsNothing);
    expect(find.byIcon(Icons.location_off_outlined), findsOneWidget);
  });
}
