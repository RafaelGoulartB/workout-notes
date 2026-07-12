enum AiMessageRole { system, user, assistant, tool }

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

  const AiToolResult({required this.ok, this.data, this.code, this.message});

  factory AiToolResult.fromMap(Map<String, dynamic> m) {
    return AiToolResult(
      ok: (m['ok'] as bool?) ?? false,
      data: m['data'],
      code: m['code'] as String?,
      message: m['message'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'ok': ok,
    if (data != null) 'data': data,
    if (code != null) 'code': code,
    if (message != null) 'message': message,
  };
}
