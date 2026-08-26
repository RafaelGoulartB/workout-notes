import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_track_point.dart';
import 'package:workout_notes/screens/run/run_replay_screen.dart';

void main() {
  test('replays each real minute in one second', () {
    expect(
      RunReplayScreen.replayDurationFor(10 * 60),
      const Duration(seconds: 10),
    );
    expect(
      RunReplayScreen.replayDurationFor(60 * 60),
      const Duration(minutes: 1),
    );
    expect(
      RunReplayScreen.replayDurationFor(2 * 60 * 60),
      const Duration(minutes: 2),
    );
    expect(
      RunReplayScreen.replayDurationFor(90),
      const Duration(milliseconds: 1500),
    );
  });

  testWidgets('replays a GPS trail with synchronized stats and controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final startedAt = DateTime.utc(2026, 8, 25, 10);
    final activity = RunActivity(
      id: 'replay-run',
      startedAt: startedAt,
      endedAt: startedAt.add(const Duration(minutes: 30)),
      durationSeconds: 1800,
      movingTimeSeconds: 1750,
      distanceMeters: 5000,
      avgPaceSecPerKm: 350,
      maxPaceSecPerKm: 330,
      calories: 400,
      title: 'Corrida teste',
      notes: null,
      status: 'completed',
      polylineSummary: null,
      createdAt: startedAt,
      updatedAt: startedAt,
    );
    final points = [
      RunTrackPoint(
        id: 'point-1',
        activityId: activity.id,
        seq: 0,
        lat: -23.5505,
        lng: -46.6333,
        altitude: null,
        accuracy: 5,
        speed: 3,
        recordedAt: startedAt,
      ),
      RunTrackPoint(
        id: 'point-2',
        activityId: activity.id,
        seq: 1,
        lat: -23.545,
        lng: -46.625,
        altitude: null,
        accuracy: 5,
        speed: 3.2,
        recordedAt: startedAt.add(const Duration(minutes: 15)),
      ),
      RunTrackPoint(
        id: 'point-3',
        activityId: activity.id,
        seq: 2,
        lat: -23.54,
        lng: -46.62,
        altitude: null,
        accuracy: 5,
        speed: 3.1,
        recordedAt: startedAt.add(const Duration(minutes: 30)),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RunReplayScreen(
          activity: activity,
          points: points,
          showMapTiles: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Replay da corrida'), findsOneWidget);
    expect(find.text('Tempo'), findsOneWidget);
    expect(find.text('Pace'), findsOneWidget);
    expect(find.text('Distância'), findsOneWidget);
    expect(find.byKey(const ValueKey('run-replay-control')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(
      RunReplayScreen.replayDurationFor(activity.movingTimeSeconds),
    );
    expect(find.text('30:00'), findsOneWidget);
    expect(find.text('5.00 km'), findsOneWidget);
    expect(find.text('Reproduzir novamente'), findsOneWidget);
  });
}
