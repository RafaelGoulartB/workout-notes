import 'dart:convert';

enum AiRoutineProposalStatus {
  awaitingApproval,
  applying,
  applied,
  rejected,
  stale,
  failed;

  String get storageValue => name;

  static AiRoutineProposalStatus fromStorage(String? value) =>
      AiRoutineProposalStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => AiRoutineProposalStatus.failed,
      );
}

enum AiRoutineProposalAction {
  create,
  update;

  String get storageValue => name;

  static AiRoutineProposalAction fromStorage(String? value) => switch (value) {
    'create' => AiRoutineProposalAction.create,
    'update' => AiRoutineProposalAction.update,
    _ => throw FormatException('Ação de proposta inválida: $value'),
  };
}

/// Persisted, user-approvable routine mutation prepared by the AI.
class AiRoutineProposal {
  final String id;
  final String threadId;
  final String toolCallId;
  final AiRoutineProposalAction action;
  final String? routineId;
  final Map<String, dynamic>? before;
  final Map<String, dynamic> target;
  final Map<String, dynamic> diff;
  final AiRoutineProposalStatus status;
  final String? appliedRoutineId;
  final String? errorCode;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AiRoutineProposal({
    required this.id,
    required this.threadId,
    required this.toolCallId,
    required this.action,
    required this.target,
    required this.diff,
    required this.status,
    required this.createdAt,
    this.routineId,
    this.before,
    this.appliedRoutineId,
    this.errorCode,
    this.errorMessage,
    this.resolvedAt,
  });

  String get routineName => (target['name'] as String?)?.trim() ?? '';
  bool get hasRemovals =>
      ((diff['removed'] as Map?)?['total'] as num? ?? 0) > 0;

  Map<String, dynamic> toRow() => {
    'id': id,
    'thread_id': threadId,
    'tool_call_id': toolCallId,
    'action': action.storageValue,
    'routine_id': routineId,
    'before_json': before == null ? null : jsonEncode(before),
    'target_json': jsonEncode(target),
    'diff_json': jsonEncode(diff),
    'status': status.storageValue,
    'applied_routine_id': appliedRoutineId,
    'error_code': errorCode,
    'error_message': errorMessage,
    'created_at': createdAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
  };

  factory AiRoutineProposal.fromRow(Map<String, dynamic> row) {
    Map<String, dynamic>? decodeNullable(dynamic value) {
      if (value is! String || value.isEmpty) return null;
      final decoded = jsonDecode(value);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    }

    Map<String, dynamic> decodeRequired(dynamic value) =>
        decodeNullable(value) ?? const {};

    return AiRoutineProposal(
      id: row['id'] as String,
      threadId: row['thread_id'] as String,
      toolCallId: row['tool_call_id'] as String,
      action: AiRoutineProposalAction.fromStorage(row['action'] as String?),
      routineId: row['routine_id'] as String?,
      before: decodeNullable(row['before_json']),
      target: decodeRequired(row['target_json']),
      diff: decodeRequired(row['diff_json']),
      status: AiRoutineProposalStatus.fromStorage(row['status'] as String?),
      appliedRoutineId: row['applied_routine_id'] as String?,
      errorCode: row['error_code'] as String?,
      errorMessage: row['error_message'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.tryParse(row['resolved_at'] as String),
    );
  }

  AiRoutineProposal copyWith({
    AiRoutineProposalStatus? status,
    String? appliedRoutineId,
    String? errorCode,
    String? errorMessage,
    DateTime? resolvedAt,
  }) => AiRoutineProposal(
    id: id,
    threadId: threadId,
    toolCallId: toolCallId,
    action: action,
    routineId: routineId,
    before: before,
    target: target,
    diff: diff,
    status: status ?? this.status,
    appliedRoutineId: appliedRoutineId ?? this.appliedRoutineId,
    errorCode: errorCode ?? this.errorCode,
    errorMessage: errorMessage ?? this.errorMessage,
    createdAt: createdAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );
}
