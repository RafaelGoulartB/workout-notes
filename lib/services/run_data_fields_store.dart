import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/models/run_data_field.dart';

/// Persists which live fields the runner picked for the record screen.
class RunDataFieldsStore {
  RunDataFieldsStore._();
  static final RunDataFieldsStore instance = RunDataFieldsStore._();

  static const storageKey = 'run_record_data_fields_v1';

  Future<List<RunDataField>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return RunDataFieldLayout.fromStorage(prefs.getStringList(storageKey));
    } catch (_) {
      return RunDataFieldLayout.defaults;
    }
  }

  Future<void> save(List<RunDataField> fields) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        storageKey,
        RunDataFieldLayout.toStorage(RunDataFieldLayout.sanitize(fields)),
      );
    } catch (_) {
      // A preference that fails to persist is not worth interrupting a run.
    }
  }
}
