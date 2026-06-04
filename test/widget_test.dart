import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:life_notes/screens/home_screen.dart';
import 'package:life_notes/models/note.dart';

void main() {
  group('Note Model', () {
    test('toJson and fromJson round-trip correctly', () {
      final note = Note(
        id: 'test-id',
        title: 'Test Note',
        content: 'This is a test note content.',
        createdAt: DateTime(2026, 6, 4, 10, 30),
        updatedAt: DateTime(2026, 6, 4, 11, 0),
      );

      final json = note.toJson();
      final reconstructed = Note.fromJson(json);

      expect(reconstructed.id, note.id);
      expect(reconstructed.title, note.title);
      expect(reconstructed.content, note.content);
      expect(reconstructed.createdAt, note.createdAt);
      expect(reconstructed.updatedAt, note.updatedAt);
    });

    test('preview truncates long content', () {
      final note = Note(
        id: '1',
        title: 'Long Note',
        content: 'a' * 200,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(note.preview.length, 123); // 120 chars + '...'
      expect(note.preview.endsWith('...'), true);
    });

    test('preview returns empty string for empty content', () {
      final note = Note(
        id: '1',
        title: 'Empty',
        content: '',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(note.preview, '');
    });

    test('copyWith preserves unchanged fields', () {
      final note = Note(
        id: '1',
        title: 'Original',
        content: 'Original content',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      final updated = note.copyWith(title: 'Updated');
      expect(updated.id, note.id);
      expect(updated.title, 'Updated');
      expect(updated.content, note.content);
    });
  });

  group('HomeScreen', () {
    testWidgets('displays welcome message when no notes exist',
        (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
      // Wait for SharedPreferences to load
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();

      expect(find.text('Welcome to Life Notes'), findsOneWidget);
      expect(find.text('Write your first note'), findsOneWidget);
    });

    testWidgets('shows loading indicator initially', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(const MaterialApp(home: HomeScreen()));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });
}
