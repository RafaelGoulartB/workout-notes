import 'dart:convert';

enum AiToolResultCode {
  ok,
  unknownTool,
  invalidArgs,
  notFound,
  error,
  interrupted,
}

class AiToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  factory AiToolCall.fromJson(Map<String, dynamic> j) {
    final fn = (j['function'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawArgs = fn['arguments'];
    Map<String, dynamic> args = const {};
    if (rawArgs is String && rawArgs.isNotEmpty) {
      try {
        final parsed = jsonDecode(rawArgs);
        if (parsed is Map) {
          args = parsed.cast<String, dynamic>();
        }
      } catch (_) {
        args = const {};
      }
    } else if (rawArgs is Map) {
      args = rawArgs.cast<String, dynamic>();
    }
    return AiToolCall(
      id: (j['id'] as String?) ?? '',
      name: (fn['name'] as String?) ?? '',
      arguments: args,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {'name': name, 'arguments': jsonEncode(arguments)},
  };
}
