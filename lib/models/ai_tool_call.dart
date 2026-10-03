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

  /// Provider fields on the call besides `id`/`type`/`function` (for example
  /// Gemini's `extra_content.google.thought_signature`). They are opaque and
  /// sent back verbatim: some providers reject a follow-up request whose tool
  /// calls lost them.
  final Map<String, dynamic> extras;

  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.rawArguments,
    this.argumentsError,
    this.extras = const {},
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
              'arguments must be a JSON object, got ${parsed.runtimeType}.';
        }
      } on FormatException catch (error) {
        argumentsError = 'invalid JSON in arguments: ${error.message}';
      }
    } else if (rawArgs is Map) {
      args = rawArgs.cast<String, dynamic>();
    }
    final extras = <String, dynamic>{
      for (final entry in j.entries)
        if (!const {'id', 'type', 'function', 'index'}.contains(entry.key) &&
            entry.value != null)
          entry.key: entry.value,
    };
    return AiToolCall(
      id: (j['id'] as String?) ?? '',
      name: (fn['name'] as String?) ?? '',
      arguments: args,
      rawArguments: rawArguments,
      argumentsError: argumentsError,
      extras: extras,
    );
  }

  AiToolCall withId(String newId) => AiToolCall(
    id: newId,
    name: name,
    arguments: arguments,
    rawArguments: rawArguments,
    argumentsError: argumentsError,
    extras: extras,
  );

  /// OpenAI wire shape. [includeExtras] is false once the call belongs to an
  /// earlier turn: reasoning signatures only matter inside the turn that
  /// produced them.
  Map<String, dynamic> toJson({bool includeExtras = true}) => {
    'id': id,
    'type': 'function',
    'function': {
      'name': name,
      'arguments': argumentsError != null && rawArguments != null
          ? rawArguments
          : jsonEncode(arguments),
    },
    if (includeExtras) ...extras,
  };
}
