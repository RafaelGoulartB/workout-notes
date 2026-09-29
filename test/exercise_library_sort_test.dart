import 'dart:ui' show Locale;

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/exercise_repository.dart';
import 'package:workout_notes/utils/exercise_equipment.dart';
import 'package:workout_notes/utils/strength_exercise_library.dart';

ExerciseLibraryEntry _entry(
  String id,
  String name, {
  String category = 'chest',
  DateTime? last,
  int sessions = 0,
}) => ExerciseLibraryEntry(
  row: {'id': id, 'name': name, 'category_id': category, 'is_favorite': 0},
  name: name,
  usage: sessions == 0 && last == null
      ? null
      : ExerciseUsage(exerciseId: id, lastDate: last, sessions: sessions),
);

void main() {
  final entries = [
    _entry('a', 'Supino', last: DateTime(2026, 9, 1), sessions: 3),
    _entry('b', 'Água', category: 'legs'),
    _entry('c', 'Crucifixo', last: DateTime(2026, 9, 20), sessions: 1),
    _entry('d', 'Agachamento', category: 'legs', sessions: 9),
    _entry(
      'e',
      'Remada',
      category: 'back',
      last: DateTime(2026, 9, 20),
      sessions: 5,
    ),
  ];

  List<String> ids(List<ExerciseLibraryEntry> list) => [
    for (final e in list) e.id,
  ];

  test('A-Z ignores case and accents', () {
    final sorted = StrengthExerciseLibrary.sorted(
      entries,
      ExerciseLibrarySort.az,
    );
    // "Água" folds to "agua": after Agachamento, before Crucifixo.
    expect(ids(sorted), ['d', 'b', 'c', 'e', 'a']);
  });

  test('recent puts the newest first and never-trained last', () {
    final sorted = StrengthExerciseLibrary.sorted(
      entries,
      ExerciseLibrarySort.recent,
    );
    // Same day: alphabetical (Crucifixo before Remada).
    expect(ids(sorted), ['c', 'e', 'a', 'd', 'b']);
  });

  test('most trained ranks by sessions', () {
    final sorted = StrengthExerciseLibrary.sorted(
      entries,
      ExerciseLibrarySort.mostTrained,
    );
    expect(ids(sorted), ['d', 'e', 'a', 'c', 'b']);
  });

  test('sections follow the category order and keep entry order', () {
    final sorted = StrengthExerciseLibrary.sorted(
      entries,
      ExerciseLibrarySort.az,
    );
    final sections = StrengthExerciseLibrary.grouped(sorted, [
      'chest',
      'back',
      'legs',
    ]);
    expect(sections.map((s) => s.categoryId), ['chest', 'back', 'legs']);
    expect(ids(sections.first.entries), ['c', 'a']);
    expect(ids(sections.last.entries), ['d', 'b']);

    // Unknown categories go last (in order of appearance), not missing.
    final unknown = StrengthExerciseLibrary.grouped(sorted, ['back']);
    expect(unknown.map((s) => s.categoryId), ['back', 'legs', 'chest']);
  });

  group('ExerciseEquipment', () {
    test('canonical matches known values loosely', () {
      expect(ExerciseEquipment.canonical('barbell'), 'Barbell');
      expect(ExerciseEquipment.canonical(' Medicine Ball '), 'Medicine Ball');
      expect(ExerciseEquipment.canonical('medicine_ball'), 'Medicine Ball');
      expect(ExerciseEquipment.canonical('Landmine'), isNull);
      expect(ExerciseEquipment.canonical(''), isNull);
      expect(ExerciseEquipment.canonical(null), isNull);
    });

    test('labels are localized, custom values pass through', () async {
      final pt = await AppLocalizations.delegate.load(const Locale('pt'));
      final en = await AppLocalizations.delegate.load(const Locale('en'));
      expect(ExerciseEquipment.label(pt, 'Cable'), 'Polia');
      expect(ExerciseEquipment.label(en, 'Cable'), 'Cable');
      expect(ExerciseEquipment.label(pt, 'Dumbbell'), 'Halter');
      expect(ExerciseEquipment.label(pt, 'Bodyweight'), 'Peso corporal');
      expect(ExerciseEquipment.label(pt, 'Landmine'), 'Landmine');
      expect(ExerciseEquipment.label(pt, null), '');
      // Every stored option has a label distinct from the raw value in pt
      // (except the loanwords).
      for (final option in ExerciseEquipment.options) {
        expect(ExerciseEquipment.label(pt, option), isNotEmpty);
      }
      expect(ExerciseEquipment.matches(pt, 'Cable', 'polia'), isTrue);
      expect(ExerciseEquipment.matches(pt, 'Cable', 'cab'), isTrue);
      expect(ExerciseEquipment.matches(pt, 'Cable', 'barra'), isFalse);
    });
  });
}
