import 'package:workout_notes/l10n/app_localizations.dart';

/// Display label of an exercise's equipment. Equipment is stored as the
/// English name picked in the form (`Barbell`, `Dumbbell`...), so known values
/// are translated and anything typed by the user is shown as is.
String exerciseEquipmentLabel(AppLocalizations loc, String raw) {
  return switch (raw.trim().toLowerCase()) {
    'barbell' => loc.exerciseDetailEquipBarbell,
    'dumbbell' => loc.exerciseDetailEquipDumbbell,
    'cable' => loc.exerciseDetailEquipCable,
    'machine' => loc.exerciseDetailEquipMachine,
    'bodyweight' => loc.exerciseDetailEquipBodyweight,
    'treadmill' => loc.exerciseDetailEquipTreadmill,
    'stationary' => loc.exerciseDetailEquipStationary,
    'kettlebell' => loc.exerciseDetailEquipKettlebell,
    'band' => loc.exerciseDetailEquipBand,
    _ => raw.trim(),
  };
}
