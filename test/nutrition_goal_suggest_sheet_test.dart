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
        onApply: (_, protein, _, _) => appliedProtein = protein,
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    expect(find.text('2487 kcal'), findsOneWidget);

    await tester.tap(find.text('Distribuição de macros'));
    await tester.pumpAndSettle();

    expect(find.text('Déficit'), findsNWidgets(2));
    expect(
      find.text('Carboidratos usam as calorias restantes.'),
      findsOneWidget,
    );

    // Profile fields are first; maintenance protein is the sixth text field.
    final maintenanceProtein = find.byType(TextField).at(5);
    await tester.enterText(maintenanceProtein, '2,0');
    await tester.pump();
    expect(find.text('160 g'), findsOneWidget);

    final applyButton = find.widgetWithText(FilledButton, 'Aplicar metas');
    await tester.ensureVisible(applyButton);
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(appliedProtein, 160);
    expect(
      settings.values['nutrition_profile_macro_maintenance_protein_g_kg'],
      '2.0',
    );
    expect(settings.values['nutrition_profile_macro_cut_protein_g_kg'], '2.2');
  });
}
