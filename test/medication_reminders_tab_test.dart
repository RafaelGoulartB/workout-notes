import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/medication.dart';
import 'package:workout_notes/repositories/medication_repository.dart';
import 'package:workout_notes/screens/alarms/medication_reminders_tab.dart';
import 'package:workout_notes/services/medication_reminder_service.dart';

import 'support/test_db.dart';

const _medicationChannel = MethodChannel('workout_notes/medication/methods');
const _sleepChannel = MethodChannel('workout_notes/sleep_monitor/methods');
const _notificationChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

/// 2026-09-29 is a Tuesday.
final _now = DateTime(2026, 9, 29, 9, 10);

Widget _app(Widget child, {String locale = 'en'}) => MaterialApp(
  locale: Locale(locale),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

/// Opens [MedicationEditorScreen] from a button and records what it popped.
class _EditorLauncher extends StatefulWidget {
  const _EditorLauncher({this.medication});

  final Medication? medication;

  @override
  State<_EditorLauncher> createState() => _EditorLauncherState();
}

class _EditorLauncherState extends State<_EditorLauncher> {
  bool? result;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        TextButton(
          onPressed: () async {
            final saved = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    MedicationEditorScreen(medication: widget.medication),
              ),
            );
            setState(() => result = saved);
          },
          child: const Text('open-editor'),
        ),
        Text('result: $result'),
      ],
    ),
  );
}

/// A repository whose writes can be switched off to exercise error paths.
class _FlakyMedicationRepository extends MedicationRepository {
  bool failReads = false;
  bool failWrites = false;

  @override
  Future<List<Medication>> getAll() {
    if (failReads) throw StateError('read failed');
    return super.getAll();
  }

  @override
  Future<Medication> insert({
    required String name,
    String? dosage,
    String? notes,
    required List<MedicationTime> times,
    required List<int> weekdays,
    required int escalationMinutes,
  }) {
    if (failWrites) throw StateError('write failed');
    return super.insert(
      name: name,
      dosage: dosage,
      notes: notes,
      times: times,
      weekdays: weekdays,
      escalationMinutes: escalationMinutes,
    );
  }

  @override
  Future<void> update(Medication medication) {
    if (failWrites) throw StateError('write failed');
    return super.update(medication);
  }
}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late Database db;
  late List<MethodCall> calls;
  late List<Map<String, Object?>> nativeStates;
  late bool permissionsGranted;
  late _FlakyMedicationRepository repository;

  MedicationReminderService service() => MedicationReminderService.instance;
  Iterable<MethodCall> called(String method) =>
      calls.where((call) => call.method == method);

  Future<Medication> seed({
    String name = 'Iron',
    String? dosage,
    List<MedicationTime> times = const [MedicationTime(9, 0)],
    List<int> weekdays = const [],
    int escalation = 30,
    bool enabled = true,
  }) async {
    final medication = await repository.insert(
      name: name,
      dosage: dosage,
      times: times,
      weekdays: weekdays,
      escalationMinutes: escalation,
    );
    if (!enabled) await repository.update(medication.copyWith(enabled: false));
    return medication;
  }

  /// Runs [body] as if on Android so the service mirrors to the native mocks.
  void androidTest(
    String name,
    Future<void> Function(WidgetTester tester) body,
  ) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await tester.binding.setSurfaceSize(const Size(500, 1200));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await body(tester);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  setUpAll(() {
    initSqfliteFfiForTests();
    AndroidFlutterLocalNotificationsPlugin.registerWith();
  });

  setUp(() async {
    db = await installTestDb();
    repository = _FlakyMedicationRepository();
    calls = [];
    nativeStates = [];
    permissionsGranted = true;
    service().overrideForTest(repository: repository, clock: () => _now);
    messenger.setMockMethodCallHandler(_medicationChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'states' => nativeStates,
        'spool' => <Object?>[],
        _ => null,
      };
    });
    messenger.setMockMethodCallHandler(_sleepChannel, (call) async {
      calls.add(call);
      if (call.method == 'getAlarmCapabilities') {
        return {
          'exact_alarm_granted': permissionsGranted,
          'full_screen_intent_granted': true,
        };
      }
      return null;
    });
    messenger.setMockMethodCallHandler(_notificationChannel, (call) async {
      calls.add(call);
      return switch (call.method) {
        'initialize' => true,
        'getNotificationChannels' => <Object?>[],
        'requestNotificationsPermission' => true,
        _ => null,
      };
    });
  });

  tearDown(() async {
    messenger.setMockMethodCallHandler(_notificationChannel, null);
    messenger.setMockMethodCallHandler(_medicationChannel, null);
    messenger.setMockMethodCallHandler(_sleepChannel, null);
    service().overrideForTest();
    await uninstallTestDb();
  });

  group('formatEscalation', () {
    test('uses minutes, whole hours and hours with minutes', () {
      final en = lookupAppLocalizations(const Locale('en'));
      final pt = lookupAppLocalizations(const Locale('pt'));
      expect(formatEscalation(en, 5), '5 min');
      expect(formatEscalation(en, 60), '1 h');
      expect(formatEscalation(en, 90), '1 h 30 min');
      expect(formatEscalation(pt, 120), '2 h');
      expect(
        medicationEscalationChoices,
        contains(Medication.defaultEscalationMinutes),
      );
    });
  });

  group('MedicationRemindersTab', () {
    testWidgets('shows the empty state without medications', (tester) async {
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('No medications yet'));

      expect(find.textContaining('Add a medication to get'), findsOneWidget);
      expect(find.text('Today'), findsNothing);
    });

    testWidgets('shows a retry when the medications cannot be read', (
      tester,
    ) async {
      repository.failReads = true;
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.byKey(const Key('load-error-retry')));
      expect(find.text('No medications yet'), findsNothing);

      repository.failReads = false;
      await tester.tap(find.byKey(const Key('load-error-retry')));
      await _pumpUntil(tester, find.text('No medications yet'));
    });

    androidTest('lists today doses with their state and the medication cards', (
      tester,
    ) async {
      final iron = (await tester.runAsync(
        () => seed(
          dosage: '50 mg',
          times: const [
            MedicationTime(21, 0),
            MedicationTime(7, 0),
            MedicationTime(9, 0),
          ],
        ),
      ))!;
      await tester.runAsync(() async {
        // Monday and Wednesday only: nothing is due on this Tuesday.
        await seed(
          name: 'Vitamin D',
          times: const [MedicationTime(12, 0)],
          weekdays: const [1, 3],
          escalation: 90,
        );
        await seed(
          name: 'Paused',
          times: const [MedicationTime(10, 0)],
          enabled: false,
        );
      });
      // The 09:00 reminder fired and waits for a confirmation.
      nativeStates.add({
        'slot_id': iron.slotId(const MedicationTime(9, 0)),
        'state': 'awaiting',
        'pending_dose_key': '2026-09-29T09:00',
      });

      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('0 of 3 doses taken'));

      // Dose rows are in time order with the dosage in front of the state.
      expect(find.text('50 mg · Late'), findsOneWidget);
      expect(find.text('50 mg · Waiting for confirmation'), findsOneWidget);
      expect(find.text('50 mg · Upcoming'), findsOneWidget);
      final rows = [
        for (final time in ['07:00', '09:00', '21:00'])
          tester.getTopLeft(find.text(time).first).dy,
      ];
      expect(rows, orderedEquals([...rows]..sort()));
      // Disabled and off-day medications have no dose today.
      expect(
        find.byKey(Key('medication-dose-${iron.id}@0700')),
        findsOneWidget,
      );
      expect(find.text('10:00'), findsOneWidget); // only the Paused card pill
      expect(find.text('12:00'), findsOneWidget); // only the Vitamin D pill

      expect(find.text('YOUR MEDICATIONS'), findsOneWidget);
      expect(find.text('Every day · Alarm after 30 min'), findsNWidgets(2));
      expect(find.text('Mon, Wed · Alarm after 1 h 30 min'), findsOneWidget);
      // Enabled medications switch on, the paused one off.
      final switches = tester
          .widgetList<Switch>(find.byType(Switch))
          .map((s) => s.value);
      expect(switches, [true, true, false]);
      // Every enabled time was mirrored to Android on startup.
      expect(called('schedule'), hasLength(4));
      expect(called('restore'), hasLength(1));
    });

    androidTest('taking, skipping and undoing a dose', (tester) async {
      final med = (await tester.runAsync(
        () => seed(
          name: 'Metformin',
          times: const [MedicationTime(8, 0), MedicationTime(21, 0)],
        ),
      ))!;
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('0 of 2 doses taken'));

      await tester.tap(find.text('I took it').first);
      await _pumpUntil(tester, find.text('1 of 2 doses taken'));

      final confirm = called('confirm').single.arguments as Map;
      expect(confirm['slot_id'], '${med.id}@0800');
      expect(confirm['dose_key'], '2026-09-29T08:00');
      expect(confirm['status'], 'taken');
      // Recorded at the (fixed) clock, shown with the active clock format.
      expect(find.textContaining('Taken at'), findsOneWidget);
      var doses = (await tester.runAsync(() => db.query('medication_doses')))!;
      expect(doses.single['status'], 'taken');

      // Skip the evening dose from its overflow menu.
      await tester.tap(find.byType(PopupMenuButton<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Skip dose'));
      await tester.pump();
      await _pumpUntil(tester, find.text('Skipped'));
      expect((called('confirm').last.arguments as Map)['status'], 'skipped');
      // Answered doses offer Undo instead of the confirm actions.
      expect(find.text('Undo'), findsNWidgets(2));
      expect(find.text('I took it'), findsNothing);
      // Skipped doses only count as taken when taken.
      expect(find.text('1 of 2 doses taken'), findsOneWidget);

      await tester.tap(find.text('Undo').first);
      await _pumpUntil(tester, find.text('0 of 2 doses taken'));
      doses = (await tester.runAsync(() => db.query('medication_doses')))!;
      expect(doses.single['status'], 'skipped');
      expect(find.text('Late'), findsOneWidget);
    });

    androidTest('the switch pauses a medication and cancels its slots', (
      tester,
    ) async {
      final med = (await tester.runAsync(
        () => seed(name: 'Omeprazole', times: const [MedicationTime(7, 0)]),
      ))!;
      nativeStates.add({
        'slot_id': med.slotId(const MedicationTime(7, 0)),
        'state': 'scheduled',
      });
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('0 of 1 doses taken'));

      await tester.tap(find.byType(Switch));
      await _pumpUntil(tester, find.text('No doses scheduled for today'));

      final row = (await tester.runAsync(() => db.query('medications')))!;
      expect(row.single['enabled'], 0);
      expect(called('cancel').single.arguments, {
        'slot_id': med.slotId(const MedicationTime(7, 0)),
      });
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

      // Turning it back on asks for the alarm permissions first.
      await tester.tap(find.byType(Switch));
      await _pumpUntil(tester, find.text('0 of 1 doses taken'));
      expect(called('getAlarmCapabilities'), isNotEmpty);
      final enabled = (await tester.runAsync(() => db.query('medications')))!;
      expect(enabled.single['enabled'], 1);
    });

    androidTest('enabling stays off while alarm permissions are missing', (
      tester,
    ) async {
      permissionsGranted = false;
      await tester.runAsync(
        () => seed(
          name: 'Paused',
          times: const [MedicationTime(7, 0)],
          enabled: false,
        ),
      );
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('Paused'));

      await tester.tap(find.byType(Switch));
      await _pumpUntil(
        tester,
        find.text('Allow notifications and exact alarms to continue.'),
      );

      expect(called('requestExactAlarmPermission'), hasLength(1));
      final row = (await tester.runAsync(() => db.query('medications')))!;
      expect(row.single['enabled'], 0);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
    });

    androidTest('a failing toggle reports the error and stays usable', (
      tester,
    ) async {
      await tester.runAsync(() => seed(name: 'Iron'));
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('0 of 1 doses taken'));

      repository.failWrites = true;
      await tester.tap(find.byType(Switch));
      await _pumpUntil(tester, find.text('Could not save the medication.'));
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
      // The busy lock is released so the switch can be used again.
      expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    });

    androidTest('deleting asks for confirmation and removes the history', (
      tester,
    ) async {
      final med = (await tester.runAsync(() async {
        final med = await seed(name: 'Doomed');
        await seed(name: 'Keeper', times: const [MedicationTime(22, 0)]);
        await repository.recordDose(
          medicationId: med.id,
          doseKey: '2026-09-29T09:00',
          scheduledAt: DateTime(2026, 9, 29, 9),
          status: MedicationDoseStatus.taken,
        );
        return med;
      }))!;
      await tester.pumpWidget(_app(const MedicationRemindersTab()));
      await _pumpUntil(tester, find.text('Keeper'));

      Future<void> openDelete() async {
        // Each card has its own overflow menu; the cards come after the
        // dose rows' menus (one per unanswered dose).
        await tester.tap(find.byType(PopupMenuButton<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete').last);
        await tester.pumpAndSettle();
      }

      // "Keeper" sorts after "Doomed" so the last menu belongs to it; cancel.
      await openDelete();
      expect(find.text('Delete medication?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        await tester.runAsync(() => db.query('medications')),
        hasLength(2),
      );

      // Delete "Keeper" for real, then the remaining one.
      await openDelete();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await _pumpUntilGone(tester, find.text('Keeper'));
      expect(find.text('Doomed'), findsWidgets);

      await openDelete();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pump();
      await _pumpUntil(tester, find.text('No medications yet'));
      expect(await tester.runAsync(() => db.query('medications')), isEmpty);
      expect(
        await tester.runAsync(() => db.query('medication_doses')),
        isEmpty,
      );
      // The native slots are reconciled away with the medication.
      expect(
        called(
          'schedule',
        ).where((c) => (c.arguments as Map)['medication_id'] == med.id),
        isNotEmpty,
      );
    });

    testWidgets('renders in Portuguese', (tester) async {
      await tester.runAsync(
        () => seed(
          name: 'Losartana',
          dosage: '50 mg',
          times: const [MedicationTime(7, 0)],
          weekdays: const [2, 4],
          escalation: 120,
        ),
      );
      await tester.pumpWidget(
        _app(const MedicationRemindersTab(), locale: 'pt'),
      );
      await _pumpUntil(tester, find.text('SEUS REMÉDIOS'));

      final pt = lookupAppLocalizations(const Locale('pt'));
      expect(find.text(pt.medicationToday.toUpperCase()), findsOneWidget);
      expect(find.text(pt.medicationTodayProgress(0, 1)), findsOneWidget);
      expect(find.text('50 mg · ${pt.medicationStateOverdue}'), findsOneWidget);
      expect(find.text(pt.medicationTake), findsOneWidget);
      expect(
        find.text(
          '${pt.alarmWeekTue}, ${pt.alarmWeekThu} · '
          '${pt.medicationEscalationChip('2 h')}',
        ),
        findsOneWidget,
      );
    });
  });

  group('MedicationEditorScreen', () {
    androidTest('validates the name and creates a medication', (tester) async {
      await tester.pumpWidget(_app(const _EditorLauncher()));
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();

      expect(find.text('New medication'), findsOneWidget);
      // One default time of 08:00, 30 min escalation, no day selected.
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Enter the medication name'), findsOneWidget);
      expect(await tester.runAsync(() => db.query('medications')), isEmpty);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medication name'),
        '  Losartan ',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dose (optional)'),
        '50 mg',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Notes (optional)'),
        'With breakfast',
      );
      // Add a second time: the picker opens 12 h after the last one (20:00).
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('20:00'), findsOneWidget);
      // Adding the same suggestion again is rejected (08:00 is 12 h later).
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('That time is already added'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);
      // Days: Mon and Thu, in selection-independent order.
      await tester.ensureVisible(find.text('Thu'));
      await tester.tap(find.text('Thu'));
      await tester.tap(find.text('Mon'));
      await tester.pump();
      // Escalation: pick one hour.
      await tester.ensureVisible(find.text('30 min'));
      await tester.tap(find.text('30 min'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('1 h').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pump();
      await _pumpUntil(tester, find.text('result: true'));

      final rows = (await tester.runAsync(() => db.query('medications')))!;
      expect(rows.single['name'], 'Losartan');
      expect(rows.single['dosage'], '50 mg');
      expect(rows.single['notes'], 'With breakfast');
      expect(rows.single['weekdays_json'], '[1,4]');
      expect(rows.single['escalation_minutes'], 60);
      expect(rows.single['times_json'], contains('"h":20'));
      // Both reminder times were mirrored to Android with their settings.
      final scheduled = called('schedule').map((c) => c.arguments as Map);
      expect(scheduled.map((a) => a['hour']), unorderedEquals([8, 20]));
      expect(scheduled.first['weekdays'], [1, 4]);
      expect(scheduled.first['escalation_minutes'], 60);
    });

    androidTest('removes and changes times, never the last one', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _EditorLauncher()));
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();

      // A single time has no delete affordance.
      expect(find.byIcon(Icons.clear), findsNothing);
      await tester.tap(find.text('Add time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('20:00'), findsOneWidget);

      // Re-confirming a time in its own picker keeps it (no duplicate error).
      await tester.tap(find.text('20:00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('20:00'), findsOneWidget);
      expect(find.text('08:00'), findsOneWidget);

      final chips = tester.widgetList<InputChip>(find.byType(InputChip));
      expect(chips.every((chip) => chip.onDeleted != null), isTrue);
      await tester.tap(find.byIcon(Icons.clear).first);
      await tester.pump();
      expect(find.text('08:00'), findsNothing);
      expect(find.text('20:00'), findsOneWidget);
      expect(
        tester.widget<InputChip>(find.byType(InputChip)).onDeleted,
        isNull,
      );
    });

    androidTest('editing updates the stored medication and clears blanks', (
      tester,
    ) async {
      final med = (await tester.runAsync(
        () => seed(
          name: 'Old name',
          dosage: '10 mg',
          times: const [MedicationTime(7, 30)],
          weekdays: const [2],
          escalation: 45,
        ),
      ))!;
      await tester.pumpWidget(_app(_EditorLauncher(medication: med)));
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();

      expect(find.text('Edit medication'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Old name'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '10 mg'), findsOneWidget);
      expect(find.text('07:30'), findsOneWidget);
      expect(find.text('45 min'), findsOneWidget);
      expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'Tue'))
            .selected,
        isTrue,
      );

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Old name'),
        'New name',
      );
      await tester.enterText(find.widgetWithText(TextFormField, '10 mg'), '  ');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await _pumpUntil(tester, find.text('result: true'));

      final row = (await tester.runAsync(
        () => db.query('medications'),
      ))!.single;
      expect(row['id'], med.id);
      expect(row['name'], 'New name');
      expect(row['dosage'], isNull);
      expect(row['escalation_minutes'], 45);
      expect(
        called('schedule').single.arguments,
        containsPair('name', 'New name'),
      );
    });

    androidTest('keeps the form and explains when saving is not possible', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const _EditorLauncher()));
      await tester.tap(find.text('open-editor'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Medication name'),
        'Iron',
      );

      // Missing alarm permissions: nothing is saved.
      permissionsGranted = false;
      await tester.tap(find.text('Save'));
      await _pumpUntil(
        tester,
        find.text('Allow notifications and exact alarms to continue.'),
      );
      expect(await tester.runAsync(() => db.query('medications')), isEmpty);
      expect(find.text('New medication'), findsOneWidget); // still editing
      // Clear the first message so the next one is not queued behind it.
      ScaffoldMessenger.of(
        tester.element(find.text('New medication')),
      ).clearSnackBars();
      await tester.pumpAndSettle();

      // A storage failure shows the generic error and the button recovers.
      permissionsGranted = true;
      repository.failWrites = true;
      await tester.tap(find.text('Save'));
      await _pumpUntil(tester, find.text('Could not save the medication.'));
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Save'))
            .onPressed,
        isNotNull,
      );
      expect(find.text('New medication'), findsOneWidget);

      repository.failWrites = false;
      await tester.tap(find.text('Save'));
      await _pumpUntil(tester, find.text('result: true'));
      expect(
        await tester.runAsync(() => db.query('medications')),
        hasLength(1),
      );
    });

    testWidgets('renders in Portuguese', (tester) async {
      await tester.pumpWidget(
        _app(const MedicationEditorScreen(), locale: 'pt'),
      );
      await tester.pump();
      final pt = lookupAppLocalizations(const Locale('pt'));
      expect(find.text(pt.medicationNew), findsOneWidget);
      expect(find.text(pt.medicationName), findsOneWidget);
      expect(find.text(pt.alarmWeekMon), findsOneWidget);
      await tester.tap(find.text(pt.medicationSave));
      await tester.pump();
      expect(find.text(pt.medicationNameRequired), findsOneWidget);
    });
  });
}
