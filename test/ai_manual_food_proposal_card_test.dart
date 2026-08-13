import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/ai_manual_food_proposal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/widgets/ai/ai_manual_food_proposal_card.dart';

void main() {
  testWidgets('food proposal previews values and requires explicit approval', (
    tester,
  ) async {
    var approvals = 0;
    var rejections = 0;
    const proposal = AiManualFoodProposal(
      draft: AiFoodLabelDraft(
        name: 'Banana prata',
        values: NutritionValues(
          calories: 98,
          proteinG: 1.3,
          carbsG: 26,
          fatG: 0.1,
          potassiumMg: 358,
        ),
        servings: [
          AiFoodLabelServingDraft(
            label: '1 unidade média',
            unit: 'unidade',
            gramsEquivalent: 80,
          ),
        ],
      ),
      notes: 'Valores típicos para banana prata crua.',
    );

    await tester.pumpWidget(
      _app(
        AiManualFoodProposalCard(
          proposal: proposal,
          onApprove: () async => approvals++,
          onReject: () async => rejections++,
        ),
      ),
    );

    expect(find.text('Banana prata'), findsOneWidget);
    expect(find.textContaining('98 kcal'), findsOneWidget);
    expect(find.text('Aprovar e revisar formulário'), findsOneWidget);

    await tester.tap(find.text('Ver todos os valores identificados'));
    await tester.pumpAndSettle();
    expect(find.textContaining('358 mg'), findsOneWidget);
    expect(find.textContaining('1 unidade média'), findsOneWidget);

    await tester.tap(find.text('Aprovar e revisar formulário'));
    await tester.pump();
    expect(approvals, 1);
    expect(rejections, 0);
  });
}

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('pt'),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);
