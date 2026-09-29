import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/widgets/run/run_pending_review_banner.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: Scaffold(body: child),
);

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await tester.pump();
  });
  await tester.pump(const Duration(milliseconds: 300));
}

/// `testWidgets` verifies foundation debug variables *before* tear-downs run,
/// so the Android platform override has to be cleared inside the body.
void _androidTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database database;
  late List<Map<String, dynamic>> pending;
  late List<String> deleted;

  final spool = <String, dynamic>{
    'activity': <String, dynamic>{
      'id': 'lost-run',
      'status': 'pending_review',
      'started_at': '2026-08-25T10:00:00.000',
      'ended_at': '2026-08-25T10:30:00.000',
      'duration_seconds': 1800,
      'moving_time_seconds': 1750,
      'distance_meters': 5000.0,
    },
    'points': <Map<String, dynamic>>[],
  };

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    pending = [
      {'id': 'lost-run', 'status': 'pending_review'},
    ];
    deleted = [];
    messenger.setMockMethodCallHandler(RunTrackingService.methods, (
      call,
    ) async {
      switch (call.method) {
        case 'listPendingSpools':
          return pending;
        case 'readSpool':
          return spool;
        case 'deleteSpool':
          deleted.add(call.arguments as String);
          pending.removeWhere((row) => row['id'] == call.arguments);
          return true;
      }
      return true;
    });
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 53,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
  });

  tearDown(() async {
    DatabaseHelper.overrideDatabase = null;
    await database.close();
    messenger.setMockMethodCallHandler(RunTrackingService.methods, null);
  });

  _androidTest('offers to review or discard a run that was never saved', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const RunPendingReviewBanner()));
    await _settle(tester);

    expect(find.text('Você tem uma corrida não salva'), findsOneWidget);
    expect(find.text('Revisar'), findsOneWidget);
    expect(find.text('Descartar'), findsOneWidget);
  });

  _androidTest('discarding asks first and removes the native spool', (
    tester,
  ) async {
    var changed = 0;
    await tester.pumpWidget(
      _app(RunPendingReviewBanner(onChanged: () => changed++)),
    );
    await _settle(tester);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(find.text('Descartar esta corrida?'), findsOneWidget);

    // Cancelling keeps everything.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(deleted, isEmpty);
    expect(find.text('Você tem uma corrida não salva'), findsOneWidget);

    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(FilledButton, 'Descartar'));
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await _settle(tester);

    expect(deleted, ['lost-run']);
    expect(changed, 1);
    expect(find.text('Você tem uma corrida não salva'), findsNothing);
  });

  _androidTest('refreshToken re-reads the pending list', (tester) async {
    pending = [];
    var token = 0;
    late StateSetter update;
    await tester.pumpWidget(
      _app(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return RunPendingReviewBanner(refreshToken: token);
          },
        ),
      ),
    );
    await _settle(tester);
    expect(find.text('Você tem uma corrida não salva'), findsNothing);

    pending = [
      {'id': 'lost-run', 'status': 'pending_review'},
    ];
    update(() => token++);
    await tester.pump();
    await _settle(tester);
    expect(find.text('Você tem uma corrida não salva'), findsOneWidget);
  });
}
