import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/repositories/ai_memory_repository.dart';
import 'package:workout_notes/screens/settings/ai_memory_screen.dart';
import 'package:workout_notes/services/ai_memory_service.dart';

import 'support/ai_ui_support.dart';

/// In-memory stand-in for the SQLite repository.
class _FakeMemoryRepository extends AiMemoryRepository {
  final Map<String, AiMemory> rows = {};

  @override
  Future<List<AiMemory>> getAll() async =>
      rows.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<AiMemory?> getById(String id) async => rows[id];

  @override
  Future<void> upsert(AiMemory memory) async => rows[memory.id] = memory;

  @override
  Future<bool> delete(String id) async => rows.remove(id) != null;

  @override
  Future<void> deleteAll() async => rows.clear();
}

AiMemory _memory(String id, String content, AiMemoryCategory category) =>
    AiMemory(
      id: id,
      content: content,
      category: category,
      createdAt: DateTime(2026, 9, 1, 8, int.parse(id.substring(1))),
      updatedAt: DateTime(2026, 9, 1),
    );

void main() {
  late _FakeMemoryRepository repo;
  late AiMemoryService service;

  setUp(() {
    repo = _FakeMemoryRepository();
    service = AiMemoryService(repo: repo);
  });

  Future<void> open(WidgetTester tester, {String locale = 'en'}) async {
    await tester.pumpWidget(
      aiTestApp(
        AiMemoryScreen(service: service),
        locale: locale,
        scaffold: false,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('empty state invites the user to add a note', (tester) async {
    await open(tester);
    expect(find.text('Nothing remembered yet'), findsOneWidget);
    expect(find.text('Add note'), findsWidgets);
  });

  testWidgets('groups notes by category with their count', (tester) async {
    repo.rows.addAll({
      'm1': _memory('m1', 'Sore left knee', AiMemoryCategory.health),
      'm2': _memory('m2', 'Dumbbells up to 20 kg', AiMemoryCategory.equipment),
      'm3': _memory(
        'm3',
        'Lower back pain on deadlifts',
        AiMemoryCategory.health,
      ),
    });
    await open(tester);

    expect(find.text('3 of 40 notes'), findsOneWidget);
    expect(find.text('HEALTH'), findsOneWidget);
    expect(find.text('EQUIPMENT'), findsOneWidget);
    expect(find.text('SCHEDULE'), findsNothing);
    expect(find.text('Sore left knee'), findsOneWidget);
    expect(find.text('Dumbbells up to 20 kg'), findsOneWidget);
  });

  testWidgets('adds a note with a category', (tester) async {
    await open(tester, locale: 'pt');
    expect(find.text('Nada lembrado ainda'), findsOneWidget);

    await tester.tap(find.text('Adicionar nota').first);
    await tester.pumpAndSettle();
    // An empty note is refused.
    await tester.tap(find.text('Salvar'));
    await tester.pump();
    expect(find.text('Escreva a nota primeiro.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Treino de manhã cedo');
    await tester.tap(find.text('Rotina'));
    await tester.pump();
    await tester.tap(find.text('Salvar'));
    await tester.pumpAndSettle();

    expect(repo.rows.values.single.content, 'Treino de manhã cedo');
    expect(repo.rows.values.single.category, AiMemoryCategory.schedule);
    expect(find.text('Treino de manhã cedo'), findsOneWidget);
    expect(find.text('ROTINA'), findsOneWidget);
  });

  testWidgets('edits a note and can move it to another category', (
    tester,
  ) async {
    repo.rows['m1'] = _memory('m1', 'Sore left knee', AiMemoryCategory.health);
    await open(tester);

    await tester.tap(find.text('Sore left knee'));
    await tester.pumpAndSettle();
    expect(find.text('Edit note'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Recovered knee');
    await tester.tap(find.text('Other'));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(repo.rows['m1']!.content, 'Recovered knee');
    expect(repo.rows['m1']!.category, AiMemoryCategory.other);
    expect(find.text('OTHER'), findsOneWidget);
  });

  testWidgets('deleting a note can be undone from the snack bar', (
    tester,
  ) async {
    repo.rows['m1'] = _memory('m1', 'Sore left knee', AiMemoryCategory.health);
    await open(tester);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(repo.rows, isEmpty);
    expect(find.text('Note deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(repo.rows.keys, ['m1']);
    expect(find.text('Sore left knee'), findsOneWidget);
  });

  testWidgets('clear all asks for confirmation first', (tester) async {
    repo.rows.addAll({
      'm1': _memory('m1', 'One', AiMemoryCategory.other),
      'm2': _memory('m2', 'Two', AiMemoryCategory.other),
    });
    await open(tester);

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Forget everything?'), findsOneWidget);
    expect(find.textContaining('All 2 notes will be deleted'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.rows, hasLength(2));

    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear all'));
    await tester.pumpAndSettle();
    expect(repo.rows, isEmpty);
    expect(find.text('Nothing remembered yet'), findsOneWidget);
  });

  testWidgets('a full memory refuses another note', (tester) async {
    for (var i = 0; i < AiMemoryService.maxEntries; i++) {
      repo.rows['m$i'] = AiMemory(
        id: 'm$i',
        content: 'Note $i',
        category: AiMemoryCategory.other,
        createdAt: DateTime(2026, 9, 1, 8).add(Duration(minutes: i)),
        updatedAt: DateTime(2026, 9, 1),
      );
    }
    await open(tester);
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    expect(
      find.text('Memory is full. Delete a note to add another.'),
      findsOneWidget,
    );
    expect(find.text('New note'), findsNothing);
  });

  testWidgets('a note added elsewhere (the coach) shows up live', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Nothing remembered yet'), findsOneWidget);
    await tester.runAsync(
      () =>
          service.add('Prefers evening workouts', AiMemoryCategory.preference),
    );
    await tester.pumpAndSettle();
    expect(find.text('Prefers evening workouts'), findsOneWidget);
  });
}
