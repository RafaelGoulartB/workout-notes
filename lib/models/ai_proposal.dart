import 'dart:convert';

/// Version of the preview JSON written by the proposal handlers and read by the
/// card. A stored preview with another (or no) version is rebuilt by its
/// handler when read (rows migrated from `ai_routine_proposals`).
const int kAiProposalPreviewVersion = 2;

/// Lifecycle of an AI proposal. Only [awaiting] can be approved or rejected.
enum AiProposalStatus {
  awaiting,
  applied,
  rejected,
  stale,
  failed,
  expired;

  String get storageValue => name;

  static AiProposalStatus fromStorage(String? value) =>
      AiProposalStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => AiProposalStatus.failed,
      );
}

/// How an approved proposal reaches the database.
enum AiProposalApplyMode {
  /// The app applies the payload in one SQLite transaction on approval.
  transactional,

  /// Approval opens a pre-filled form; the change happens only when the user
  /// saves it there (then [AiProposal] is marked applied with the result).
  userConfirmed,
}

/// A change the AI prepared for the user to approve, persisted in
/// `ai_proposals`. [kind] selects the handler (`routine`, `meal_log`, …);
/// [payload] is the validated change, [preview] the language-neutral data the
/// card renders, [base]/[baseHash] the state the proposal was made against.
class AiProposal {
  final String id;
  final String threadId;
  final String toolCallId;
  final String kind;
  final String? subjectId;
  final String? baseHash;
  final Map<String, dynamic>? base;
  final Map<String, dynamic> payload;
  final Map<String, dynamic> preview;
  final AiProposalStatus status;
  final Map<String, dynamic>? result;
  final String? errorCode;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  const AiProposal({
    required this.id,
    required this.threadId,
    required this.toolCallId,
    required this.kind,
    required this.payload,
    required this.preview,
    required this.status,
    required this.createdAt,
    this.subjectId,
    this.baseHash,
    this.base,
    this.result,
    this.errorCode,
    this.resolvedAt,
  });

  bool get isPending => status == AiProposalStatus.awaiting;

  AiProposal copyWith({
    AiProposalStatus? status,
    Map<String, dynamic>? result,
    String? errorCode,
    bool clearError = false,
    DateTime? resolvedAt,
    Map<String, dynamic>? preview,
  }) => AiProposal(
    id: id,
    threadId: threadId,
    toolCallId: toolCallId,
    kind: kind,
    subjectId: subjectId,
    baseHash: baseHash,
    base: base,
    payload: payload,
    preview: preview ?? this.preview,
    status: status ?? this.status,
    result: result ?? this.result,
    errorCode: clearError ? null : (errorCode ?? this.errorCode),
    createdAt: createdAt,
    resolvedAt: resolvedAt ?? this.resolvedAt,
  );

  Map<String, dynamic> toRow() => {
    'id': id,
    'thread_id': threadId,
    'tool_call_id': toolCallId,
    'kind': kind,
    'subject_id': subjectId,
    'base_hash': baseHash,
    'base_json': base == null ? null : jsonEncode(base),
    'payload_json': jsonEncode(payload),
    'preview_json': jsonEncode(preview),
    'status': status.storageValue,
    'result_json': result == null ? null : jsonEncode(result),
    'error_code': errorCode,
    'created_at': createdAt.toIso8601String(),
    'resolved_at': resolvedAt?.toIso8601String(),
  };

  static AiProposal fromRow(Map<String, dynamic> row) => AiProposal(
    id: row['id'] as String,
    threadId: row['thread_id'] as String,
    toolCallId: row['tool_call_id'] as String,
    kind: row['kind'] as String,
    subjectId: row['subject_id'] as String?,
    baseHash: row['base_hash'] as String?,
    base: _map(row['base_json']),
    payload: _map(row['payload_json']) ?? const {},
    preview: _map(row['preview_json']) ?? const {},
    status: AiProposalStatus.fromStorage(row['status'] as String?),
    result: _map(row['result_json']),
    errorCode: row['error_code'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
    resolvedAt: row['resolved_at'] == null
        ? null
        : DateTime.tryParse(row['resolved_at'] as String),
  );

  static Map<String, dynamic>? _map(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }
}
