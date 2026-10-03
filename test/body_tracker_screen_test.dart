import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/screens/body/body_stats_screen.dart';
import 'package:workout_notes/screens/body/body_tracker_dialogs.dart';
import 'package:workout_notes/screens/body/body_tracker_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/body_tracker/body_tracker_selectors.dart';
import 'package:workout_notes/widgets/body_tracker/measurement_card.dart';

import 'support/goals_ui_support.dart';
import 'support/test_db.dart';

void main() {
  late DatabaseHelper helper;

  setUpAll(() async {
    initSqfliteFfiForTests();
    await initDateSymbolsForTests();
  });

  setUp(() async {
    await installTestDb();
    helper = DatabaseHelper.instance;
  });
  tearDown(uninstallTestDb);

  Future<void> add(
    WidgetTester tester,
    String type,
    double value,
    DateTime date, {
    String? unit,
    double? secondary,
    String? comment,
    String? timeOfDay,
    bool fasted = false,
    String? side,
  }) async {
    final measureType = kBodyMeasureTypes.firstWhere((t) => t.id == type);
    await tester.runAsync(
      () => helper.bodyMeasurementRepo.addBodyMeasurement(
        type,
        value,
        unit ?? measureType.unit,
        secondaryValue: secondary,
        date: date,
        comment: comment,
        timeOfDay: timeOfDay,
        isFasted: fasted,
        side: side,
      ),
    );
  }

  Future<List<Map<String, dynamic>>> stored(
    WidgetTester tester, {
    String? type,
  }) async => (await tester.runAsync(
    () => helper.bodyMeasurementRepo.getBodyMeasurements(type: type),
  ))!;

  Future<void> pumpScreen(
    WidgetTester tester, {
    Locale locale = const Locale('en'),
  }) async {
    useLogicalViewSize(tester, const Size(600, 3000));
    await tester.pumpWidget(
      goalsApp(const BodyTrackerScreen(), locale: locale),
    );
    await settleDb(tester);
  }

  /// Opens the speed dial and taps the round button of one option. Only the
  /// button reacts: tapping the label beside it lands on the scrim.
  Future<void> speedDial(WidgetTester tester, {required bool quick}) async {
    await tester.tap(find.byType(FloatingActionButton));
    // The first pump starts the open animation, the second one finishes it.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(
      find.byIcon(quick ? Icons.bolt : Icons.add_circle_outline),
    );
    await settleDb(tester);
  }

  /// Picks a type in the measurement picker, whose grid shows the first word
  /// of the type name.
  Future<void> pickType(WidgetTester tester, String typeLabel) async {
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text(typeLabel),
      ),
    );
    await settleDb(tester);
  }

  /// The text field in the quick-measure row titled [label].
  Finder quickField(String label) => find.descendant(
    of: find.widgetWithText(ListTile, label),
    matching: find.byType(TextFormField),
  );

  final sep1 = DateTime(2026, 9, 1);
  final sep8 = DateTime(2026, 9, 8);
  final sep15 = DateTime(2026, 9, 15);

  group('BodyTrackerScreen', () {
    testWidgets('shows the empty state and opens quick measure from it', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text('Body Measurements'), findsOneWidget);
      expect(find.text('No measurements yet'), findsOneWidget);
      expect(find.textContaining('Start tracking'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Quick Measure'));
      await settleDb(tester);

      expect(
        find.text(
          'Fill in the measurements you want to record. Leave blank to skip.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('shows summary, quick stats and the history', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await add(tester, 'weight', 79, sep8, comment: 'Morning check');
      await add(tester, 'weight', 78.5, sep15, fasted: true);
      await pumpScreen(tester);

      // Type selector with the latest value.
      expect(find.text('Body Weight'), findsWidgets);
      // Summary: latest value and the change from the previous entry.
      expect(find.text('78.5'), findsWidgets);
      expect(find.text('-0.5'), findsOneWidget);
      // Quick stats: min, max, average (79.17) and the count.
      expect(find.text('Min'), findsOneWidget);
      expect(find.text('Max'), findsOneWidget);
      expect(find.text('80.0'), findsWidgets);
      expect(find.text('79.2'), findsOneWidget);
      // History, newest first.
      expect(find.text('History · 3 entries'), findsOneWidget);
      final cards = tester
          .widgetList<BodyMeasurementCard>(find.byType(BodyMeasurementCard))
          .map((c) => c.measurement['value'])
          .toList();
      expect(cards, [78.5, 79.0, 80.0]);
      expect(find.text('Morning check'), findsOneWidget);
    });

    testWidgets('history is paginated five entries at a time', (tester) async {
      for (var i = 0; i < 12; i++) {
        await add(tester, 'weight', 80 + i * 0.1, DateTime(2026, 8, 1 + i));
      }
      await pumpScreen(tester);

      expect(find.byType(BodyMeasurementCard), findsNWidgets(5));
      expect(find.text('Load 7 more entries'), findsOneWidget);

      await tester.tap(find.text('Load 7 more entries'));
      await tester.pump();
      expect(find.byType(BodyMeasurementCard), findsNWidgets(10));
      // With five or fewer left the label gets shorter.
      expect(find.text('Load 2 more'), findsOneWidget);

      await tester.tap(find.text('Load 2 more'));
      await tester.pump();
      expect(find.byType(BodyMeasurementCard), findsNWidgets(12));
      expect(find.textContaining('Load'), findsNothing);
    });

    testWidgets('switching the type shows that type\'s data', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await add(tester, 'waist', 90.5, sep1);
      await add(tester, 'waist', 89, sep8);
      await pumpScreen(tester);

      await pickType(tester, 'Waist');

      expect(find.text('History · 2 entries'), findsOneWidget);
      expect(find.text('89.0'), findsWidgets);
      expect(find.text('90.5 cm'), findsOneWidget);
      // The picker label is now the selected type.
      expect(find.text('Waist'), findsWidgets);
      // Body composition belongs to weight only.
      expect(find.text('Estimated Body Composition'), findsNothing);
    });

    testWidgets('bilateral types filter the history by side', (tester) async {
      await add(tester, 'arm', 35, sep1, side: 'left');
      await add(tester, 'arm', 34, sep8, side: 'left');
      await add(tester, 'arm', 36, sep8, side: 'right');
      await pumpScreen(tester);
      await pickType(tester, 'Arm');

      expect(find.text('History · 3 entries'), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('L'), findsWidgets);
      expect(find.text('R'), findsWidgets);

      await tester.tap(find.widgetWithText(InkWell, 'R').first);
      await tester.pump();
      expect(find.text('History · 1 entries'), findsOneWidget);
      expect(find.byType(BodyMeasurementCard), findsOneWidget);

      await tester.tap(find.widgetWithText(InkWell, 'L').first);
      await tester.pump();
      expect(find.text('History · 2 entries'), findsOneWidget);
      expect(find.byType(BodyMeasurementCard), findsNWidgets(2));

      await tester.tap(find.widgetWithText(InkWell, 'All').first);
      await tester.pump();
      expect(find.text('History · 3 entries'), findsOneWidget);
    });

    testWidgets('the delta compares entries of the same side only', (
      tester,
    ) async {
      await add(tester, 'arm', 35, sep1, side: 'left');
      await add(tester, 'arm', 40, sep8, side: 'right');
      await add(tester, 'arm', 36, sep15, side: 'left');
      await pumpScreen(tester);
      await pickType(tester, 'Arm');

      final deltas = tester
          .widgetList<BodyMeasurementCard>(find.byType(BodyMeasurementCard))
          .map((c) => c.delta)
          .toList();
      // Newest first: left 36 vs left 35, right 40 has no previous right,
      // left 35 has no previous entry.
      expect(deltas, [1.0, null, null]);
    });

    testWidgets('long press deletes an entry after confirmation', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await add(tester, 'weight', 79, sep8);
      await pumpScreen(tester);

      await tester.longPress(find.byType(BodyMeasurementCard).first);
      await tester.pumpAndSettle();
      expect(find.text('Delete this measurement?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await settleDb(tester);
      expect(await stored(tester), hasLength(2));

      await tester.longPress(find.byType(BodyMeasurementCard).first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);

      final rows = await stored(tester);
      expect(rows.map((r) => r['value']), [80.0]);
      expect(find.byType(BodyMeasurementCard), findsOneWidget);
    });

    testWidgets('deleting the last entry returns to the empty state', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);

      await tester.longPress(find.byType(BodyMeasurementCard));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);

      expect(find.text('No measurements yet'), findsOneWidget);
    });

    testWidgets('the stats button opens the progress stats', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);

      await tester.tap(find.byTooltip('Progress stats'));
      await settleDb(tester);

      expect(find.byType(BodyStatsScreen), findsOneWidget);
    });

    testWidgets('a failed load shows an error, not the empty state', (
      tester,
    ) async {
      await tester.runAsync(() async {
        await (await helper.database).execute('DROP TABLE body_measurements');
      });
      await pumpScreen(tester);

      expect(find.text('Could not load your data.'), findsOneWidget);
      expect(find.text('No measurements yet'), findsNothing);
      // No add button while the data is unreadable.
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('renders in Portuguese', (tester) async {
      await pumpScreen(tester, locale: const Locale('pt'));

      expect(find.text('Medidas Corporais'), findsOneWidget);
      expect(find.text('Nenhuma medida ainda'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Medir Agora'), findsOneWidget);
    });

    testWidgets('customizing the types hides the unticked ones', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Customize'));
      await tester.pumpAndSettle();
      expect(find.text('Customize Measurements'), findsOneWidget);

      await tester.tap(find.widgetWithText(SwitchListTile, 'Waist'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await settleDb(tester);

      final saved = await tester.runAsync(
        () => helper.settingsRepo.getSetting('body_tracker_enabled_types'),
      );
      expect(saved!.split(','), isNot(contains('waist')));
      expect(saved.split(','), contains('weight'));

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Waist'),
        ),
        findsNothing,
      );
    });

    testWidgets('hidden types stay hidden the next time the screen opens', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await tester.runAsync(
        () => helper.settingsRepo.setSetting(
          'body_tracker_enabled_types',
          'weight,bodyFat',
        ),
      );
      await pumpScreen(tester);

      await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('Waist'),
        ),
        findsNothing,
      );
    });
  });

  group('add measurement sheet', () {
    testWidgets('validates the value and saves with every option', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);

      await speedDial(tester, quick: false);
      expect(find.text('Add Body Weight'), findsWidgets);

      // An empty value is rejected inline.
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Invalid value'), findsOneWidget);
      expect(await stored(tester), hasLength(1));

      await tester.enterText(find.byType(TextFormField).first, '81,5');
      await tester.enterText(find.byType(TextFormField).last, 'after run');
      await tester.tap(find.text('Fasting'));
      await tester.pump();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Morning').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      expect(find.text('✅ Measurement saved!'), findsOneWidget);
      final rows = await stored(tester, type: 'weight');
      expect(rows, hasLength(2));
      final created = rows.firstWhere((r) => r['value'] == 81.5);
      expect(created['unit'], 'kg');
      expect(created['comment'], 'after run');
      expect(created['time_of_day'], 'morning');
      expect(created['is_fasted'], 1);
      expect(created['date'], dateKey(DateTime.now()));
      expect(created['side'], isNull);
      // The list reloads with the new entry on top.
      expect(find.text('History · 2 entries'), findsOneWidget);
    });

    testWidgets('a past date can be picked', (tester) async {
      useLogicalViewSize(tester, const Size(600, 3000));
      final type = kBodyMeasureTypes.first;
      await tester.pumpWidget(
        goalsApp(
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddMeasurementSheet(
                  context,
                  repo: helper.bodyMeasurementRepo,
                  currentType: type,
                  typeId: type.id,
                  onSaved: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await settleDb(tester);

      final now = DateTime.now();
      await tester.tap(
        find.text(DateFormat.yMMMd(Intl.defaultLocale).format(now)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('1').first);
      await tester.pump();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField).first, '70');
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      final rows = await stored(tester);
      expect(rows.single['date'], dateKey(DateTime(now.year, now.month, 1)));
    });

    testWidgets('blood pressure needs both values and stores both', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);
      await pickType(tester, 'Blood');

      await speedDial(tester, quick: false);
      expect(find.text('Systolic'), findsOneWidget);
      expect(find.text('Diastolic'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Systolic'),
        '120',
      );
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Invalid value'), findsOneWidget);
      expect(await stored(tester, type: 'bloodPressure'), isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Diastolic'),
        '80',
      );
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      final row = (await stored(tester, type: 'bloodPressure')).single;
      expect(row['value'], 120.0);
      expect(row['secondary_value'], 80.0);
      expect(row['unit'], 'mmHg');
      // The summary shows both numbers.
      expect(find.text('120/80 mmHg'), findsWidgets);
    });

    testWidgets('bilateral types save the chosen side', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);
      await pickType(tester, 'Arm');

      await speedDial(tester, quick: false);
      await tester.enterText(find.byType(TextFormField).first, '36.5');
      await tester.tap(
        find.descendant(
          of: find.byType(SideSelector),
          matching: find.text('Left'),
        ),
      );
      await tester.pump();
      await tester.tap(find.text('Save'));
      await settleDb(tester);

      final row = (await stored(tester, type: 'arm')).single;
      expect(row['value'], 36.5);
      expect(row['side'], 'left');
    });

    testWidgets('renders in Portuguese', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester, locale: const Locale('pt'));

      await speedDial(tester, quick: false);
      expect(find.text('Adicionar Peso Corporal'), findsWidgets);
      expect(find.text('Jejum'), findsOneWidget);

      await tester.tap(find.text('Salvar'));
      await tester.pump();
      expect(find.text('Valor inválido'), findsOneWidget);
    });
  });

  group('quick measure sheet', () {
    testWidgets('saves only the filled fields in one batch', (tester) async {
      await add(tester, 'weight', 78, sep1);
      await pumpScreen(tester);
      await speedDial(tester, quick: true);

      // Nothing to save yet.
      final saveAll = find.widgetWithText(FilledButton, 'Save Measurements');
      expect(tester.widget<FilledButton>(saveAll).onPressed, isNull);
      // The last known value of each type is offered as a reference.
      expect(find.text('Last: 78.0 kg'), findsOneWidget);

      await tester.enterText(quickField('Body Weight'), '80,5');
      await tester.enterText(quickField('Waist'), '90');
      await tester.enterText(quickField('Arm L.'), '35');
      await tester.pump();
      expect(tester.widget<FilledButton>(saveAll).onPressed, isNotNull);

      await tester.tap(find.text('Fasted'));
      await tester.tap(find.text('Morning'));
      await tester.pump();
      await tester.tap(saveAll);
      await settleDb(tester);

      expect(find.text('✅ 3 measurements saved!'), findsOneWidget);
      final rows = await stored(tester);
      final byType = {
        for (final r in rows.where((r) => r['date'] == dateKey(DateTime.now())))
          r['type'] as String: r,
      };
      expect(byType.keys, unorderedEquals(['weight', 'waist', 'arm']));
      expect(byType['weight']!['value'], 80.5);
      expect(byType['waist']!['value'], 90.0);
      expect(byType['arm']!['side'], 'left');
      expect(byType['arm']!['value'], 35.0);
      for (final row in byType.values) {
        expect(row['is_fasted'], 1);
        expect(row['time_of_day'], 'morning');
      }
    });

    testWidgets('an incomplete blood pressure explains why nothing saved', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Quick Measure'));
      await settleDb(tester);

      await tester.enterText(quickField('Systolic'), '118');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save Measurements'));
      await settleDb(tester);

      expect(find.text('Invalid value'), findsOneWidget);
      expect(await stored(tester), isEmpty);
    });

    testWidgets('blood pressure and right-side values are stored whole', (
      tester,
    ) async {
      await pumpScreen(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Quick Measure'));
      await settleDb(tester);

      await tester.enterText(quickField('Systolic'), '118');
      await tester.enterText(quickField('Diastolic'), '76');
      await tester.enterText(quickField('Thigh R.'), '55,5');
      // Zero and junk are skipped rather than stored.
      await tester.enterText(quickField('Hip'), '0');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Quick note (optional)'),
        'evening check',
      );
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Save Measurements'));
      await settleDb(tester);

      expect(find.text('✅ 2 measurements saved!'), findsOneWidget);
      final rows = await stored(tester);
      final pressure = rows.firstWhere((r) => r['type'] == 'bloodPressure');
      expect(pressure['value'], 118.0);
      expect(pressure['secondary_value'], 76.0);
      expect(pressure['comment'], 'evening check');
      final thigh = rows.firstWhere((r) => r['type'] == 'thigh');
      expect(thigh['side'], 'right');
      expect(thigh['value'], 55.5);
      expect(rows.where((r) => r['type'] == 'hip'), isEmpty);
    });

    testWidgets('renders in Portuguese', (tester) async {
      await pumpScreen(tester, locale: const Locale('pt'));
      await tester.tap(find.widgetWithText(FilledButton, 'Medir Agora'));
      await settleDb(tester);

      expect(find.text('Anotação rápida (opcional)'), findsOneWidget);
      expect(find.text('Salvar Medidas'), findsOneWidget);
      expect(find.text('Em jejum'), findsOneWidget);
    });
  });

  group('measurement detail sheet', () {
    testWidgets('shows the full entry and deletes it after confirming', (
      tester,
    ) async {
      await add(tester, 'weight', 80, sep1);
      await add(
        tester,
        'weight',
        78.5,
        sep15,
        comment: 'Post holiday',
        timeOfDay: 'morning',
        fasted: true,
      );
      await pumpScreen(tester);

      await tester.tap(find.text('Post holiday'));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.text('Body Weight')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: sheet,
          matching: find.text(
            DateFormat.yMMMd(Intl.defaultLocale).format(sep15),
          ),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('78.5')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('-1.5 kg')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Post holiday')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Fasting')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: sheet, matching: find.text('Morning')),
        findsOneWidget,
      );

      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this measurement?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await settleDb(tester);

      final rows = await stored(tester);
      expect(rows.map((r) => r['value']), [80.0]);
      expect(find.text('Post holiday'), findsNothing);
    });

    testWidgets('a blood pressure entry shows both values without a unit', (
      tester,
    ) async {
      await add(tester, 'bloodPressure', 120, sep1, secondary: 80);
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);
      await pickType(tester, 'Blood');

      await tester.tap(find.byType(BodyMeasurementCard));
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('120/80 mmHg'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the delete keeps the entry', (tester) async {
      await add(tester, 'weight', 80, sep1);
      await pumpScreen(tester);

      await tester.tap(find.byType(BodyMeasurementCard));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await settleDb(tester);

      expect(await stored(tester), hasLength(1));
      expect(find.byType(BodyMeasurementCard), findsOneWidget);
    });
  });
}
