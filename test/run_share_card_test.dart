import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:share_plus/share_plus.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_export_service.dart';
import 'package:workout_notes/widgets/run/run_share_card.dart';

RunActivity _activity() {
  final started = DateTime.utc(2026, 8, 25, 10);
  return RunActivity(
    id: 'share-run',
    startedAt: started,
    endedAt: started.add(const Duration(minutes: 30)),
    durationSeconds: 1800,
    movingTimeSeconds: 1750,
    distanceMeters: 5000,
    avgPaceSecPerKm: 350,
    maxPaceSecPerKm: null,
    calories: 400,
    title: 'Corrida do parque',
    notes: null,
    status: 'completed',
    polylineSummary:
        '-23.55000,-46.63000;-23.55100,-46.63200;-23.55300,-46.63100;'
        '-23.55400,-46.62900',
    createdAt: started,
    updatedAt: started,
    elevationGainMeters: 42,
  );
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('pt'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void main() {
  testWidgets('the share card shows the run headline numbers', (tester) async {
    await tester.pumpWidget(
      _app(
        Scaffold(
          body: Center(child: RunShareCard(activity: _activity())),
        ),
      ),
    );
    expect(find.text('Corrida do parque'), findsOneWidget);
    expect(find.text('5.00'), findsOneWidget);
    expect(find.text('WORKOUT NOTES'), findsOneWidget);
    expect(find.text('29:10'), findsOneWidget);
    expect(find.text('+42 m'), findsOneWidget);
  });

  testWidgets('sharing renders the card to a PNG and shares it', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final temp = Directory.systemTemp.createTempSync('run_share_');
    addTearDown(() => temp.deleteSync(recursive: true));
    XFile? shared;
    final service = RunExportService(
      tempDirectory: () async => temp,
      shareFile: (file, text) async => shared = file,
    );

    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showRunShareSheet(
                context,
                activity: _activity(),
                exportService: service,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Compartilhar esta corrida'), findsOneWidget);

    await tester.tap(find.text('Compartilhar'));
    // Rasterising and writing the file use real async work, so alternate
    // real waits with frames until the share callback fires.
    await tester.runAsync(() async {
      for (var i = 0; i < 20 && shared == null; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    });

    expect(shared, isNotNull);
    expect(shared!.mimeType, 'image/png');
    final bytes = File(shared!.path).readAsBytesSync();
    // PNG signature.
    expect(bytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
    expect(bytes.length, greaterThan(1000));
  });
}
