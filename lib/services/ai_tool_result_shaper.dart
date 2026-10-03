import 'dart:convert';

/// Turns a tool's raw result tree into the compact JSON the model reads.
///
/// Applied centrally by `AiToolRegistry.executeRead`, so services only build
/// plain `snake_case` maps and never worry about token cost:
///
/// - `null` values and empty strings are dropped from maps (an absent key
///   means "not reported"; the system prompt says so once);
/// - doubles are rounded by key (see [decimalsFor]) and whole values become
///   integers;
/// - timestamps are cut to `yyyy-MM-ddTHH:mm`;
/// - homogeneous lists of three or more flat maps become
///   `{"cols":[...],"rows":[[...]]}`, because repeated key names are most of
///   the payload otherwise;
/// - the whole result is capped at [maxChars] by dropping rows from the END of
///   the largest lists (tools list newest first), setting `has_more` and
///   `truncated_rows`. The result is a structure, never a cut string, so it
///   is always valid JSON.
class AiToolResultShaper {
  static const int defaultMaxChars = 6000;

  /// Per-key decimals that override [decimalsFor].
  final Map<String, int> decimals;
  final int maxChars;

  const AiToolResultShaper({
    this.decimals = const {},
    this.maxChars = defaultMaxChars,
  });

  static final RegExp _timestamp = RegExp(
    r'^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})?$',
  );

  /// Decimals kept for a double stored under [key].
  ///
  /// Key names carry the unit: `_m` meters and `_s` seconds are whole,
  /// `_s_km` (pace) is whole seconds, `_km` keeps 2 decimals, correlations
  /// keep 3 so 0.04 is not shown as 0.0, calories and kg of volume are whole,
  /// everything else keeps one decimal.
  static int decimalsFor(String key) {
    final k = key.toLowerCase();
    if (k.contains('correlation') ||
        k == 'coefficient' ||
        k == 'r' ||
        k.endsWith('_r')) {
      return 3;
    }
    if (k == 'calories' ||
        k.endsWith('_calories') ||
        k == 'kcal' ||
        k.endsWith('_kcal') ||
        k == 'volume_kg' ||
        k.endsWith('_volume_kg')) {
      return 0;
    }
    if (k.endsWith('_m') ||
        k.endsWith('_meters') ||
        k.endsWith('_s') ||
        k.endsWith('_s_km') ||
        k.endsWith('_s_mi')) {
      return 0;
    }
    if (k.endsWith('_km') || k.endsWith('_mi')) return 2;
    return 1;
  }

  /// Shapes [data] (a tool's result map).
  Map<String, dynamic> shape(Map<String, dynamic> data) {
    final cleaned = _clean(data, null);
    final root = cleaned is Map<String, dynamic>
        ? cleaned
        : <String, dynamic>{};
    _cap(root);
    return root;
  }

  /// Length of the JSON encoding of [value].
  static int encodedLength(Object? value) => jsonEncode(value).length;

  // -------------------------------------------------------------------------
  // Cleaning
  // -------------------------------------------------------------------------

  Object? _clean(Object? value, String? key) {
    if (value == null) return null;
    if (value is Map) {
      final out = <String, dynamic>{};
      value.forEach((rawKey, rawValue) {
        final k = '$rawKey';
        final cleaned = _clean(rawValue, k);
        if (cleaned == null || cleaned == '') return;
        if (cleaned is Map && cleaned.isEmpty) return;
        out[k] = cleaned;
      });
      return out;
    }
    if (value is Iterable) {
      final items = [for (final item in value) _clean(item, key)];
      return _tabulate(items) ?? items;
    }
    if (value is double) return _round(value, key);
    if (value is num || value is bool) return value;
    if (value is DateTime) return _timestampText(value.toIso8601String());
    if (value is String) return _timestampText(value);
    return '$value';
  }

  Object? _round(double value, String? key) {
    if (value.isNaN || value.isInfinite) return null;
    final places = decimals[key] ?? decimalsFor(key ?? '');
    if (places == 0) return value.round();
    var factor = 1.0;
    for (var i = 0; i < places; i++) {
      factor *= 10;
    }
    final rounded = (value * factor).round() / factor;
    return rounded == rounded.truncateToDouble() ? rounded.toInt() : rounded;
  }

  static String _timestampText(String text) {
    if (text.length >= 16 && _timestamp.hasMatch(text)) {
      return '${text.substring(0, 10)}T${text.substring(11, 16)}';
    }
    return text;
  }

  /// `{cols, rows}` for lists of three or more flat, similar maps; null when
  /// the list does not qualify.
  static Map<String, dynamic>? _tabulate(List<Object?> items) {
    if (items.length < 3) return null;
    final columns = <String>[];
    final seen = <String>{};
    for (final item in items) {
      if (item is! Map) return null;
      for (final entry in item.entries) {
        final cell = entry.value;
        if (cell is Map || cell is List) return null;
        if (seen.add('${entry.key}')) columns.add('${entry.key}');
      }
    }
    if (columns.isEmpty || columns.length > 40) return null;
    // Rows that share fewer than a quarter of the columns are not one record
    // kind (a few `null` cells cost far less than repeating every key).
    for (final item in items) {
      if ((item! as Map).length * 4 < columns.length) return null;
    }
    return {
      'cols': columns,
      'rows': [
        for (final item in items)
          [for (final column in columns) (item! as Map)[column]],
      ],
    };
  }

  // -------------------------------------------------------------------------
  // Size cap
  // -------------------------------------------------------------------------

  void _cap(Map<String, dynamic> root) {
    var length = encodedLength(root);
    if (length <= maxChars) return;
    var removedTotal = 0;
    // Reserve room for the two keys added below.
    const reserve = 40;
    while (length > maxChars - reserve) {
      final lists = <List<Object?>>[];
      _collectLists(root, lists);
      List<Object?>? target;
      var targetLength = 0;
      for (final list in lists) {
        if (list.length < 2) continue;
        final listLength = encodedLength(list);
        if (listLength > targetLength) {
          target = list;
          targetLength = listLength;
        }
      }
      if (target == null) break;
      final average = targetLength / target.length;
      final excess = length - (maxChars - reserve);
      var remove = (excess / average).ceil();
      if (remove < 1) remove = 1;
      if (remove > target.length - 1) remove = target.length - 1;
      target.removeRange(target.length - remove, target.length);
      removedTotal += remove;
      length = encodedLength(root);
    }
    if (removedTotal > 0) {
      root['has_more'] = true;
      root['truncated_rows'] =
          ((root['truncated_rows'] as int?) ?? 0) + removedTotal;
    }
  }

  static void _collectLists(Object? node, List<List<Object?>> out) {
    if (node is Map) {
      for (final value in node.values) {
        _collectLists(value, out);
      }
    } else if (node is List) {
      // Only lists of records (maps, or the rows of a table) can lose items;
      // `cols` and the cells of a row are never trimmed.
      if (node.isNotEmpty && node.every((e) => e is Map || e is List)) {
        out.add(node);
      }
      for (final value in node) {
        _collectLists(value, out);
      }
    }
  }
}
