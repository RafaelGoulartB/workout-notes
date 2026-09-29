import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/medication.dart';
import '../repositories/medication_repository.dart';
import 'traditional_alarm_service.dart';

/// Where one of today's doses stands.
enum MedicationDoseState {
  /// Later today.
  upcoming,

  /// Reminder sent, waiting for a confirmation before the alarm.
  awaiting,

  /// Not confirmed in time: the sound alarm is ringing.
  ringing,

  /// Time passed without an answer (and no alarm pending).
  overdue,
  taken,
  skipped,
}

/// One scheduled dose of today with its answer (if any).
class MedicationDoseItem {
  const MedicationDoseItem({
    required this.medication,
    required this.time,
    required this.scheduledAt,
    required this.record,
    required this.state,
  });

  final Medication medication;
  final MedicationTime time;
  final DateTime scheduledAt;
  final MedicationDose? record;
  final MedicationDoseState state;

  String get doseKey => Medication.doseKey(scheduledAt);
  String get slotId => medication.slotId(time);
  bool get isAnswered => record != null;
}

/// Persists medications in SQLite and mirrors one native reminder slot per
/// medication time to Android, which notifies, escalates to a sound alarm and
/// records confirmations while the app is closed. Native confirmations reach
/// SQLite through a spool imported on [reconcile].
class MedicationReminderService extends ChangeNotifier {
  MedicationReminderService._();
  static final MedicationReminderService instance =
      MedicationReminderService._();
  static const _channel = MethodChannel('workout_notes/medication/methods');

  MedicationRepository _repository = MedicationRepository();
  DateTime Function() _clock = DateTime.now;

  List<Medication> _medications = const [];
  List<Medication> get medications => List.unmodifiable(_medications);

  List<MedicationDose> _todayDoses = const [];
  Map<String, String> _nativeStates = const {};
  Map<String, String?> _nativePending = const {};

  @visibleForTesting
  void overrideForTest({
    MedicationRepository? repository,
    DateTime Function()? clock,
  }) {
    _repository = repository ?? MedicationRepository();
    _clock = clock ?? DateTime.now;
    _medications = const [];
    _todayDoses = const [];
    _nativeStates = const {};
    _nativePending = const {};
  }

  Future<void> initialize() => reconcile();

  /// Imports native confirmations, then makes Android's slots match SQLite.
  Future<void> reconcile() async {
    await _importSpool();
    await refresh();
    await _syncNative(restore: true);
  }

  Future<void> refresh() async {
    _medications = await _repository.getAll();
    final today = _today();
    _todayDoses = await _repository.getDoses(
      from: today,
      to: today.add(const Duration(days: 1)),
    );
    notifyListeners();
  }

  /// Today's doses of enabled medications, in time order.
  List<MedicationDoseItem> todayItems() {
    final now = _clock();
    final today = _today();
    final records = {
      for (final dose in _todayDoses)
        '${dose.medicationId}|${dose.doseKey}': dose,
    };
    final items = <MedicationDoseItem>[];
    for (final medication in _medications.where((m) => m.enabled)) {
      for (final time in medication.times) {
        if (!medication.takesOn(today)) continue;
        final scheduledAt = DateTime(
          today.year,
          today.month,
          today.day,
          time.hour,
          time.minute,
        );
        final key = Medication.doseKey(scheduledAt);
        final record = records['${medication.id}|$key'];
        final slotId = medication.slotId(time);
        final nativePending = _nativePending[slotId] == key;
        final state = record != null
            ? (record.status == MedicationDoseStatus.taken
                  ? MedicationDoseState.taken
                  : MedicationDoseState.skipped)
            : nativePending && _nativeStates[slotId] == 'ringing'
            ? MedicationDoseState.ringing
            : nativePending
            ? MedicationDoseState.awaiting
            : scheduledAt.isAfter(now)
            ? MedicationDoseState.upcoming
            : MedicationDoseState.overdue;
        items.add(
          MedicationDoseItem(
            medication: medication,
            time: time,
            scheduledAt: scheduledAt,
            record: record,
            state: state,
          ),
        );
      }
    }
    items.sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
    return items;
  }

  Future<Medication> create({
    required String name,
    String? dosage,
    String? notes,
    required List<MedicationTime> times,
    required List<int> weekdays,
    required int escalationMinutes,
  }) async {
    final medication = await _repository.insert(
      name: name,
      dosage: dosage,
      notes: notes,
      times: times,
      weekdays: weekdays,
      escalationMinutes: escalationMinutes,
    );
    await refresh();
    await _syncNative();
    return medication;
  }

  Future<void> save(Medication medication) async {
    await _repository.update(medication.copyWith(updatedAt: _clock()));
    await refresh();
    await _syncNative();
  }

  Future<void> setEnabled(Medication medication, bool enabled) =>
      save(medication.copyWith(enabled: enabled));

  Future<void> delete(Medication medication) async {
    await _repository.delete(medication.id);
    await refresh();
    await _syncNative();
  }

  /// Logs today's dose from the app and silences its reminder / alarm.
  Future<void> answer(
    MedicationDoseItem item,
    MedicationDoseStatus status,
  ) async {
    await _repository.recordDose(
      medicationId: item.medication.id,
      doseKey: item.doseKey,
      scheduledAt: item.scheduledAt,
      status: status,
      recordedAt: _clock(),
    );
    await _invoke('confirm', {
      'slot_id': item.slotId,
      'dose_key': item.doseKey,
      'status': status.name,
    });
    await refresh();
    await _readNativeStates();
  }

  /// Removes a logged answer (for a mistaken tap).
  Future<void> undo(MedicationDoseItem item) async {
    await _repository.deleteDose(item.medication.id, item.doseKey);
    await refresh();
  }

  /// Notifications, exact alarms and full-screen alarms, as for wake alarms.
  Future<bool> preparePermissions() =>
      TraditionalAlarmService.instance.preparePermissions();

  Future<void> _importSpool() async {
    final raw = await _invoke<List<dynamic>>('spool');
    if (raw == null || raw.isEmpty) return;
    final known = {for (final m in await _repository.getAll()) m.id};
    final imported = <String>[];
    for (final value in raw) {
      if (value is! Map) continue;
      final entry = Map<String, dynamic>.from(value);
      final id = entry['id'] as String?;
      final medicationId = entry['medication_id'] as String?;
      final key = entry['dose_key'] as String?;
      if (id == null) continue;
      final scheduledAt = key == null ? null : Medication.parseDoseKey(key);
      // Entries of a deleted medication are dropped rather than retried.
      if (medicationId != null &&
          key != null &&
          scheduledAt != null &&
          known.contains(medicationId)) {
        final recorded = entry['recorded_at_epoch_ms'];
        await _repository.recordDose(
          medicationId: medicationId,
          doseKey: key,
          scheduledAt: scheduledAt,
          status: MedicationDoseStatus.parse(entry['status'] as String?),
          recordedAt: recorded is num
              ? DateTime.fromMillisecondsSinceEpoch(recorded.toInt())
              : null,
        );
      }
      imported.add(id);
    }
    if (imported.isNotEmpty) await _invoke('ackSpool', {'ids': imported});
  }

  /// Schedules every enabled medication time and cancels slots that no
  /// longer exist (deleted, disabled or a removed time).
  Future<void> _syncNative({bool restore = false}) async {
    if (!_isAndroid) return;
    final expected = <String>{};
    for (final medication in _medications.where((m) => m.enabled)) {
      for (final time in medication.times) {
        final slotId = medication.slotId(time);
        expected.add(slotId);
        await _invoke('schedule', {
          'slot_id': slotId,
          'medication_id': medication.id,
          'name': medication.name,
          'dosage': medication.dosage,
          'hour': time.hour,
          'minute': time.minute,
          'weekdays': medication.weekdays,
          'escalation_minutes': medication.escalationMinutes,
        });
      }
    }
    final states = await _invoke<List<dynamic>>('states') ?? const [];
    for (final value in states) {
      if (value is! Map) continue;
      final slotId = value['slot_id'] as String?;
      if (slotId != null && !expected.contains(slotId)) {
        await _invoke('cancel', {'slot_id': slotId});
      }
    }
    if (restore) await _invoke('restore');
    await _readNativeStates();
  }

  Future<void> _readNativeStates() async {
    final states = await _invoke<List<dynamic>>('states') ?? const [];
    final byState = <String, String>{};
    final pending = <String, String?>{};
    for (final value in states) {
      if (value is! Map) continue;
      final slotId = value['slot_id'] as String?;
      if (slotId == null) continue;
      byState[slotId] = value['state'] as String? ?? 'scheduled';
      pending[slotId] = value['pending_dose_key'] as String?;
    }
    _nativeStates = byState;
    _nativePending = pending;
    notifyListeners();
  }

  /// Channel calls are best effort: SQLite stays the source of truth and the
  /// next [reconcile] repairs anything a transient failure left behind.
  Future<T?> _invoke<T>(
    String method, [
    Map<String, Object?>? arguments,
  ]) async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException catch (error) {
      debugPrint('Medication reminder $method failed: ${error.code}');
      return null;
    }
  }

  DateTime _today() {
    final now = _clock();
    return DateTime(now.year, now.month, now.day);
  }

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;
}
