/// Small helpers shared by the SQLite repositories.
library;

/// Escapes `\`, `%` and `_` in [value] so it can be embedded in a `LIKE`
/// pattern that declares `ESCAPE '\'`.
String escapeLike(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

/// [value] trimmed, or `null` when it is null or blank. Used to store
/// optional free-text columns as SQL NULL instead of empty strings.
String? optionalText(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
