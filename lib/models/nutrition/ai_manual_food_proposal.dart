import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/utils/ai_json.dart';

/// The payload of a `manual_food` proposal: a food the AI drafted for the user
/// to review in the regular manual food form. Nothing is persisted until the
/// user saves that form; the proposal's status lives in `AiProposal`.
class AiManualFoodProposal {
  final AiFoodLabelDraft draft;
  final String? notes;

  const AiManualFoodProposal({required this.draft, this.notes});

  /// Reads a stored payload (`{draft, notes}`). Throws [FormatException] when
  /// the draft is missing or invalid.
  factory AiManualFoodProposal.fromJson(Map<String, dynamic> json) {
    final rawDraft = json['draft'];
    if (rawDraft is! Map) throw const FormatException('missing food draft');
    return AiManualFoodProposal(
      draft: AiFoodLabelDraft.fromJson(rawDraft.cast<String, dynamic>()),
      notes: AiJson.text(json['notes']),
    );
  }

  Map<String, dynamic> toJson() => {
    'draft': draft.toJson(),
    if (notes != null) 'notes': notes,
  };
}
