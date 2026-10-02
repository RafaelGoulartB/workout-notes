enum AiMessageRole {
  system,
  user,
  assistant,
  tool,

  /// Something the app did that the model must know about (a proposal was
  /// applied or rejected, a memory change was undone…). Persisted like any
  /// message and sent to the model as a short `<app_event>` user message.
  event,
}

extension AiMessageRoleX on AiMessageRole {
  String get wireValue {
    switch (this) {
      case AiMessageRole.system:
        return 'system';
      case AiMessageRole.user:
        return 'user';
      case AiMessageRole.assistant:
        return 'assistant';
      case AiMessageRole.tool:
        return 'tool';
      case AiMessageRole.event:
        return 'event';
    }
  }

  static AiMessageRole fromWire(String? value) {
    switch (value) {
      case 'user':
        return AiMessageRole.user;
      case 'assistant':
        return AiMessageRole.assistant;
      case 'tool':
        return AiMessageRole.tool;
      case 'event':
        return AiMessageRole.event;
      case 'system':
      default:
        return AiMessageRole.system;
    }
  }
}

class AiToolResult {
  final bool ok;
  final dynamic data;
  final String? code;
  final String? message;

  /// What the model can do next after a failure, e.g.
  /// `call list_routines to get valid ids`.
  final String? hint;

  /// Machine-readable facts about a failure, e.g.
  /// `{param, expected, received}` for `invalid_args`.
  final Map<String, dynamic>? details;

  const AiToolResult({
    required this.ok,
    this.data,
    this.code,
    this.message,
    this.hint,
    this.details,
  });

  factory AiToolResult.fromMap(Map<String, dynamic> m) {
    final details = m['details'];
    return AiToolResult(
      ok: (m['ok'] as bool?) ?? false,
      data: m['data'],
      code: m['code'] as String?,
      message: m['message'] as String?,
      hint: m['hint'] as String?,
      details: details is Map ? details.cast<String, dynamic>() : null,
    );
  }

  Map<String, dynamic> toMap() => {
    'ok': ok,
    if (data != null) 'data': data,
    if (code != null) 'code': code,
    if (message != null) 'message': message,
    if (hint != null) 'hint': hint,
    if (details != null) 'details': details,
  };
}
