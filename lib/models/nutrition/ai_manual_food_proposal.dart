import 'ai_food_label_draft.dart';

enum AiManualFoodProposalStatus {
  awaitingApproval,
  created,
  rejected;

  String get storageValue => switch (this) {
    awaitingApproval => 'awaiting_approval',
    created => 'created',
    rejected => 'rejected',
  };

  static AiManualFoodProposalStatus fromStorage(String? value) =>
      switch (value) {
        'created' => created,
        'rejected' => rejected,
        _ => awaitingApproval,
      };
}

/// A non-persisting AI proposal for a user-created food.
///
/// Approval opens the regular manual food form with [draft] pre-filled. The
/// food is only written when the user saves that form.
class AiManualFoodProposal {
  final AiFoodLabelDraft draft;
  final String? notes;
  final AiManualFoodProposalStatus status;
  final String? createdFoodId;

  const AiManualFoodProposal({
    required this.draft,
    this.notes,
    this.status = AiManualFoodProposalStatus.awaitingApproval,
    this.createdFoodId,
  });

  factory AiManualFoodProposal.fromJson(Map<String, dynamic> json) {
    final rawDraft = json['draft'];
    if (rawDraft is! Map) {
      throw const FormatException('missing food draft');
    }
    return AiManualFoodProposal(
      draft: AiFoodLabelDraft.fromJson(rawDraft.cast<String, dynamic>()),
      notes: _nullableString(json['notes']),
      status: AiManualFoodProposalStatus.fromStorage(json['status'] as String?),
      createdFoodId: _nullableString(json['createdFoodId']),
    );
  }

  AiManualFoodProposal copyWith({
    AiManualFoodProposalStatus? status,
    String? createdFoodId,
  }) => AiManualFoodProposal(
    draft: draft,
    notes: notes,
    status: status ?? this.status,
    createdFoodId: createdFoodId ?? this.createdFoodId,
  );

  Map<String, dynamic> toJson() => {
    'status': status.storageValue,
    'draft': draft.toJson(),
    if (notes != null) 'notes': notes,
    if (createdFoodId != null) 'createdFoodId': createdFoodId,
  };
}

String? _nullableString(dynamic value) {
  if (value is! String) return null;
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
