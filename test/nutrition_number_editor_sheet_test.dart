import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/nutrition/settings/nutrition_settings_sheets.dart';

void main() {
  Future<(double?,)?> openSheet(
    WidgetTester tester,
    Future<void> Function() interact,
  ) async {
    late Future<(double?,)?> result;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => result = showModalBottomSheet<(double?,)>(
                context: context,
                isScrollControlled: true,
                builder: (_) => const NumberEditorSheet(
                  title: 'Protein',
                  unit: 'g',
                  initial: 120,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact();
    await tester.pumpAndSettle();
    return result;
  }

  testWidgets('dismissing without saving leaves the value unchanged', (
    tester,
  ) async {
    final result = await openSheet(tester, () async {
      await tester.tapAt(const Offset(10, 10));
    });
    expect(result, isNull);
  });

  testWidgets('saving an empty field clears the value', (tester) async {
    final result = await openSheet(tester, () async {
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('Save'));
    });
    expect(result, isNotNull);
    expect(result!.$1, isNull);
  });

  testWidgets('saving a number returns it', (tester) async {
    final result = await openSheet(tester, () async {
      await tester.enterText(find.byType(TextField), '145,5');
      await tester.tap(find.text('Save'));
    });
    expect(result?.$1, 145.5);
  });
}
