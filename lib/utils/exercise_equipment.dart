import 'package:workout_notes/l10n/app_localizations.dart';

/// Equipment values stored in `exercises.equipment` (English identifiers) and
/// their localized labels. The stored value never changes; only the display.
abstract final class ExerciseEquipment {
  /// Values offered by the exercise form, in display order.
  static const List<String> options = [
    'Barbell',
    'Dumbbell',
    'Cable',
    'Machine',
    'Bodyweight',
    'Kettlebell',
    'Band',
    'Treadmill',
    'Stationary',
    'Other',
  ];

  /// Normalises a stored value for lookups (case/space insensitive).
  static String _key(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s_-]+'), '');

  /// Canonical stored value for [raw] when it matches a known option
  /// (`'barbell'` -> `'Barbell'`), otherwise `null`.
  static String? canonical(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final key = _key(raw);
    for (final option in [...options, 'Medicine Ball', 'Plates']) {
      if (_key(option) == key) return option;
    }
    return null;
  }

  /// Localized label for a stored equipment value. Unknown / user-typed values
  /// are shown as typed; empty values return an empty string.
  static String label(AppLocalizations loc, String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return '';
    return switch (canonical(value)) {
      'Barbell' => loc.exerciseLibraryEquipBarbell,
      'Dumbbell' => loc.exerciseLibraryEquipDumbbell,
      'Cable' => loc.exerciseLibraryEquipCable,
      'Machine' => loc.exerciseLibraryEquipMachine,
      'Bodyweight' => loc.exerciseLibraryEquipBodyweight,
      'Kettlebell' => loc.exerciseLibraryEquipKettlebell,
      'Band' => loc.exerciseLibraryEquipBand,
      'Treadmill' => loc.exerciseLibraryEquipTreadmill,
      'Stationary' => loc.exerciseLibraryEquipStationary,
      'Medicine Ball' => loc.exerciseLibraryEquipMedicineBall,
      'Plates' => loc.exerciseLibraryEquipPlates,
      'Other' => loc.exerciseLibraryEquipOther,
      _ => value,
    };
  }

  /// Whether [raw] matches [query] in either its stored or localized form.
  static bool matches(AppLocalizations loc, String? raw, String query) {
    final q = query.toLowerCase();
    if (q.isEmpty) return true;
    final value = raw?.toLowerCase() ?? '';
    return value.contains(q) || label(loc, raw).toLowerCase().contains(q);
  }
}
