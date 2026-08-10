import 'dart:convert';

/// Source of a food record.
///
/// - `manual`: created by the user directly in the app.
/// - `ai_vision`: extracted from a nutrition label photo by the AI Coach.
/// - Other values are gateway-defined (e.g. `open_food_facts`, `usda`).
///   New sources can be added without schema changes.
class FoodSource {
  static const String manual = 'manual';
  static const String aiVision = 'ai_vision';
  static const String openFoodFacts = 'open_food_facts';
}

class Food {
  final String id;
  final String source;
  final String externalId;
  final String name;
  final String searchName;
  final String? brand;
  final String? barcode;
  final String? sourceUrl;
  final DateTime fetchedAt;
  final DateTime? lastUsedAt;
  final bool? isFavorite;

  const Food({
    required this.id,
    required this.source,
    required this.externalId,
    required this.name,
    required this.searchName,
    this.brand,
    this.barcode,
    this.sourceUrl,
    required this.fetchedAt,
    this.lastUsedAt,
    this.isFavorite,
  });

  bool get isManual => source == FoodSource.manual;

  /// Foods entered by the user, either directly or from a label photo.
  bool get isUserCreated =>
      source == FoodSource.manual || source == FoodSource.aiVision;

  /// (source, externalId) pair used as the deduplication key for
  /// upserts and search-result merging.
  String get dedupKey => '$source::$externalId';

  Food copyWith({
    String? id,
    String? source,
    String? externalId,
    String? name,
    String? searchName,
    Object? brand = _sentinel,
    Object? barcode = _sentinel,
    Object? sourceUrl = _sentinel,
    DateTime? fetchedAt,
    Object? lastUsedAt = _sentinel,
    Object? isFavorite = _sentinel,
  }) {
    return Food(
      id: id ?? this.id,
      source: source ?? this.source,
      externalId: externalId ?? this.externalId,
      name: name ?? this.name,
      searchName: searchName ?? this.searchName,
      brand: identical(brand, _sentinel) ? this.brand : brand as String?,
      barcode: identical(barcode, _sentinel)
          ? this.barcode
          : barcode as String?,
      sourceUrl: identical(sourceUrl, _sentinel)
          ? this.sourceUrl
          : sourceUrl as String?,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      lastUsedAt: identical(lastUsedAt, _sentinel)
          ? this.lastUsedAt
          : lastUsedAt as DateTime?,
      isFavorite: identical(isFavorite, _sentinel)
          ? this.isFavorite
          : isFavorite as bool?,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'source': source,
    'external_id': externalId,
    'name': name,
    'search_name': searchName,
    'brand': brand,
    'barcode': barcode,
    'source_url': sourceUrl,
    'fetched_at': fetchedAt.toIso8601String(),
    'last_used_at': lastUsedAt?.toIso8601String(),
    'is_favorite': (isFavorite ?? false) ? 1 : 0,
  };

  factory Food.fromMap(Map<String, dynamic> map) {
    final isFavoriteRaw = map['is_favorite'] as int?;
    return Food(
      id: map['id'] as String,
      source: map['source'] as String,
      externalId: map['external_id'] as String,
      name: map['name'] as String,
      searchName: map['search_name'] as String,
      brand: map['brand'] as String?,
      barcode: map['barcode'] as String?,
      sourceUrl: map['source_url'] as String?,
      fetchedAt: DateTime.parse(map['fetched_at'] as String),
      lastUsedAt: (map['last_used_at'] as String?) != null
          ? DateTime.parse(map['last_used_at'] as String)
          : null,
      isFavorite: isFavoriteRaw == null ? null : isFavoriteRaw == 1,
    );
  }

  /// Normalises text for `LIKE` queries and diacritic-insensitive search.
  static String normalizeForSearch(String input) {
    if (input.isEmpty) return '';
    final lower = input.toLowerCase();
    final stripped = _stripDiacritics(lower);
    final cleaned = stripped
        .replaceAll(RegExp(r"[^a-z0-9\s]"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    return cleaned.trim();
  }

  static String _stripDiacritics(String input) {
    const map = <String, String>{
      'á': 'a',
      'à': 'a',
      'ã': 'a',
      'â': 'a',
      'ä': 'a',
      'é': 'e',
      'è': 'e',
      'ê': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'õ': 'o',
      'ô': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    final buf = StringBuffer();
    for (final ch in input.runes) {
      final c = String.fromCharCode(ch);
      buf.write(map[c] ?? c);
    }
    return buf.toString();
  }

  /// JSON encoding helper used to embed a [Food] inside a snapshot.
  String encodeJson() => jsonEncode(toMap());

  static Food decodeJson(String source) =>
      Food.fromMap(jsonDecode(source) as Map<String, dynamic>);

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Food && other.id == id);

  @override
  int get hashCode => id.hashCode;
}

const Object _sentinel = Object();
