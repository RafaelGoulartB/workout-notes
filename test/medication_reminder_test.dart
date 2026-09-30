import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';
import 'package:workout_notes/models/medication.dart';
import 'package:workout_notes/repositories/medication_repository.dart';
import 'package:workout_notes/services/medication_reminder_service.dart';
import 'support/test_db.dart';

const _channel = MethodChannel('workout_notes/medication/methods');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Database database;
  late MedicationRepository repository;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    database = await databaseFactory.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 55,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: DatabaseSchema.onCreate,
      ),
    );
    DatabaseHelper.overrideDatabase = database;
    repository = MedicationRepository();
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
    MedicationReminderService.instance.overrideForTest();
    DatabaseHelper.overrideDatabase = null;
    await database.close();
  });

  group('Medication model', () {
    test('dose keys match the Android format', () {
      expect(
        Medication.doseKey(DateTime(2026, 9, 29, 8, 5)),
        '2026-09-29T08:05',
      );
      expect(
        Medication.parseDoseKey('2026-09-29T08:05'),
        DateTime(2026, 9, 29, 8, 5),
      );
    });

    test('doses follow the selected weekdays', () async {
      final medication = await repository.insert(
        name: 'Vitamin D',
        times: const [MedicationTime(20, 0), MedicationTime(8, 0)],
        weekdays: const [1, 3],
        escalationMinutes: 30,
      );
      // 2026-09-28 is a Monday, 2026-09-29 a Tuesday.
      expect(medication.dosesOn(DateTime(2026, 9, 28)), [
        DateTime(2026, 9, 28, 8),
        DateTime(2026, 9, 28, 20),
      ]);
      expect(medication.dosesOn(DateTime(2026, 9, 29)), isEmpty);
      expect(
        medication.slotId(const MedicationTime(8, 0)),
        '${medication.id}@0800',
      );
    });

    test('round-trips through SQLite', () async {
      final created = await repository.insert(
        name: '  Losartan ',
        dosage: '50 mg',
        notes: ' ',
        times: const [MedicationTime(21, 30)],
        weekdays: const [],
        escalationMinutes: 45,
      );
      final loaded = (await repository.getAll()).single;
      expect(loaded.id, created.id);
      expect(loaded.name, 'Losartan');
      expect(loaded.dosage, '50 mg');
      expect(loaded.notes, isNull);
      expect(loaded.times, const [MedicationTime(21, 30)]);
      expect(loaded.everyDay, isTrue);
      expect(loaded.escalationMinutes, 45);
      expect(loaded.enabled, isTrue);
    });
  });

  group('MedicationRepository', () {
    test('records one answer per dose and deletes the log with it', () async {
      final medication = await repository.insert(
        name: 'Omeprazole',
        times: const [MedicationTime(7, 0)],
        weekdays: const [],
        escalationMinutes: 30,
      );
      final due = DateTime(2026, 9, 29, 7);
      final key = Medication.doseKey(due);
      await repository.recordDose(
        medicationId: medication.id,
        doseKey: key,
        scheduledAt: due,
        status: MedicationDoseStatus.skipped,
      );
      await repository.recordDose(
        medicationId: medication.id,
        doseKey: key,
        scheduledAt: due,
        status: MedicationDoseStatus.taken,
      );
      final doses = await repository.getDoses(
        from: DateTime(2026, 9, 29),
        to: DateTime(2026, 9, 30),
      );
      expect(doses, hasLength(1));
      expect(doses.single.status, MedicationDoseStatus.taken);

      await repository.delete(medication.id);
      expect(
        await repository.getDoses(
          from: DateTime(2026, 9, 29),
          to: DateTime(2026, 9, 30),
        ),
        isEmpty,
      );
    });
  });

  group('MedicationReminderService', () {
    late List<MethodCall> calls;
    late List<Map<String, Object?>> spool;
    late List<Map<String, Object?>> nativeStates;

    void mockNative() {
      calls = [];
      spool = [];
      nativeStates = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'spool':
                return spool;
              case 'states':
                return nativeStates;
              case 'confirm':
                return true;
            }
            return null;
          });
    }

    test('imports native confirmations and acknowledges them', () async {
      mockNative();
      final medication = await repository.insert(
        name: 'Metformin',
        times: const [MedicationTime(8, 0)],
        weekdays: const [],
        escalationMinutes: 30,
      );
      spool.addAll([
        {
          'id': 'entry-1',
          'slot_id': medication.slotId(const MedicationTime(8, 0)),
          'medication_id': medication.id,
          'dose_key': '2026-09-29T08:00',
          'status': 'taken',
          'recorded_at_epoch_ms': DateTime(
            2026,
            9,
            29,
            8,
            12,
          ).millisecondsSinceEpoch,
        },
        // A medication deleted meanwhile: dropped, but still acknowledged.
        {
          'id': 'entry-2',
          'slot_id': 'gone@0900',
          'medication_id': 'gone',
          'dose_key': '2026-09-29T09:00',
          'status': 'taken',
          'recorded_at_epoch_ms': 0,
        },
      ]);
      final service = MedicationReminderService.instance
        ..overrideForTest(clock: () => DateTime(2026, 9, 29, 10));

      await service.reconcile();

      final doses = await repository.getDoses(
        from: DateTime(2026, 9, 29),
        to: DateTime(2026, 9, 30),
      );
      expect(doses.single.medicationId, medication.id);
      expect(doses.single.recordedAt, DateTime(2026, 9, 29, 8, 12));
      final ack = calls.singleWhere((call) => call.method == 'ackSpool');
      expect((ack.arguments as Map)['ids'], ['entry-1', 'entry-2']);
      expect(service.todayItems().single.state, MedicationDoseState.taken);
    });

    test(
      'schedules every time and cancels slots that no longer exist',
      () async {
        mockNative();
        final medication = await repository.insert(
          name: 'Levothyroxine',
          dosage: '25 mcg',
          times: const [MedicationTime(6, 30), MedicationTime(18, 0)],
          weekdays: const [1, 2, 3, 4, 5],
          escalationMinutes: 15,
        );
        nativeStates.add({
          'slot_id': 'old-medication@0700',
          'state': 'scheduled',
        });
        final service = MedicationReminderService.instance
          ..overrideForTest(clock: () => DateTime(2026, 9, 29, 10));

        await service.reconcile();

        final scheduled = calls.where((call) => call.method == 'schedule');
        expect(scheduled, hasLength(2));
        final first = scheduled.first.arguments as Map;
        expect(first['slot_id'], '${medication.id}@0630');
        expect(first['name'], 'Levothyroxine');
        expect(first['dosage'], '25 mcg');
        expect(first['weekdays'], [1, 2, 3, 4, 5]);
        expect(first['escalation_minutes'], 15);
        final cancelled = calls.where((call) => call.method == 'cancel');
        expect(cancelled.map((call) => (call.arguments as Map)['slot_id']), [
          'old-medication@0700',
        ]);
        expect(calls.any((call) => call.method == 'restore'), isTrue);
      },
    );

    test('today states and answering from the app', () async {
      mockNative();
      final medication = await repository.insert(
        name: 'Iron',
        times: const [
          MedicationTime(7, 0),
          MedicationTime(9, 0),
          MedicationTime(21, 0),
        ],
        weekdays: const [],
        escalationMinutes: 30,
      );
      // The 09:00 reminder fired and is waiting for a confirmation.
      nativeStates.add({
        'slot_id': medication.slotId(const MedicationTime(9, 0)),
        'state': 'awaiting',
        'pending_dose_key': '2026-09-29T09:00',
      });
      final service = MedicationReminderService.instance
        ..overrideForTest(clock: () => DateTime(2026, 9, 29, 9, 10));
      await service.reconcile();

      var items = service.todayItems();
      expect(items.map((item) => item.state), [
        MedicationDoseState.overdue,
        MedicationDoseState.awaiting,
        MedicationDoseState.upcoming,
      ]);

      nativeStates.clear();
      await service.answer(items[1], MedicationDoseStatus.taken);
      final confirm = calls.lastWhere((call) => call.method == 'confirm');
      expect((confirm.arguments as Map)['dose_key'], '2026-09-29T09:00');
      expect((confirm.arguments as Map)['status'], 'taken');

      items = service.todayItems();
      expect(items[1].state, MedicationDoseState.taken);

      await service.undo(items[1]);
      expect(service.todayItems()[1].state, MedicationDoseState.overdue);
    });

    test('disabled medications have no doses and no native slots', () async {
      mockNative();
      final medication = await repository.insert(
        name: 'Paused',
        times: const [MedicationTime(8, 0)],
        weekdays: const [],
        escalationMinutes: 30,
      );
      final service = MedicationReminderService.instance
        ..overrideForTest(clock: () => DateTime(2026, 9, 29, 7));
      await service.reconcile();
      nativeStates.add({
        'slot_id': medication.slotId(const MedicationTime(8, 0)),
        'state': 'scheduled',
      });

      await service.setEnabled(service.medications.single, false);

      expect(service.todayItems(), isEmpty);
      expect(calls.where((call) => call.method == 'cancel').single.arguments, {
        'slot_id': medication.slotId(const MedicationTime(8, 0)),
      });
    });
  });
}
