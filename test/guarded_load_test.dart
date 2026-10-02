import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/run/run_gear_screen.dart';
import 'package:workout_notes/screens/run/run_history_screen.dart';
import 'package:workout_notes/screens/run/run_plans_screen.dart';
import 'package:workout_notes/screens/workout/calendar_screen.dart';
import 'package:workout_notes/widgets/ui/guarded_load.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';

/// Screen with a controllable loader, built the way the real screens are.
class _Harness extends StatefulWidget {
  final Future<String> Function(int call) loader;

  const _Harness({required this.loader});

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> with GuardedLoad {
  String? data;
  int calls = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guardedLoad(() async {
    final token = loadToken;
    final call = ++calls;
    final result = await widget.loader(call);
    if (!mounted || !isLoadCurrent(token)) return;
    setState(() => data = result);
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const CircularProgressIndicator();
    if (loadFailed) return LoadErrorView(onRetry: _load);
    return Column(
      children: [
        Text(data ?? 'none'),
        TextButton(onPressed: _load, child: const Text('reload')),
      ],
    );
  }
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

/// A database that opens but lacks every feature table, so each read fails.
Future<Database> _bareDatabase() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => db.execute(
        'CREATE TABLE app_settings (key TEXT PRIMARY KEY, value TEXT)',
      ),
    ),
  );
  DatabaseHelper.overrideDatabase = db;
  return db;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GuardedLoad', () {
    testWidgets('a successful load replaces the spinner with the content', (
      tester,
    ) async {
      await tester.pumpWidget(_app(_Harness(loader: (_) async => 'hello')));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump();
      expect(find.text('hello'), findsOneWidget);
      expect(find.byType(LoadErrorView), findsNothing);
    });

    testWidgets('a failing load ends in an error view and retry recovers', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          _Harness(
            loader: (call) async {
              if (call == 1) throw StateError('boom');
              return 'recovered';
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('load-error-retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('load-error-retry')));
      await tester.pump();
      await tester.pump();
      expect(find.text('recovered'), findsOneWidget);
      expect(find.byType(LoadErrorView), findsNothing);
    });

    testWidgets('only the newest load decides the result', (tester) async {
      final first = Completer<String>();
      final second = Completer<String>();
      await tester.pumpWidget(
        _app(
          _Harness(loader: (call) => call == 1 ? first.future : second.future),
        ),
      );
      await tester.pump();

      // Start a second load while the first is still running.
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      unawaited(state._load());
      second.complete('newest');
      await tester.pump();
      first.complete('stale');
      await tester.pump();
      await tester.pump();

      expect(find.text('newest'), findsOneWidget);
      expect(find.text('stale'), findsNothing);
    });

    testWidgets('a stale failure does not replace a newer success', (
      tester,
    ) async {
      final first = Completer<String>();
      await tester.pumpWidget(
        _app(
          _Harness(
            loader: (call) => call == 1 ? first.future : Future.value('ok'),
          ),
        ),
      );
      await tester.pump();
      final state = tester.state<_HarnessState>(find.byType(_Harness));
      unawaited(state._load());
      await tester.pump();
      first.completeError(StateError('late failure'));
      await tester.pump();
      await tester.pump();

      expect(find.text('ok'), findsOneWidget);
      expect(find.byType(LoadErrorView), findsNothing);
    });
  });

  group('screens end in an error with retry, never a forever spinner', () {
    late Database db;

    setUp(() async {
      db = await _bareDatabase();
    });

    tearDown(() async {
      DatabaseHelper.overrideDatabase = null;
      await db.close();
    });

    for (final entry in <String, Widget Function()>{
      'run plans': () => const RunPlansScreen(),
      'run gear': () => const RunGearScreen(),
      'run history': () => const RunHistoryScreen(),
      'calendar': () => const CalendarScreen(),
    }.entries) {
      testWidgets(entry.key, (tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(_app(entry.value()));
        });
        await _settle(tester);

        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const Key('load-error-retry')), findsOneWidget);
      });
    }
  });
}
