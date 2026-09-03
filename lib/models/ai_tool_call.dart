import 'dart:convert';

class AiToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  /// Raw `arguments` string exactly as the provider sent it. Kept so a call
  /// with unparseable arguments can be echoed back verbatim in the transcript.
  final String? rawArguments;

  /// Non-null when the provider's `arguments` string was not a JSON object.
  final String? argumentsError;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.rawArguments,
    this.argumentsError,
  });

  factory AiToolCall.fromJson(Map<String, dynamic> j) {
    final fn = (j['function'] as Map?)?.cast<String, dynamic>() ?? const {};
    final rawArgs = fn['arguments'];
    Map<String, dynamic> args = const {};
    String? rawArguments;
    String? argumentsError;
    if (rawArgs is String && rawArgs.trim().isNotEmpty) {
      rawArguments = rawArgs;
      try {
        final parsed = jsonDecode(rawArgs);
        if (parsed is Map) {
          args = parsed.cast<String, dynamic>();
        } else {
          argumentsError =
              'Os argumentos devem ser um objeto JSON; recebido '
              '${parsed.runtimeType}.';
        }
      } on FormatException catch (error) {
        argumentsError = 'JSON inválido nos argumentos: ${error.message}';
      }
    } else if (rawArgs is Map) {
      args = rawArgs.cast<String, dynamic>();
    }
    return AiToolCall(
      id: (j['id'] as String?) ?? '',
      name: (fn['name'] as String?) ?? '',
      arguments: args,
      rawArguments: rawArguments,
      argumentsError: argumentsError,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': 'function',
    'function': {
      'name': name,
      'arguments': argumentsError != null && rawArguments != null
          ? rawArguments
          : jsonEncode(arguments),
    },
  };
}
