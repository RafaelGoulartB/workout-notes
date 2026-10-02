import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/alarms/medication_reminders_tab.dart';
import 'package:workout_notes/screens/workout/calendar_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

import 'support/test_db.dart';

Widget _app(Widget home, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: home),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('showAppSnack', () {
    testWidgets('shows the message and replaces the one on screen', (
      tester,
    ) async {
      late BuildContext captured;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      showAppSnack(captured, 'first');
      await tester.pump();
      expect(find.text('first'), findsOneWidget);

      showAppSnack(captured, 'second');
      await tester.pumpAndSettle();
      expect(find.text('first'), findsNothing);
      expect(find.text('second'), findsOneWidget);
    });

    testWidgets('runs the action', (tester) async {
      late BuildContext captured;
      var undone = false;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              captured = context;
              return const SizedBox();
            },
          ),
        ),
      );

      showAppSnack(
        captured,
        'removed',
        action: SnackBarAction(label: 'Undo', onPressed: () => undone = true),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('Undo'));
      expect(undone, isTrue);
    });
  });

  group('icon-only buttons have tooltips', () {
    testWidgets('planning stepper', (tester) async {
      await tester.pumpWidget(
        _app(
          PlanningStepper(value: '3', onDecrement: () {}, onIncrement: () {}),
        ),
      );
      expect(find.byTooltip('Decrease'), findsOneWidget);
      expect(find.byTooltip('Increase'), findsOneWidget);
    });

    testWidgets('planning stepper in Portuguese', (tester) async {
      await tester.pumpWidget(
        _app(
          PlanningStepper(value: '3', onDecrement: () {}, onIncrement: () {}),
          locale: 'pt',
        ),
      );
      expect(find.byTooltip('Diminuir'), findsOneWidget);
      expect(find.byTooltip('Aumentar'), findsOneWidget);
    });
  });

  group('calendar', () {
    setUp(() async {
      await installTestDb();
    });

    tearDown(() async {
      await uninstallTestDb();
    });

    Future<void> pumpCalendar(WidgetTester tester) async {
      // A phone-shaped surface: the calendar grid is square cells.
      tester.view.physicalSize = const Size(400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.runAsync(() async {
        await tester.pumpWidget(_app(const CalendarScreen()));
        await Future<void>.delayed(const Duration(milliseconds: 150));
        await tester.pump();
      });
    }

    testWidgets('month chevrons have tooltips', (tester) async {
      await pumpCalendar(tester);
      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
    });

    testWidgets('day cells are buttons labelled with date and status', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final now = DateTime.now();
      final today = dayOf(now);
      await tester.runAsync(() async {
        final db = await DatabaseHelper.instance.database;
        await db.insert('run_activities', {
          'id': 'run-today',
          'activity_type': 'run',
          'started_at': DateTime(
            now.year,
            now.month,
            now.day,
            7,
          ).toIso8601String(),
          'duration_seconds': 1800,
          'moving_time_seconds': 1800,
          'distance_meters': 5000.0,
          'avg_pace_sec_per_km': 360.0,
          'status': 'completed',
          'created_at': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        });
      });
      await pumpCalendar(tester);

      final label = DateFormat.yMMMMd('en_US').format(today);
      final loc = AppLocalizations.of(
        tester.element(find.byType(CalendarScreen)),
      )!;
      final withRun = find.bySemanticsLabel(
        '$label, ${loc.calendarLegendCompletedRun}',
      );
      expect(withRun, findsOneWidget);
      final data = tester.getSemantics(withRun).getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, ui.Tristate.isTrue);

      // A day without anything only announces its date.
      final other = DateTime(now.year, now.month, now.day == 1 ? 2 : 1);
      expect(
        find.bySemanticsLabel(DateFormat.yMMMMd('en_US').format(other)),
        findsOneWidget,
      );
      semantics.dispose();
    });
  });

  group('escalation label', () {
    testWidgets('is localized with units from the ARB files', (tester) async {
      late AppLocalizations en;
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) {
              en = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(formatEscalation(en, 15), '15 min');
      expect(formatEscalation(en, 60), '1 h');
      expect(formatEscalation(en, 90), '1 h 30 min');
    });
  });
}
