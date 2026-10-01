import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/ai_tool_result_shaper.dart';

void main() {
  const shaper = AiToolResultShaper();

  Map<String, dynamic> shape(Map<String, dynamic> data) => shaper.shape(data);

  test('drops nulls, empty strings and empty maps but keeps zero and false', () {
    final shaped = shape({
      'a': null,
      'b': '',
      'c': 0,
      'd': false,
      'e': <String, dynamic>{},
      'f': {'x': null},
      'list': [1, null, 3],
      'empty_list': <Object?>[],
    });
    expect(shaped, {
      'c': 0,
      'd': false,
      'list': [1, null, 3],
      'empty_list': <Object?>[],
    });
  });

  test('rounds doubles by key name and turns whole values into ints', () {
    final shaped = shape({
      'distance_m': 5012.6,
      'pace_s_km': 325.4,
      'distance_km': 12.3456,
      'weight_kg': 82.46,
      'calories': 2301.7,
      'volume_kg': 10005.4,
      'coefficient': 0.04321,
      'sleep_efficiency_correlation': -0.5551,
      'progress_pct': 22.2222,
      'whole': 60.0,
      'nan': double.nan,
    });
    expect(shaped['distance_m'], 5013);
    expect(shaped['pace_s_km'], 325);
    expect(shaped['distance_km'], 12.35);
    expect(shaped['weight_kg'], 82.5);
    expect(shaped['calories'], 2302);
    expect(shaped['volume_kg'], 10005);
    expect(shaped['coefficient'], 0.043);
    expect(shaped['sleep_efficiency_correlation'], -0.555);
    expect(shaped['progress_pct'], 22.2);
    expect(shaped['whole'], 60);
    expect(shaped['whole'], isA<int>());
    expect(shaped.containsKey('nan'), isFalse);
  });

  test('a spec can override the decimals of a key', () {
    final shaped = const AiToolResultShaper(
      decimals: {'weight_kg': 2},
    ).shape({'weight_kg': 82.456});
    expect(shaped['weight_kg'], 82.46);
  });

  test('timestamps are cut to minutes, plain dates are left alone', () {
    final shaped = shape({
      'started_at': '2026-09-01T07:10:33.000',
      'ended_at': '2026-09-01T08:00:00Z',
      'date': '2026-09-01',
      'text': 'hello 2026-09-01T07:10:33',
    });
    expect(shaped['started_at'], '2026-09-01T07:10');
    expect(shaped['ended_at'], '2026-09-01T08:00');
    expect(shaped['date'], '2026-09-01');
    expect(shaped['text'], 'hello 2026-09-01T07:10:33');
  });

  test('homogeneous lists of three or more flat maps become cols and rows', () {
    final shaped = shape({
      'rows': [
        {'id': 'a', 'n': 1, 'x': null},
        {'id': 'b', 'n': 2.0},
        {'id': 'c', 'n': 3, 'extra': true},
      ],
    });
    expect(shaped['rows'], {
      'cols': ['id', 'n', 'extra'],
      'rows': [
        ['a', 1, null],
        ['b', 2, null],
        ['c', 3, true],
      ],
    });
  });

  test('short lists, nested values and dissimilar maps stay lists of maps', () {
    final shaped = shape({
      'two': [
        {'a': 1},
        {'a': 2},
      ],
      'nested': [
        {
          'a': 1,
          'inner': {'b': 1},
        },
        {'a': 2},
        {'a': 3},
      ],
      'mixed': [
        {'a': 1, 'b': 2, 'c': 3, 'd': 4},
        {'z': 1},
        {'a': 1, 'b': 2, 'c': 3, 'd': 4},
      ],
    });
    expect((shaped['two'] as List).first, isA<Map>());
    expect(shaped['nested'], isA<List>());
    expect(shaped['mixed'], isA<List>());
  });

  test('tables nested in tables are shaped from the inside out', () {
    final shaped = shape({
      'exercises': [
        for (var i = 0; i < 3; i++)
          {
            'name': 'e$i',
            'sets': [
              for (var j = 0; j < 3; j++) {'w': 50 + j, 'r': 10},
            ],
          },
      ],
    });
    final exercises = shaped['exercises'] as List;
    expect(exercises, hasLength(3));
    expect((exercises.first as Map)['sets'], containsPair('cols', ['w', 'r']));
  });

  test('an oversized result is trimmed from the end into valid JSON', () {
    final shaped = shape({
      'total': 200,
      'rows': [
        for (var i = 0; i < 200; i++)
          {'id': 'row-$i', 'text': 'x' * 40, 'value': i},
      ],
    });
    final encoded = jsonEncode(shaped);
    expect(encoded.length, lessThanOrEqualTo(6000));
    expect(jsonDecode(encoded), isA<Map>());
    expect(shaped['has_more'], isTrue);
    final table = shaped['rows'] as Map;
    final rows = table['rows'] as List;
    expect(shaped['truncated_rows'], 200 - rows.length);
    // The kept rows are the head of the list (newest first), untouched.
    expect((rows.first as List).first, 'row-0');
    expect(table['cols'], ['id', 'text', 'value']);
    for (final row in rows) {
      expect((row as List), hasLength(3));
    }
  });

  test('the largest list is trimmed and the small ones survive', () {
    final shaped = shape({
      'small': [
        for (var i = 0; i < 3; i++) {'a': i},
      ],
      'big': [
        for (var i = 0; i < 300; i++) {'b': 'y' * 30, 'i': i},
      ],
    });
    expect(jsonEncode(shaped).length, lessThanOrEqualTo(6000));
    expect(((shaped['small'] as Map)['rows'] as List), hasLength(3));
    expect(shaped['truncated_rows'], greaterThan(0));
  });

  test('a result under the cap is not marked', () {
    final shaped = shape({
      'rows': [
        for (var i = 0; i < 5; i++) {'a': i},
      ],
    });
    expect(shaped.containsKey('has_more'), isFalse);
    expect(shaped.containsKey('truncated_rows'), isFalse);
  });
}
