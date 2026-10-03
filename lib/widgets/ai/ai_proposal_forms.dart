import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/nutrition/ai_manual_food_proposal.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/manual_food_screen.dart';

/// Opens the pre-filled form of a user-confirmed proposal.
///
/// A user-confirmed proposal (`AiProposalApplyMode.userConfirmed`) changes
/// nothing when approved: approval opens the regular form of the feature with
/// the AI's draft filled in, and the change only exists once the user saves it
/// there. The caller then reports the outcome with
/// `AiProposalService.markApplied(id, result: ...)`.
abstract final class AiProposalForms {
  /// Opens the form for [proposal]. Returns the result to store when the user
  /// saved it (`{'food_id': id}` for a manual food), or null when they
  /// cancelled or the proposal has no form.
  static Future<Map<String, dynamic>?> open(
    BuildContext context,
    AiProposal proposal, {
    NutritionRepository? nutritionRepository,
  }) async {
    switch (proposal.kind) {
      case 'manual_food':
        final AiManualFoodProposal manualFood;
        try {
          manualFood = AiManualFoodProposal.fromJson(proposal.payload);
        } on FormatException catch (error) {
          debugPrint('Unreadable manual food proposal ${proposal.id}: $error');
          return null;
        }
        final food = await Navigator.of(context).push<Food>(
          MaterialPageRoute(
            builder: (_) => ManualFoodScreen(
              repository:
                  nutritionRepository ?? DatabaseHelper.instance.nutritionRepo,
              source: FoodSource.aiCoach,
              initial: manualFood.draft,
            ),
          ),
        );
        return food == null ? null : {'food_id': food.id};
    }
    return null;
  }
}
