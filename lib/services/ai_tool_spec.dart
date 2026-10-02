import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';

/// The model sent arguments a tool cannot use. The registry turns it into the
/// single `invalid_args` result shape, so handlers and services stay linear.
class AiToolArgException implements Exception {
  final String param;
  final String expected;
  final Object? received;
  final String message;

  const AiToolArgException._(
    this.param,
    this.expected,
    this.received,
    this.message,
  );

  /// A required argument is absent or blank.
  factory AiToolArgException.missing(String param) => AiToolArgException._(
    param,
    'a value',
    null,
    '$param: required',
  );

  /// An argument has the wrong type, format or value.
  factory AiToolArgException.invalid(
    String param,
    String expected,
    Object? received,
  ) => AiToolArgException._(
    param,
    expected,
    received,
    '$param: expected $expected, got ${_show(received)}',
  );

  /// A combination of arguments that cannot work together.
  factory AiToolArgException.conflict(String param, String message) =>
      AiToolArgException._(param, message, null, '$param: $message');

  static String _show(Object? value) =>
      value is String ? '"$value"' : '$value';

  AiToolResult toResult() => AiToolResult(
    ok: false,
    code: 'invalid_args',
    message: message,
    details: {
      'param': param,
      'expected': expected,
      if (received != null) 'received': received,
    },
  );

  @override
  String toString() => message;
}

/// The id (or date) the model asked about does not exist.
class AiToolNotFoundException implements Exception {
  final String message;
  final String? hint;

  const AiToolNotFoundException(this.message, {this.hint});

  AiToolResult toResult() => AiToolResult(
    ok: false,
    code: 'not_found',
    message: message,
    hint: hint,
  );

  @override
  String toString() => message;
}

final RegExp _isoDatePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

/// Typed, forgiving argument readers for tool handlers.
///
/// Models are inconsistent about naming, so every reader accepts the
/// documented snake_case key and its camelCase spelling. A blank string always
/// means "not provided". Out-of-range integers are clamped and the adjustment
/// is collected in [adjusted] so the result can echo it under `applied`.
class AiToolArgs {
  final Map<String, dynamic> raw;

  /// `{param: {requested, used}}` for every integer that had to be clamped.
  final Map<String, Map<String, int>> adjusted = {};

  AiToolArgs(this.raw);

  dynamic operator [](String key) => raw[key];

  static String _camel(String snake) {
    final parts = snake.split('_');
    return parts.first +
        parts
            .skip(1)
            .map(
              (p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}',
            )
            .join();
  }

  dynamic _value(String key, [String? alt]) {
    final value = raw[key] ?? raw[_camel(key)] ?? (alt == null ? null : raw[alt]);
    if (value is String && value.trim().isEmpty) return null;
    return value;
  }

  /// Whether the model passed a non-blank value for [key].
  bool has(String key) => _value(key) != null;

  /// Trimmed non-empty string under [key], its camelCase spelling or [alt].
  /// Numbers are accepted and stringified (some models send ids as numbers).
  String? string(String key, {String? alt}) {
    final value = _value(key, alt);
    if (value == null) return null;
    if (value is String) return value.trim();
    if (value is num || value is bool) return '$value';
    throw AiToolArgException.invalid(key, 'a string', value);
  }

  /// Like [string], but fails with `invalid_args` when missing.
  String requiredString(String key) {
    final value = string(key);
    if (value == null) throw AiToolArgException.missing(key);
    return value;
  }

  /// `yyyy-MM-dd` for the date under [key]; null when absent. A full ISO
  /// timestamp is accepted and cut to its date. Anything else fails with
  /// `invalid_args`.
  String? date(String key, {String? alt}) {
    final text = string(key, alt: alt);
    if (text == null) return null;
    final candidate = text.length > 10 && text[10] == 'T'
        ? text.substring(0, 10)
        : text;
    if (!_isoDatePattern.hasMatch(candidate)) {
      throw AiToolArgException.invalid(key, 'YYYY-MM-DD', text);
    }
    final parsed = DateTime.tryParse(candidate);
    if (parsed == null || _key(parsed) != candidate) {
      throw AiToolArgException.invalid(key, 'YYYY-MM-DD', text);
    }
    return candidate;
  }

  static String _key(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';

  /// Integer under [key], or [fallback]; clamped to [min]..[max] with the
  /// adjustment reported.
  int integer(String key, {required int fallback, int? min, int? max}) =>
      integerOrNull(key, min: min, max: max) ?? fallback;

  /// Like [integer] but null when absent.
  int? integerOrNull(String key, {int? min, int? max}) {
    final value = _value(key);
    if (value == null) return null;
    final int parsed;
    if (value is num) {
      parsed = value.round();
    } else if (value is String) {
      final number = num.tryParse(value.trim());
      if (number == null) throw AiToolArgException.invalid(key, 'an integer', value);
      parsed = number.round();
    } else {
      throw AiToolArgException.invalid(key, 'an integer', value);
    }
    var used = parsed;
    if (min != null && used < min) used = min;
    if (max != null && used > max) used = max;
    if (used != parsed) adjusted[key] = {'requested': parsed, 'used': used};
    return used;
  }

  /// Boolean under [key]: `true`/`false` or the strings "true"/"false".
  bool? boolean(String key) {
    final value = _value(key);
    if (value == null) return null;
    if (value is bool) return value;
    if (value is String) {
      switch (value.trim().toLowerCase()) {
        case 'true':
          return true;
        case 'false':
          return false;
      }
    }
    throw AiToolArgException.invalid(key, 'true or false', value);
  }

  bool flag(String key, {bool fallback = false}) => boolean(key) ?? fallback;

  /// One of [allowed] (case-insensitive) or [fallback]/null when absent.
  String? enumValue(String key, List<String> allowed, {String? fallback}) {
    final text = string(key);
    if (text == null) return fallback;
    for (final option in allowed) {
      if (option.toLowerCase() == text.toLowerCase()) return option;
    }
    throw AiToolArgException.invalid(
      key,
      'one of ${allowed.join(', ')}',
      text,
    );
  }
}

AiToolResult aiToolOk(Map<String, dynamic> data) =>
    AiToolResult(ok: true, data: data);

typedef AiToolHandler = Future<AiToolResult> Function(AiToolArgs args);

/// Builders for JSON-schema parameters, so every tool describes the same
/// argument the same way and the catalog stays small.
abstract final class AiParam {
  static Map<String, dynamic> string(String description) => {
    'type': 'string',
    'description': description,
  };

  /// A `YYYY-MM-DD` date.
  static Map<String, dynamic> date(String description) => {
    'type': 'string',
    'description': '$description (YYYY-MM-DD).',
  };

  static Map<String, dynamic> integer(
    String description, {
    int? min,
    int? max,
  }) => {
    'type': 'integer',
    'description': description,
    'minimum': ?min,
    'maximum': ?max,
  };

  static Map<String, dynamic> boolean(String description) => {
    'type': 'boolean',
    'description': description,
  };

  static Map<String, dynamic> enumOf(
    List<String> values,
    String description,
  ) => {'type': 'string', 'enum': values, 'description': description};

  /// Look-back window ending at `end_date` (or today).
  static Map<String, dynamic> days(int fallback, int min, int max) => integer(
    'Window in days (default $fallback).',
    min: min,
    max: max,
  );

  static Map<String, dynamic> startDate() => date('From');

  static Map<String, dynamic> endDate([String? note]) =>
      date(note == null ? 'To' : 'To, $note');

  /// Row limit. `minimum` is left out on purpose (always 1; the handler
  /// clamps) to keep the catalog small.
  static Map<String, dynamic> limit(int fallback, int max) => {
    'type': 'integer',
    'description': 'Default $fallback.',
    'maximum': max,
  };

  static Map<String, dynamic> page() => {
    'type': 'integer',
    'description': 'Default 1.',
  };
}

/// One entry of the model-facing tool catalog: its OpenAI function schema and
/// the handler that executes it. Proposal tools that are not executed through
/// the registry have a null [handler].
class AiToolSpec {
  final String name;

  /// Full `{type: function, function: {...}}` entry, built once.
  final Map<String, dynamic> schema;
  final AiToolHandler? handler;

  /// True for tools that only prepare a guarded proposal (never read data).
  final bool proposal;

  /// Domain the tool belongs to; a domain the user switched off removes the
  /// tool from the catalog.
  final AiToolDomain domain;

  /// Decimals to keep for result keys that differ from the shaper's default
  /// rule (see `AiToolResultShaper`).
  final Map<String, int> decimals;

  const AiToolSpec._(
    this.name,
    this.schema,
    this.handler,
    this.proposal,
    this.domain,
    this.decimals,
  );

  /// [properties] empty means a no-argument tool: `parameters` is omitted
  /// entirely. `required` is only emitted when non-empty.
  factory AiToolSpec({
    required String name,
    required String description,
    Map<String, dynamic> properties = const <String, dynamic>{},
    List<String> required = const [],
    AiToolHandler? handler,
    bool proposal = false,
    AiToolDomain domain = AiToolDomain.core,
    Map<String, int> decimals = const {},
  }) => AiToolSpec._(
    name,
    {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        if (properties.isNotEmpty)
          'parameters': {
            'type': 'object',
            'properties': properties,
            if (required.isNotEmpty) 'required': required,
          },
      },
    },
    handler,
    proposal,
    domain,
    decimals,
  );
}
