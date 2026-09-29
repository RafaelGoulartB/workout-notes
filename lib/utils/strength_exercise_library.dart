import 'package:workout_notes/repositories/exercise_repository.dart';

enum ExerciseLibrarySort { az, recent, mostTrained }

/// One exercise of the library with the numbers used to sort and display it.
class ExerciseLibraryEntry {
  final Map<String, dynamic> row;

  /// Localized display name, used for sorting and grouping.
  final String name;
  final ExerciseUsage? usage;

  /// Best estimated 1RM, when the exercise is a weighted strength lift with
  /// finished sessions.
  final double? bestE1rm;

  const ExerciseLibraryEntry({
    required this.row,
    required this.name,
    this.usage,
    this.bestE1rm,
  });

  String get id => row['id'] as String;
  String get categoryId => row['category_id'] as String? ?? '';
  bool get isFavorite => (row['is_favorite'] as int?) == 1;
  DateTime? get lastDate => usage?.lastDate;
  int get sessions => usage?.sessions ?? 0;
}

/// A muscle group with its exercises, for the "All" view.
class ExerciseLibrarySection {
  final String categoryId;
  final List<ExerciseLibraryEntry> entries;

  const ExerciseLibrarySection(this.categoryId, this.entries);
}

abstract final class StrengthExerciseLibrary {
  static const _folds = {
    'á': 'a',
    'à': 'a',
    'â': 'a',
    'ã': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'ô': 'o',
    'õ': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
  };

  /// Lowercase and accent-free key so "Água" sorts next to "Agachamento".
  static String sortKey(String name) {
    final lower = name.toLowerCase();
    final buffer = StringBuffer();
    for (final rune in lower.runes) {
      final char = String.fromCharCode(rune);
      buffer.write(_folds[char] ?? char);
    }
    return buffer.toString();
  }

  static int _byName(ExerciseLibraryEntry a, ExerciseLibraryEntry b) =>
      sortKey(a.name).compareTo(sortKey(b.name));

  static List<ExerciseLibraryEntry> sorted(
    Iterable<ExerciseLibraryEntry> entries,
    ExerciseLibrarySort sort,
  ) {
    final list = entries.toList();
    switch (sort) {
      case ExerciseLibrarySort.az:
        list.sort(_byName);
      case ExerciseLibrarySort.recent:
        list.sort((a, b) {
          final ad = a.lastDate;
          final bd = b.lastDate;
          if (ad == null && bd == null) return _byName(a, b);
          if (ad == null) return 1;
          if (bd == null) return -1;
          final cmp = bd.compareTo(ad);
          return cmp != 0 ? cmp : _byName(a, b);
        });
      case ExerciseLibrarySort.mostTrained:
        list.sort((a, b) {
          final cmp = b.sessions.compareTo(a.sessions);
          if (cmp != 0) return cmp;
          final ad = a.lastDate;
          final bd = b.lastDate;
          if (ad != null && bd != null) {
            final dateCmp = bd.compareTo(ad);
            if (dateCmp != 0) return dateCmp;
          } else if (ad != null || bd != null) {
            return ad == null ? 1 : -1;
          }
          return _byName(a, b);
        });
    }
    return list;
  }

  /// Groups [entries] by muscle group following [categoryOrder] (category ids
  /// in display order); categories missing from it go last. Entries keep the
  /// order they come in, so sort first.
  static List<ExerciseLibrarySection> grouped(
    Iterable<ExerciseLibraryEntry> entries,
    List<String> categoryOrder,
  ) {
    final byCategory = <String, List<ExerciseLibraryEntry>>{};
    for (final entry in entries) {
      (byCategory[entry.categoryId] ??= []).add(entry);
    }
    final ids = [
      ...categoryOrder.where(byCategory.containsKey),
      ...byCategory.keys.where((id) => !categoryOrder.contains(id)),
    ];
    return [for (final id in ids) ExerciseLibrarySection(id, byCategory[id]!)];
  }
}
