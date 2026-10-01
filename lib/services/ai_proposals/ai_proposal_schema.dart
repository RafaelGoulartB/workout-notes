/// Compact JSON-schema builders for the proposal tools. The schemas are sent
/// on every request, so they only carry what steers the model (types, enums,
/// ranges and kind-specific hints); the handlers validate everything.
abstract final class AiSchema {
  static Map<String, dynamic> str([String? description]) => {
    'type': 'string',
    'description': ?description,
  };

  static Map<String, dynamic> date(String description) =>
      str('$description (YYYY-MM-DD).');

  static Map<String, dynamic> number([
    String? description,
    num? min,
    num? max,
  ]) => {
    'type': 'number',
    'description': ?description,
    'minimum': ?min,
    'maximum': ?max,
  };

  static Map<String, dynamic> integer([
    String? description,
    int? min,
    int? max,
  ]) => {
    'type': 'integer',
    'description': ?description,
    'minimum': ?min,
    'maximum': ?max,
  };

  static Map<String, dynamic> boolean([String? description]) => {
    'type': 'boolean',
    'description': ?description,
  };

  static Map<String, dynamic> enumOf(
    List<String> values, [
    String? description,
  ]) => {'type': 'string', 'enum': values, 'description': ?description};

  static Map<String, dynamic> list(
    Map<String, dynamic> items, {
    String? description,
    int? min,
    int? max,
  }) => {
    'type': 'array',
    'description': ?description,
    'maxItems': ?max,
    'items': items,
  };

  static Map<String, dynamic> object(
    Map<String, dynamic> properties, {
    List<String> required = const [],
    String? description,
  }) => {
    'type': 'object',
    'description': ?description,
    'properties': properties,
    if (required.isNotEmpty) 'required': required,
  };
}
