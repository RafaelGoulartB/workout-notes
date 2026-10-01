import 'dart:convert';

/// Lenient readers for JSON produced by a language model.
abstract final class AiJson {
  /// Decodes the JSON object in [raw]: tolerates a markdown fence and prose
  /// around the braces. Throws [FormatException] when there is no object.
  static Map<String, dynamic> parseObject(String raw) {
    var cleaned = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
    if (fence != null) cleaned = fence.group(1)!.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) cleaned = cleaned.substring(start, end + 1);
    final Object? decoded;
    try {
      decoded = jsonDecode(cleaned);
    } on FormatException {
      throw const FormatException('response is not valid JSON');
    }
    if (decoded is Map) return decoded.cast<String, dynamic>();
    throw const FormatException('response is not a JSON object');
  }

  /// The object in [value]: a map, or a string holding one. Null otherwise.
  static Map<String, dynamic>? objectOrNull(Object? value) {
    if (value is Map) return value.cast<String, dynamic>();
    if (value is String && value.trim().isNotEmpty) {
      try {
        return parseObject(value);
      } on FormatException {
        return null;
      }
    }
    return null;
  }

  /// Texts models write for "no value".
  static const _absent = {'null', 'none', 'n/a', 'na', 'nil', 'undefined', '-'};

  /// A trimmed non-empty string, or null for blank text and the strings
  /// `"null"`, `"none"`, `"n/a"`… a model writes instead of a real null.
  static String? text(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty || _absent.contains(trimmed.toLowerCase())) return null;
    return trimmed;
  }

  /// A finite, non-negative number from a number or from text with a leading
  /// number: `12`, `"12,5"`, `"12 g"`, `"<1"`, `"~30 kcal"`. Anything else
  /// (including negative values and absent-value strings) is null.
  static double? number(Object? value) {
    double? parsed;
    if (value is num) {
      parsed = value.toDouble();
    } else if (value is String) {
      final cleaned = text(value);
      if (cleaned == null) return null;
      final match = RegExp(
        r'^[<>~≈≤≥]?\s*(\d+(?:[.,]\d+)?|[.,]\d+)',
      ).firstMatch(cleaned);
      if (match == null) return null;
      parsed = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    }
    if (parsed == null || parsed.isNaN || parsed.isInfinite || parsed < 0) {
      return null;
    }
    return parsed;
  }

  /// Like [number] but a zero counts as absent.
  static double? positive(Object? value) {
    final parsed = number(value);
    return parsed == null || parsed <= 0 ? null : parsed;
  }
}
