import 'app_localizations.dart';
import 'l10n_exercises.dart';

/// Helper methods for resolving localized exercise and category names.
///
/// Rules:
/// - If a DB row has a non-null `locale_key`, use the translation for that key.
/// - Otherwise (user-created exercises), fall back to the stored `name` in the DB.
class ExerciseLocaleHelper {
  /// Returns the localized exercise name.
  /// [row] is a Map from a DB query (exercises table or JOIN result).
  /// Uses `locale_key` column if present, otherwise `name` column.
  static String exerciseName(AppLocalizations loc, Map<String, dynamic> row) {
    final localeKey = row['locale_key'] as String?;
    if (localeKey != null) {
      final translated = ExerciseLocalization.exerciseName(
        localeKey,
        loc.localeName,
      );
      if (translated != null && translated.isNotEmpty) return translated;
    }
    return (row['name'] as String?) ?? '';
  }

  /// Returns the localized exercise notes.
  /// Falls back to the stored `notes` column if no translation exists.
  static String exerciseNotes(AppLocalizations loc, Map<String, dynamic> row) {
    final localeKey = row['locale_key'] as String?;
    if (localeKey != null) {
      final translated = ExerciseLocalization.exerciseNotes(
        localeKey,
        loc.localeName,
      );
      if (translated != null && translated.isNotEmpty) return translated;
    }
    return (row['notes'] as String?) ?? '';
  }

  /// Returns the localized category name.
  /// [row] is a Map from a category DB query or JOIN result.
  /// Uses `locale_key` column if present (categories), otherwise `name`.
  static String categoryName(AppLocalizations loc, Map<String, dynamic> row) {
    // If the row has a locale_key (direct category query)
    final localeKey = row['locale_key'] as String?;
    if (localeKey != null) {
      final translated = ExerciseLocalization.categoryName(
        localeKey,
        loc.localeName,
      );
      if (translated != null && translated.isNotEmpty) return translated;
    }
    // If the row has a category_name (JOIN result)
    final catKey = row['category_id'] as String?;
    if (catKey != null) {
      final translated = ExerciseLocalization.categoryName(
        catKey,
        loc.localeName,
      );
      if (translated != null && translated.isNotEmpty) return translated;
    }
    // Fallback to the stored name
    return (row['category_name'] as String?) ?? (row['name'] as String?) ?? '';
  }

  /// Returns the localized category name from a category ID.
  static String categoryNameFromId(AppLocalizations loc, String categoryId) {
    final translated = ExerciseLocalization.categoryName(
      categoryId,
      loc.localeName,
    );
    return translated ?? categoryId;
  }

  /// Returns the localized exercise name from a locale key.
  static String exerciseNameFromKey(AppLocalizations loc, String key) {
    final translated = ExerciseLocalization.exerciseName(key, loc.localeName);
    return translated ?? key;
  }

  /// Checks if a row matches a search query considering localization.
  ///
  /// Searches both the stored DB name AND the localized name so that
  /// users can find exercises in either language.
  ///
  /// Example: if locale is 'en' and user types "supino",
  /// this will match because the stored DB name is "Supino Reto" (Portuguese).
  /// If the user types "bench", it will match because the localized (EN) name
  /// is "Bench Press".
  static bool exerciseMatchesSearch(
    AppLocalizations loc,
    Map<String, dynamic> row,
    String query,
  ) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();

    // Search in stored DB name
    final dbName = (row['name'] as String?)?.toLowerCase() ?? '';
    if (dbName.contains(q)) return true;

    // Search in localized name
    final localeKey = row['locale_key'] as String?;
    if (localeKey != null) {
      final localized = ExerciseLocalization.exerciseName(
        localeKey,
        loc.localeName,
      );
      if (localized != null && localized.toLowerCase().contains(q)) {
        return true;
      }
      // Also search in the other locale as a bonus
      final otherLocale = loc.localeName == 'en' ? 'pt' : 'en';
      final otherLocalized = ExerciseLocalization.exerciseName(
        localeKey,
        otherLocale,
      );
      if (otherLocalized != null && otherLocalized.toLowerCase().contains(q)) {
        return true;
      }
    }

    return false;
  }

  /// Checks if a category row matches a search query considering localization.
  static bool categoryMatchesSearch(
    AppLocalizations loc,
    Map<String, dynamic> row,
    String query,
  ) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();

    // Search in stored DB name
    final dbName = (row['name'] as String?)?.toLowerCase() ?? '';
    if (dbName.contains(q)) return true;

    // Search in localized name
    final localeKey = row['locale_key'] as String?;
    if (localeKey != null) {
      final localized = ExerciseLocalization.categoryName(
        localeKey,
        loc.localeName,
      );
      if (localized != null && localized.toLowerCase().contains(q)) {
        return true;
      }
    } else {
      // Search by category ID
      final catId = row['id'] as String?;
      if (catId != null) {
        final localized = ExerciseLocalization.categoryName(
          catId,
          loc.localeName,
        );
        if (localized != null && localized.toLowerCase().contains(q)) {
          return true;
        }
      }
    }

    return false;
  }

  /// Returns a display string for the equipment, localized if needed.
  static String equipment(Map<String, dynamic> row) {
    return (row['equipment'] as String?) ?? '';
  }
}
