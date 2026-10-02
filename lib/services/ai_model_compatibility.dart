part of 'ai_service.dart';

/// Per-model compatibility flags learned from provider errors.
extension AiServiceCompatibility on AiService {
  _ModelCompatibility _compatibilityFor(String baseUrl, String model) =>
      _modelCompatibility.putIfAbsent(
        _compatibilityKey(baseUrl, model),
        _ModelCompatibility.new,
      );

  String _compatibilityKey(String baseUrl, String model) {
    final uri = Uri.tryParse(baseUrl);
    final endpoint = uri == null
        ? baseUrl.trim().toLowerCase()
        : '${uri.scheme.toLowerCase()}://${uri.host.toLowerCase()}'
              '${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
    return '$endpoint|${model.trim().toLowerCase()}';
  }

  Future<void> _persistCompatibility() async {
    final store = _store;
    if (store == null) return;
    try {
      await store.save({
        for (final entry in _modelCompatibility.entries)
          if (entry.value.adjustments.isNotEmpty)
            entry.key: entry.value.toJson(),
      });
    } catch (error) {
      debugPrint('Saving AI compatibility flags failed: $error');
    }
  }

  String? _applyCompatibilityAdjustment({
    required String responseBody,
    required Map<String, dynamic> sentPayload,
    required _ModelCompatibility compatibility,
  }) {
    final error = responseBody.toLowerCase();
    String? learn(bool condition, void Function() apply, String label) {
      if (!condition) return null;
      apply();
      return compatibility.record(label);
    }

    final mentionsReasoningEffort =
        error.contains('reasoning_effort') ||
        (error.contains('reasoning') && error.contains('effort'));
    final reasoningUnsupported =
        mentionsReasoningEffort &&
        (_rejects(error, 'reasoning_effort') ||
            _rejects(error, 'reasoning.effort') ||
            _rejects(error, 'reasoning') ||
            _rejects(error, 'effort'));
    if (reasoningUnsupported &&
        (sentPayload.containsKey('reasoning_effort') ||
            sentPayload.containsKey('reasoning')) &&
        !compatibility.omitReasoningEffort) {
      return learn(
        true,
        () => compatibility.omitReasoningEffort = true,
        'reasoning_effort omitted',
      );
    }
    if (error.contains('temperature')) {
      final mustBeOne =
          RegExp(
            r'(only|must be|has to be|required|allowed|support(?:ed|s)?)\D{0,24}1(?:\.0+)?\b',
          ).hasMatch(error) ||
          RegExp(r'1(?:\.0+)?\D{0,24}(only|temperature)').hasMatch(error);
      if (mustBeOne &&
          sentPayload['temperature'] != 1 &&
          compatibility.temperatureOverride != 1) {
        return learn(
          true,
          () => compatibility.temperatureOverride = 1,
          'temperature=1',
        );
      }
      if (_rejects(error, 'temperature') &&
          sentPayload.containsKey('temperature') &&
          !compatibility.omitTemperature) {
        return learn(
          true,
          () => compatibility.omitTemperature = true,
          'temperature omitted',
        );
      }
    }
    if (sentPayload.containsKey('stream_options') &&
        _mentions(error, 'stream_options') &&
        !compatibility.omitStreamOptions) {
      return learn(
        true,
        () => compatibility.omitStreamOptions = true,
        'stream_options omitted',
      );
    }
    if (sentPayload['stream'] == true &&
        _rejects(error, 'stream') &&
        !compatibility.streamUnsupported) {
      return learn(
        true,
        () => compatibility.streamUnsupported = true,
        'streaming disabled',
      );
    }
    if (sentPayload.containsKey('prompt_cache_key') &&
        _mentions(error, 'prompt_cache_key')) {
      return learn(
        !compatibility.omitCacheKey,
        () => compatibility.omitCacheKey = true,
        'prompt_cache_key omitted',
      );
    }
    if (sentPayload.containsKey('cache_control') &&
        _mentions(error, 'cache_control')) {
      return learn(
        !compatibility.omitCacheControl,
        () => compatibility.omitCacheControl = true,
        'cache_control omitted',
      );
    }
    if ((sentPayload.containsKey('max_completion_tokens') ||
            sentPayload.containsKey('max_output_tokens')) &&
        (error.contains('max_completion_tokens') ||
            error.contains('max_output_tokens'))) {
      return learn(
        !compatibility.omitMaxTokens,
        () => compatibility.omitMaxTokens = true,
        'max tokens omitted',
      );
    }
    if (sentPayload.containsKey('include') &&
        (error.contains('encrypted_content') || _rejects(error, 'include'))) {
      return learn(
        !compatibility.omitReasoningInclude,
        () => compatibility.omitReasoningInclude = true,
        'reasoning include omitted',
      );
    }
    if (sentPayload.containsKey('tool_choice') &&
        _rejects(error, 'tool_choice') &&
        !compatibility.omitToolChoice) {
      return learn(
        true,
        () => compatibility.omitToolChoice = true,
        'tool_choice omitted',
      );
    }
    return null;
  }
}

/// [parameter] as a whole word (`stream` does not match `upstream` or
/// `stream_options`).
bool _mentions(String error, String parameter) => RegExp(
  '(^|[^a-z0-9_.])${RegExp.escape(parameter)}(\$|[^a-z0-9_])',
).hasMatch(error);

bool _rejects(String error, String parameter) =>
    _mentions(error, parameter) &&
    (error.contains('unsupported') ||
        error.contains('not supported') ||
        error.contains('unknown') ||
        error.contains('unrecognized') ||
        error.contains('not allowed') ||
        error.contains('extra inputs') ||
        error.contains('additional properties') ||
        error.contains('invalid') ||
        error.contains('does not support'));

class _ModelCompatibility {
  double? temperatureOverride;
  bool omitTemperature = false;
  bool omitToolChoice = false;
  bool omitReasoningEffort = false;
  bool omitStreamOptions = false;
  bool streamUnsupported = false;
  bool omitCacheKey = false;
  bool omitCacheControl = false;
  bool omitMaxTokens = false;
  bool omitReasoningInclude = false;
  final Set<String> adjustments = {};

  _ModelCompatibility();

  factory _ModelCompatibility.fromJson(Map<String, dynamic> json) {
    final c = _ModelCompatibility()
      ..temperatureOverride = (json['temperatureOverride'] as num?)?.toDouble()
      ..omitTemperature = json['omitTemperature'] == true
      ..omitToolChoice = json['omitToolChoice'] == true
      ..omitReasoningEffort = json['omitReasoningEffort'] == true
      ..omitStreamOptions = json['omitStreamOptions'] == true
      ..streamUnsupported = json['streamUnsupported'] == true
      ..omitCacheKey = json['omitCacheKey'] == true
      ..omitCacheControl = json['omitCacheControl'] == true
      ..omitMaxTokens = json['omitMaxTokens'] == true
      ..omitReasoningInclude = json['omitReasoningInclude'] == true;
    final adjustments = json['adjustments'];
    if (adjustments is List) {
      c.adjustments.addAll(adjustments.whereType<String>());
    }
    return c;
  }

  Map<String, dynamic> toJson() => {
    if (temperatureOverride != null) 'temperatureOverride': temperatureOverride,
    'omitTemperature': omitTemperature,
    'omitToolChoice': omitToolChoice,
    'omitReasoningEffort': omitReasoningEffort,
    'omitStreamOptions': omitStreamOptions,
    'streamUnsupported': streamUnsupported,
    'omitCacheKey': omitCacheKey,
    'omitCacheControl': omitCacheControl,
    'omitMaxTokens': omitMaxTokens,
    'omitReasoningInclude': omitReasoningInclude,
    'adjustments': adjustments.toList(),
  };

  String record(String adjustment) {
    adjustments.add(adjustment);
    return adjustment;
  }
}
