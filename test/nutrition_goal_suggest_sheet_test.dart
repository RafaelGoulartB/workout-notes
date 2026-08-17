import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/screens/workout/nutrition_goal_suggest_sheet.dart';

class _BodyRepository extends BodyMeasurementRepository {
  @override
  Future<double?> getLatestWeightKg() async => 80;
}

class _MemorySettingsRepository extends SettingsRepository {
  final values = <String, String>{
    'nutrition_profile_sex': 'male',
    'nutrition_profile_age': '23',
    'nutrition_profile_height_cm': '179',
    'nutrition_profile_activity': 'light',
  };

  @override
  Future<String?> getSetting(String key) async => values[key];

  @override
  Future<void> setSetting(String key, String value) async {
    values[key] = value;
  }
}

Widget _app({
  required BodyMeasurementRepository bodyRepository,
  required SettingsRepository settingsRepository,
  required NutritionGoalApplyCallback onApply,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('pt'),
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () => NutritionGoalSuggestSheet.show(
              context,
              bodyRepo: bodyRepository,
              settingsRepo: settingsRepository,
              onApply: onApply,
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('edits and persists macro ratios from the suggestion sheet', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settings = _MemorySettingsRepository();
    double? appliedProtein;
    await tester.pumpWidget(
      _app(
        bodyRepository: _BodyRepository(),
        settingsRepository: settings,
        onApply: (suggestion) => appliedProtein = suggestion.proteinG,
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    // The headline reports the maintenance expenditure (BMR × activity).
    expect(find.text('2487 kcal'), findsOneWidget);

    // The objective selector is gone: the sheet only estimates maintenance.
    expect(find.text('Déficit'), findsNothing);
    expect(find.text('Superávit'), findsNothing);
    expect(find.text('Objetivo'), findsNothing);
    expect(find.text('Distribuição de macros'), findsOneWidget);
    expect(
      find.text('Carboidratos usam as calorias restantes.'),
      findsOneWidget,
    );

    // Profile fields come first (age, height, weight); protein is fourth.
    final proteinField = find.byType(TextField).at(3);
    await tester.enterText(proteinField, '2,0');
    await tester.pump();
    expect(find.text('160 g'), findsOneWidget);

    final applyButton = find.widgetWithText(
      FilledButton,
      'Aplicar gasto diário',
    );
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(appliedProtein, 160);
    expect(settings.values['nutrition_profile_macro_protein_g_kg'], '2.0');
    expect(settings.values['nutrition_profile_macro_fat_g_kg'], '1.0');
    // The legacy per-objective keys are no longer written.
    expect(
      settings.values.containsKey(
        'nutrition_profile_macro_maintenance_protein_g_kg',
      ),
      isFalse,
    );
  });

  testWidgets('falls back to the legacy maintenance ratio keys', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(430, 932));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final settings = _MemorySettingsRepository()
      ..values['nutrition_profile_macro_maintenance_protein_g_kg'] = '2.4'
      ..values['nutrition_profile_macro_maintenance_fat_g_kg'] = '0.9';
    await tester.pumpWidget(
      _app(
        bodyRepository: _BodyRepository(),
        settingsRepository: settings,
        onApply: (_) {},
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    // 80 kg × 2.4 g/kg = 192 g of protein in the preview.
    expect(find.text('192 g'), findsOneWidget);
    // 80 kg × 0.9 g/kg = 72 g of fat in the preview.
    expect(find.text('72 g'), findsOneWidget);
  });
}
