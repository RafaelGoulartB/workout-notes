import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/run_gear_repository.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';

import 'support/test_db.dart';

Widget _app({String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: const RunGearScreen(),
);

/// Lets real async work (sqflite FFI runs on isolates) finish between pumps.
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

Future<void> _insertRun(
  Database db, {
  required String id,
  required String gearId,
  required double meters,
  required String startedAt,
  String type = 'running',
  String status = 'completed',
}) => db.insert('run_activities', {
  'id': id,
  'activity_type': type,
  'started_at': startedAt,
  'distance_meters': meters,
  'status': status,
  'gear_id': gearId,
  'created_at': startedAt,
  'updated_at': startedAt,
});

void main() {
  late Database db;
  RunGearRepository repo() => DatabaseHelper.instance.runGearRepo;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    db = await installTestDb();
  });

  tearDown(() async {
    Intl.defaultLocale = null;
    await uninstallTestDb();
  });

  testWidgets('empty state offers to add the first shoes', (tester) async {
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('No shoes yet'));

    expect(find.text('Shoes'), findsOneWidget);
    expect(find.textContaining('track their mileage'), findsOneWidget);
    // The empty state owns the add button, so there is no floating one.
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Add shoes'), findsOneWidget);
  });

  testWidgets('adding shoes validates the name and saves every field', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('No shoes yet'));

    await tester.tap(find.text('Add shoes'));
    await tester.pumpAndSettle();
    // The sheet is titled like the action and starts with the default
    // retirement distance of 700 km.
    expect(find.text('Add shoes'), findsWidgets);
    expect(find.widgetWithText(TextFormField, '700'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);
    expect(await tester.runAsync(() => db.query('run_gear')), isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Name'),
      '  Pegasus 41 ',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Brand'), 'Nike');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Distance already used (km)'),
      '120,5',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Replace at (km)'),
      '600',
    );
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();

    await _pumpUntil(tester, find.text('Pegasus 41'));
    final saved = (await tester.runAsync(() => db.query('run_gear')))!.single;
    expect(saved['name'], 'Pegasus 41');
    expect(saved['brand'], 'Nike');
    expect(saved['initial_distance_meters'], 120500);
    expect(saved['retire_distance_meters'], 600000);
    expect(saved['is_default'], 1);

    // The list replaced the empty state; a floating add button appears.
    expect(find.text('No shoes yet'), findsNothing);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('Nike · No runs'), findsOneWidget);
    expect(find.text('121'), findsOneWidget);
    expect(find.text('20% of 600.0 km'.replaceAll('.0', '')), findsOneWidget);
    expect(find.byType(FloatingActionButton), findsOneWidget);
  });

  testWidgets('cards show mileage, wear warnings and the retired section', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final fresh = await repo().saveGear(
        name: 'Fresh pair',
        brand: 'Asics',
        initialDistanceMeters: 100000,
        isDefault: true,
      );
      // Only completed running/treadmill runs add to the mileage.
      await _insertRun(
        db,
        id: 'r1',
        gearId: fresh.id,
        meters: 5000,
        startedAt: '2026-09-20T07:00:00',
      );
      await _insertRun(
        db,
        id: 'r2',
        gearId: fresh.id,
        meters: 10000,
        startedAt: '2026-09-25T07:00:00',
        type: 'treadmill',
      );
      await _insertRun(
        db,
        id: 'r3',
        gearId: fresh.id,
        meters: 40000,
        startedAt: '2026-09-26T07:00:00',
        type: 'stationary_bike',
      );
      await _insertRun(
        db,
        id: 'r4',
        gearId: fresh.id,
        meters: 40000,
        startedAt: '2026-09-27T07:00:00',
        status: 'recording',
      );
      await repo().saveGear(
        name: 'Worn pair',
        initialDistanceMeters: 600000,
        retireDistanceMeters: 700000,
      );
      await repo().saveGear(
        name: 'Dead pair',
        initialDistanceMeters: 750000,
        retireDistanceMeters: 700000,
      );
      final old = await repo().saveGear(
        name: 'Old pair',
        initialDistanceMeters: 650000,
      );
      await repo().setRetired(old.id, true);
    });

    await tester.binding.setSurfaceSize(const Size(500, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('Fresh pair'));

    final lastRun = DateFormat.yMMMd('en').format(DateTime(2026, 9, 25, 7));
    expect(find.text('Asics · 2 runs · $lastRun'), findsOneWidget);
    // 100 km already on the shoe + 5 + 10 logged = 115 km of 700 km.
    expect(find.text('115'), findsOneWidget);
    expect(find.text('16% of 700 km'), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);

    expect(find.text('Worn pair'), findsOneWidget);
    expect(find.text('86% of 700 km'), findsOneWidget);
    expect(find.text('Consider replacing soon'), findsOneWidget);
    expect(find.text('Time to replace'), findsOneWidget);
    expect(find.text('107% of 700 km'), findsOneWidget);

    // Retired shoes sit under their own header, without wear warnings, and
    // the ordering puts them after every active pair.
    expect(find.text('RETIRED'), findsOneWidget); // section header
    expect(find.text('Retired'), findsOneWidget); // badge
    final oldY = tester.getTopLeft(find.text('Old pair')).dy;
    for (final name in ['Fresh pair', 'Worn pair', 'Dead pair']) {
      expect(tester.getTopLeft(find.text(name)).dy, lessThan(oldY));
    }
    expect(find.text('93% of 700 km'), findsOneWidget);
    expect(find.byIcon(Icons.warning_amber_rounded), findsNWidgets(2));
  });

  testWidgets('retire and put back in use from the actions sheet', (
    tester,
  ) async {
    late String id;
    await tester.runAsync(() async {
      id = (await repo().saveGear(name: 'Daily', isDefault: true)).id;
    });
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('Daily'));

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Edit shoes'), findsOneWidget);
    expect(find.text('Retire'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
    await tester.tap(find.text('Retire'));
    await tester.pumpAndSettle();

    await _pumpUntil(tester, find.text('RETIRED'));
    var row = (await tester.runAsync(
      () => db.query('run_gear', where: 'id = ?', whereArgs: [id]),
    ))!.single;
    expect(row['retired_at'], isNotNull);
    // Retiring also clears the default flag.
    expect(row['is_default'], 0);
    expect(find.text('Default'), findsNothing);

    await tester.tap(find.text('Daily'));
    await tester.pumpAndSettle();
    expect(find.text('Put back in use'), findsOneWidget);
    await tester.tap(find.text('Put back in use'));
    await tester.pumpAndSettle();
    await _pumpUntilGone(tester, find.text('RETIRED'));

    row = (await tester.runAsync(
      () => db.query('run_gear', where: 'id = ?', whereArgs: [id]),
    ))!.single;
    expect(row['retired_at'], isNull);
  });

  testWidgets('editing prefills the sheet and keeps the id', (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = (await repo().saveGear(
        name: 'Old name',
        brand: 'Hoka',
        initialDistanceMeters: 50000,
        retireDistanceMeters: 500000,
      )).id;
    });
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('Old name'));

    await tester.tap(find.text('Old name'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit shoes'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Old name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Hoka'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '50'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '500'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Old name'),
      'New name',
    );
    await tester.tap(find.text('Save'));
    await tester.pump();
    await _pumpUntil(tester, find.text('Hoka · No runs'));

    expect(find.text('New name'), findsOneWidget);
    final rows = (await tester.runAsync(() => db.query('run_gear')))!;
    expect(rows.single['id'], id);
    expect(rows.single['name'], 'New name');
    expect(rows.single['retire_distance_meters'], 500000);
  });

  testWidgets('delete asks first and detaches the runs', (tester) async {
    late String id;
    await tester.runAsync(() async {
      id = (await repo().saveGear(name: 'Doomed')).id;
      await repo().saveGear(name: 'Keeper');
      await _insertRun(
        db,
        id: 'run-1',
        gearId: id,
        meters: 8000,
        startedAt: '2026-09-10T07:00:00',
      );
    });
    await tester.pumpWidget(_app());
    await _pumpUntil(tester, find.text('Doomed'));

    await tester.tap(find.text('Doomed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Delete these shoes?'), findsOneWidget);

    // Cancelling leaves everything as it was.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Doomed'), findsOneWidget);
    expect(await tester.runAsync(() => db.query('run_gear')), hasLength(2));

    await tester.tap(find.text('Doomed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await _pumpUntilGone(tester, find.text('Doomed'));

    expect(find.text('Keeper'), findsOneWidget);
    final run = (await tester.runAsync(() => db.query('run_activities')))!;
    expect(run.single['gear_id'], isNull);
    expect(await tester.runAsync(() => db.query('run_gear')), hasLength(1));
  });

  testWidgets('renders in Portuguese with comma decimals', (tester) async {
    Intl.defaultLocale = 'pt_BR';
    await tester.runAsync(() async {
      final gear = await repo().saveGear(
        name: 'Pegasus',
        brand: 'Nike',
        initialDistanceMeters: 50000,
        isDefault: true,
      );
      await _insertRun(
        db,
        id: 'r1',
        gearId: gear.id,
        meters: 3270,
        startedAt: '2026-09-20T07:00:00',
      );
      final old = await repo().saveGear(name: 'Velho');
      await repo().setRetired(old.id, true);
    });
    await tester.binding.setSurfaceSize(const Size(500, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(locale: 'pt'));
    await _pumpUntil(tester, find.text('Pegasus'));

    expect(find.text('Tênis'), findsOneWidget);
    expect(find.text('Adicionar tênis'), findsOneWidget);
    expect(find.text('Padrão'), findsOneWidget);
    final lastRun = DateFormat.yMMMd('pt_BR').format(DateTime(2026, 9, 20, 7));
    expect(find.text('Nike · 1 corrida · $lastRun'), findsOneWidget);
    // 53.27 km, with the Portuguese decimal comma.
    expect(find.text('53,3'), findsOneWidget);
    expect(find.text('8% de 700 km'), findsOneWidget);
    expect(find.text('APOSENTADOS'), findsOneWidget);

    await tester.pumpAndSettle(); // the floating button animates in
    await tester.tap(find.text('Adicionar tênis'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Informe um nome'), findsOneWidget);
  });
}
