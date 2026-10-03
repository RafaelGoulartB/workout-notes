import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// A typed failure of a proposal. Raised while preparing (the model receives
/// it as `ok:false` with a `hint` it can act on) and while approving (the
/// proposal ends `stale` or `failed`; [code] is stored in `error_code` and
/// localized by the UI, never shown raw).
class AiProposalException implements Exception {
  /// Stable machine code (`invalid_args`, `not_found`, `stale_revision`…).
  final String code;

  /// Short English description for the model and the logs.
  final String message;

  /// What the model should do next (e.g. "call get_routine_detail again").
  final String? hint;

  /// Offending argument path (`routine.days[1].exercises[0].sets[2].reps`).
  final String? param;
  final String? expected;
  final Object? received;

  /// True when the data changed since the proposal was prepared: the proposal
  /// ends `stale` instead of `failed`.
  final bool stale;

  const AiProposalException(
    this.code,
    this.message, {
    this.hint,
    this.param,
    this.expected,
    this.received,
    this.stale = false,
  });

  /// The change no longer matches the data it was prepared against.
  const AiProposalException.stale(
    this.code,
    this.message, {
    this.hint = 'Read the data again and prepare a new proposal.',
  }) : param = null,
       expected = null,
       received = null,
       stale = true;

  /// What the model sees for a failed `propose_*` call.
  AiToolResult toToolResult() => AiToolResult(
    ok: false,
    code: code,
    message: message,
    data: {
      'param': ?param,
      'expected': ?expected,
      if (received != null) 'received': _clip(received),
      'hint': ?hint,
    },
  );

  static Object? _clip(Object? value) {
    final text = '$value';
    return text.length <= 120 ? value : '${text.substring(0, 117)}...';
  }

  @override
  String toString() => 'AiProposalException($code): $message';
}

/// What a handler produces from the model's arguments: the validated change
/// plus everything needed to show it honestly and to detect that the data
/// moved before approval.
class AiProposalDraft {
  /// The validated, normalised change the handler applies on approval.
  final Map<String, dynamic> payload;

  /// Language-neutral data the card renders (see `AiProposalCard`).
  final Map<String, dynamic> preview;

  /// Snapshot of what the change is based on, when the handler needs one.
  final Map<String, dynamic>? base;
  final String? baseHash;

  /// Id of the entity being changed (routine, goal, plan…), when there is one.
  final String? subjectId;

  /// Compact facts the model can mention ("3 foods, 640 kcal").
  final Map<String, dynamic> summary;

  const AiProposalDraft({
    required this.payload,
    required this.preview,
    this.base,
    this.baseHash,
    this.subjectId,
    this.summary = const {},
  });
}

/// One kind of proposal: its tool, validation, preview and apply logic.
///
/// Handlers never write while preparing. [apply] runs inside the approval
/// transaction, after [revalidate], so it may assume the data still matches
/// the proposal's base.
abstract class AiProposalHandler {
  const AiProposalHandler();

  /// Stored in `ai_proposals.kind`.
  String get kind;

  /// The `propose_*` tool that creates this kind of proposal.
  String get toolName;

  AiToolDomain get domain;

  AiProposalApplyMode get applyMode => AiProposalApplyMode.transactional;

  /// The model-facing tool (schema + description). Its handler is unused:
  /// calls go through `AiProposalService.prepare`.
  AiToolSpec get spec;

  /// [spec] ready for the catalog: an empty `required` list is dropped (some
  /// providers reject it).
  AiToolSpec get catalogSpec {
    final built = spec;
    final parameters =
        (built.schema['function'] as Map)['parameters'] as Map<String, dynamic>;
    final required = parameters['required'];
    if (required is List && required.isEmpty) parameters.remove('required');
    return built;
  }

  /// Validates [args] and builds the draft. Reads through [db]; never writes.
  /// Throws [AiProposalException] for anything the model can fix.
  Future<AiProposalDraft> prepare(DatabaseExecutor db, AiProposalArgs args);

  /// Runs in the approval transaction before [apply]. Returns a stable stale
  /// code (`stale_revision`, `stale_target_missing`, …) when the proposal no
  /// longer matches the data, null when it is still valid.
  Future<String?> revalidate(DatabaseExecutor txn, AiProposal proposal) async =>
      null;

  /// Applies the change inside the approval transaction and returns the
  /// result stored in `result_json`. Must throw [AiProposalException] (or any
  /// error) instead of swallowing a failure: the transaction rolls back and
  /// the proposal ends `failed`/`stale`.
  Future<Map<String, dynamic>> apply(
    DatabaseExecutor txn,
    AiProposal proposal,
  ) => throw UnsupportedError('$kind proposals are applied by a form');

  /// True when [proposal]'s stored preview must be rebuilt by
  /// [rebuildPreview] (written by an older version of the app).
  bool needsPreviewRefresh(AiProposal proposal) =>
      proposal.preview['v'] != kAiProposalPreviewVersion;

  /// Rebuilds the preview of an older proposal from its payload/base, or null
  /// when that is not possible.
  Future<Map<String, dynamic>?> rebuildPreview(
    DatabaseExecutor db,
    AiProposal proposal,
  ) async => null;

  /// Compact facts about an applied proposal for the model's transcript.
  Map<String, dynamic> resultFacts(AiProposal proposal) =>
      proposal.result ?? const {};
}

/// Strict, typed reader of a tool call's arguments. Every reader names the
/// offending path in its error so the model can fix the exact field instead of
/// resending the whole call.
class AiProposalArgs {
  final Map<String, dynamic> raw;

  /// Path of this object inside the call (`routine.days[0]`), empty at root.
  final String path;

  const AiProposalArgs(this.raw, {this.path = ''});

  String _at(String key) => path.isEmpty ? key : '$path.$key';

  /// A value the model really supplied: null and blank strings are the
  /// placeholders models write into optional fields, so they count as absent.
  bool has(String key) => !_blank(raw[key]);

  static bool _blank(Object? value) =>
      value == null || (value is String && value.trim().isEmpty);

  /// Rejects keys outside [allowed] so a misspelled or invented field is
  /// reported instead of silently ignored.
  void allowOnly(Set<String> allowed) {
    for (final key in raw.keys) {
      if (!allowed.contains(key)) {
        final sorted = allowed.toList()..sort();
        throw AiProposalException(
          'invalid_args',
          'Unknown argument "${_at(key)}".',
          param: _at(key),
          expected: 'one of: ${sorted.join(', ')}',
          hint: 'Remove "${_at(key)}" and use only the documented fields.',
        );
      }
    }
  }

  String? optionalString(
    String key, {
    int maxLength = 500,
    bool allowEmpty = false,
  }) {
    final value = raw[key];
    if (value == null) return null;
    if (value is! String) {
      throw _type(key, 'string', value);
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      if (allowEmpty) return '';
      return null;
    }
    if (trimmed.length > maxLength) {
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" is too long.',
        param: _at(key),
        expected: 'at most $maxLength characters',
        received: '${trimmed.length} characters',
        hint: 'Shorten "${_at(key)}".',
      );
    }
    return trimmed;
  }

  String requiredString(String key, {int maxLength = 500}) {
    final value = optionalString(key, maxLength: maxLength);
    if (value == null) throw _missing(key, 'non-empty string');
    return value;
  }

  /// A number in [min]..[max]. With [zeroIsAbsent] a 0 is the placeholder a
  /// model writes into an optional field and reads as "not given".
  double? optionalNumber(
    String key, {
    double? min,
    double? max,
    bool zeroIsAbsent = false,
  }) {
    final value = raw[key];
    if (_blank(value)) return null;
    if (zeroIsAbsent && value is num && value == 0) return null;
    if (value is! num || value.isNaN || value.isInfinite) {
      throw _type(key, 'number', value);
    }
    final number = value.toDouble();
    _range(key, number, min, max);
    return number;
  }

  double requiredNumber(String key, {double? min, double? max}) {
    final value = optionalNumber(key, min: min, max: max);
    if (value == null) throw _missing(key, 'number');
    return value;
  }

  /// An integer in [min]..[max]; see [optionalNumber] for [zeroIsAbsent].
  int? optionalInt(
    String key, {
    int? min,
    int? max,
    bool zeroIsAbsent = false,
  }) {
    final value = raw[key];
    if (_blank(value)) return null;
    if (zeroIsAbsent && value is num && value == 0) return null;
    if (value is! num || value.isNaN || value.isInfinite) {
      throw _type(key, 'integer', value);
    }
    if (value != value.roundToDouble()) {
      throw _type(key, 'integer', value);
    }
    final number = value.toInt();
    _range(key, number.toDouble(), min?.toDouble(), max?.toDouble());
    return number;
  }

  int requiredInt(String key, {int? min, int? max}) {
    final value = optionalInt(key, min: min, max: max);
    if (value == null) throw _missing(key, 'integer');
    return value;
  }

  bool? optionalBool(String key) {
    final value = raw[key];
    if (_blank(value)) return null;
    if (value is! bool) throw _type(key, 'boolean', value);
    return value;
  }

  String? optionalEnum(String key, List<String> allowed) {
    final value = raw[key];
    if (_blank(value)) return null;
    if (value is! String || !allowed.contains(value.trim())) {
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" is not an allowed value.',
        param: _at(key),
        expected: 'one of: ${allowed.join(', ')}',
        received: value,
        hint: 'Use exactly one of: ${allowed.join(', ')}.',
      );
    }
    return value.trim();
  }

  String requiredEnum(String key, List<String> allowed) {
    final value = optionalEnum(key, allowed);
    if (value == null) throw _missing(key, 'one of: ${allowed.join(', ')}');
    return value;
  }

  /// A calendar date written `YYYY-MM-DD` (rejects `2026-02-30`).
  String? optionalDate(String key) {
    final value = raw[key];
    if (_blank(value)) return null;
    if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" must be a date.',
        param: _at(key),
        expected: 'YYYY-MM-DD',
        received: value,
        hint: 'Write the date as YYYY-MM-DD, for example 2026-09-30.',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null || dateKey(parsed) != value) {
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" is not a real calendar date.',
        param: _at(key),
        expected: 'YYYY-MM-DD',
        received: value,
        hint: 'Use a date that exists, as YYYY-MM-DD.',
      );
    }
    return value;
  }

  String requiredDate(String key) {
    final value = optionalDate(key);
    if (value == null) throw _missing(key, 'YYYY-MM-DD');
    return value;
  }

  AiProposalArgs? optionalObject(String key) {
    final value = raw[key];
    if (value == null) return null;
    if (value is! Map) throw _type(key, 'object', value);
    return AiProposalArgs(value.cast<String, dynamic>(), path: _at(key));
  }

  AiProposalArgs requiredObject(String key) {
    final value = optionalObject(key);
    if (value == null) throw _missing(key, 'object');
    return value;
  }

  /// Array of objects with [min]..[max] entries; null when absent.
  List<AiProposalArgs>? optionalObjects(String key, {int min = 0, int? max}) {
    final value = raw[key];
    if (value == null) return null;
    if (value is! List) throw _type(key, 'array', value);
    if (value.length < min || (max != null && value.length > max)) {
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" has ${value.length} entries.',
        param: _at(key),
        expected: max == null
            ? 'at least $min entries'
            : 'between $min and $max entries',
        received: '${value.length} entries',
        hint: max != null && value.length > max
            ? 'Split the change in several proposals of at most $max entries.'
            : 'Provide at least $min entries.',
      );
    }
    return [
      for (var i = 0; i < value.length; i++)
        if (value[i] is Map)
          AiProposalArgs(
            (value[i] as Map).cast<String, dynamic>(),
            path: '${_at(key)}[$i]',
          )
        else
          throw AiProposalException(
            'invalid_args',
            '"${_at(key)}[$i]" must be an object.',
            param: '${_at(key)}[$i]',
            expected: 'object',
            received: value[i],
            hint: 'Every entry of "${_at(key)}" must be a JSON object.',
          ),
    ];
  }

  List<AiProposalArgs> requiredObjects(String key, {int min = 1, int? max}) {
    final value = optionalObjects(key, min: min, max: max);
    if (value == null) throw _missing(key, 'array of objects');
    return value;
  }

  void _range(String key, double value, double? min, double? max) {
    if ((min != null && value < min) || (max != null && value > max)) {
      final bounds = min != null && max != null
          ? 'between ${_num(min)} and ${_num(max)}'
          : min != null
          ? 'at least ${_num(min)}'
          : 'at most ${_num(max!)}';
      throw AiProposalException(
        'invalid_args',
        '"${_at(key)}" is out of range.',
        param: _at(key),
        expected: bounds,
        received: value,
        hint: 'Use a value $bounds.',
      );
    }
  }

  static String _num(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';

  AiProposalException _missing(String key, String expected) =>
      AiProposalException(
        'invalid_args',
        '"${_at(key)}" is required.',
        param: _at(key),
        expected: expected,
        hint: 'Add "${_at(key)}" ($expected).',
      );

  AiProposalException _type(String key, String expected, Object? value) =>
      AiProposalException(
        'invalid_args',
        '"${_at(key)}" must be $expected.',
        param: _at(key),
        expected: expected,
        received: value,
        hint: 'Send "${_at(key)}" as $expected.',
      );
}
