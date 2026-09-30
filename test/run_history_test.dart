import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_activity_filter.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/screens/run/run_history_screen.dart';

import 'support/test_db.dart';

Future<T> real<T>(WidgetTester tester, Future<T> Function() body) async {
  late T result;
  await tester.runAsync(() async {
    result = await body();
  });
  return result;
}

Future<void> settle(WidgetTester tester, {int millis = 250}) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration(milliseconds: millis));
    await tester.pump();
  });
}

void main() {
  late Database database;
  late RunRepository repository;

  setUpAll(() {
    initSqfliteFfiForTests();
    Intl.defaultLocale = 'pt_BR';
  });

  tearDownAll(() => Intl.defaultLocale = null);

  setUp(() async {
    database = await installTestDb();
    repository = RunRepository();
  });

  tearDown(uninstallTestDb);

  Future<void> seed(
    String id,
    DateTime startedAt, {
    double km = 5,
    String type = 'running',
    String? title,
    String? notes,
    String? planWorkoutId,
    String status = 'completed',
  }) => database.insert('run_activities', {
    'id': id,
    'activity_type': type,
    'started_at': startedAt.toIso8601String(),
    'duration_seconds': (km * 330).round(),
    'moving_time_seconds': (km * 330).round(),
    'distance_meters': km * 1000,
    'avg_pace_sec_per_km': 330.0,
    'title': title,
    'notes': notes,
    'status': status,
    'plan_workout_id': planWorkoutId,
    'created_at': startedAt.toIso8601String(),
    'updated_at': startedAt.toIso8601String(),
  });

  group('history queries', () {
    test('filters by type, distance range, plan link and text', () async {
      await seed('a', DateTime(2026, 9, 1, 7), km: 3, title: 'Rodagem leve');
      await seed('b', DateTime(2026, 9, 3, 7), km: 7, planWorkoutId: 'w1');
      await seed('c', DateTime(2026, 9, 5, 7), km: 12, notes: 'Longão 100%');
      await seed('d', DateTime(2026, 9, 6, 7), km: 5, type: 'treadmill');
      await seed('e', DateTime(2026, 9, 7, 7), km: 20, type: 'stationary_bike');
      await seed('f', DateTime(2026, 9, 8, 7), km: 9, status: 'recording');

      Future<List<String>> ids(RunActivityFilter filter) async => [
        for (final a in await repository.searchActivities(filter)) a.id,
      ];

      expect(await ids(RunActivityFilter.all), ['e', 'd', 'c', 'b', 'a']);
      expect(
        await ids(
          const RunActivityFilter(types: [CardioActivityType.treadmill]),
        ),
        ['d'],
      );
      expect(
        await ids(
          const RunActivityFilter(
            minDistanceMeters: 5000,
            maxDistanceMeters: 10000,
          ),
        ),
        ['d', 'b'],
      );
      expect(await ids(const RunActivityFilter(onlyPlanWorkouts: true)), ['b']);
      expect(await ids(const RunActivityFilter(query: 'rodagem')), ['a']);
      // Wildcards in the search are literal characters.
      expect(await ids(const RunActivityFilter(query: '100%')), ['c']);
      expect(await ids(const RunActivityFilter(query: '%')), ['c']);
      expect(await ids(const RunActivityFilter(query: '_')), isEmpty);
    });

    test('pages newest first without gaps', () async {
      for (var day = 1; day <= 25; day++) {
        await seed('r$day', DateTime(2026, 9, day, 7));
      }
      final first = await repository.searchActivities(
        RunActivityFilter.all,
        limit: 10,
      );
      final second = await repository.searchActivities(
        RunActivityFilter.all,
        limit: 10,
        offset: 10,
      );
      final third = await repository.searchActivities(
        RunActivityFilter.all,
        limit: 10,
        offset: 20,
      );
      expect(first.first.id, 'r25');
      expect(second.first.id, 'r15');
      expect(third.map((a) => a.id), ['r5', 'r4', 'r3', 'r2', 'r1']);
    });

    test('totals and monthly totals follow the same filter', () async {
      await seed('a', DateTime(2026, 8, 30, 7), km: 4);
      await seed('b', DateTime(2026, 9, 1, 7), km: 6);
      await seed('c', DateTime(2026, 9, 2, 7), km: 10, type: 'treadmill');

      final all = await repository.summarizeActivities(RunActivityFilter.all);
      expect(all.count, 3);
      expect(all.distanceMeters, 20000);
      expect(all.movingTimeSeconds, (20 * 330));

      final months = await repository.monthlyTotals(RunActivityFilter.all);
      expect(months['2026-08']!.count, 1);
      expect(months['2026-09']!.count, 2);
      expect(months['2026-09']!.distanceMeters, 16000);

      const running = RunActivityFilter(types: [CardioActivityType.running]);
      expect((await repository.summarizeActivities(running)).count, 2);
      expect((await repository.monthlyTotals(running))['2026-09']!.count, 1);
      expect(
        await repository.summarizeActivities(
          const RunActivityFilter(query: 'nada'),
        ),
        isA<RunActivityTotals>().having((t) => t.count, 'count', 0),
      );
    });

    test('the filter presets turn into query bounds', () {
      final now = DateTime(2026, 9, 28, 15);
      final query = const RunHistoryFilter(
        type: RunHistoryType.treadmill,
        period: RunHistoryPeriod.last30Days,
        distance: RunHistoryDistance.from5to10,
        onlyPlan: true,
        query: '  tempo ',
      ).toQuery(now);
      expect(query.types, [CardioActivityType.treadmill]);
      expect(query.startedFrom, DateTime(2026, 8, 30));
      expect(query.minDistanceMeters, 5000);
      expect(query.maxDistanceMeters, 10000);
      expect(query.onlyPlanWorkouts, isTrue);
      expect(query.query, 'tempo');
      expect(const RunHistoryFilter().isActive, isFalse);
      expect(const RunHistoryFilter(query: 'x').isActive, isTrue);
    });
  });

  group('RunHistoryScreen', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('pt'),
            home: RunHistoryScreen(),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 300));
        await tester.pump();
      });
    }

    testWidgets('shows the empty state without any run', (tester) async {
      await pump(tester);
      expect(find.text('Nenhuma corrida ainda'), findsOneWidget);
    });

    testWidgets('summarizes the result and groups rows by month', (
      tester,
    ) async {
      await real(tester, () async {
        await seed('a', DateTime(2026, 8, 30, 7), km: 4, title: 'Agosto');
        await seed('b', DateTime(2026, 9, 1, 7), km: 6, title: 'Setembro 1');
        await seed('c', DateTime(2026, 9, 2, 7), km: 10, title: 'Setembro 2');
      });
      await pump(tester);

      expect(find.textContaining('3 atividades · 20,0 km'), findsOneWidget);
      expect(find.text('Setembro de 2026'), findsOneWidget);
      expect(find.text('16,0 km · 2 atividades'), findsOneWidget);
      expect(find.text('Agosto de 2026'), findsOneWidget);
      expect(find.text('4,00 km · 1 atividade'), findsOneWidget);
      expect(find.text('Setembro 2'), findsOneWidget);
    });

    testWidgets('filtering by type updates the list and summary', (
      tester,
    ) async {
      await real(tester, () async {
        await seed('a', DateTime(2026, 9, 1, 7), title: 'Rua');
        await seed(
          'b',
          DateTime(2026, 9, 2, 7),
          title: 'Esteira longa',
          type: 'treadmill',
        );
      });
      await pump(tester);
      expect(find.text('Rua'), findsOneWidget);
      expect(find.text('Esteira longa'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('runHistoryType_treadmill')));
      await settle(tester);

      expect(find.text('Rua'), findsNothing);
      expect(find.text('Esteira longa'), findsOneWidget);
      expect(find.textContaining('1 atividade · '), findsOneWidget);
      expect(find.text('Limpar filtros'), findsOneWidget);

      await tester.tap(find.text('Limpar filtros'));
      await settle(tester);
      expect(find.text('Rua'), findsOneWidget);
    });

    testWidgets('search with no match shows the no-results state', (
      tester,
    ) async {
      await real(tester, () async {
        await seed('a', DateTime(2026, 9, 1, 7), title: 'Rodagem');
      });
      await pump(tester);

      await tester.enterText(find.byType(TextField), 'maratona');
      // The search is debounced on the (fake) clock; the query itself is real.
      await tester.pump(const Duration(milliseconds: 400));
      await settle(tester);

      expect(find.text('Nenhuma atividade encontrada'), findsOneWidget);
      expect(find.text('Nenhuma corrida ainda'), findsNothing);
    });

    testWidgets('loads more rows while scrolling', (tester) async {
      await real(tester, () async {
        for (var i = 0; i < 45; i++) {
          await seed(
            'r$i',
            DateTime(2026, 9, 1, 7).subtract(Duration(days: i)),
            title: 'Corrida ${i.toString().padLeft(2, '0')}',
          );
        }
      });
      await pump(tester);
      expect(find.text('Corrida 00'), findsOneWidget);
      expect(find.text('Corrida 44'), findsNothing);
      // The summary counts everything, not just the loaded page.
      expect(find.textContaining('45 atividades'), findsOneWidget);

      for (var i = 0; i < 6; i++) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -2500));
        await settle(tester, millis: 150);
      }
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -2500));
      await settle(tester);
      expect(find.text('Corrida 44'), findsOneWidget);
    });
  });
}
