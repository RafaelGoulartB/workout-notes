import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

void main() {
  AiToolArgs args(Map<String, dynamic> raw) => AiToolArgs(raw);

  group('string', () {
    test('trims, treats blank as absent and reads camelCase', () {
      expect(args({'name': '  x '}).string('name'), 'x');
      expect(args({'name': '   '}).string('name'), isNull);
      expect(args({'name_contains': ''}).string('name_contains'), isNull);
      expect(args({'nameContains': 'a'}).string('name_contains'), 'a');
      expect(args({'search': 'q'}).string('query', alt: 'search'), 'q');
    });

    test('numbers become ids, objects fail', () {
      expect(args({'id': 7}).string('id'), '7');
      expect(
        () => args({'id': {'a': 1}}).string('id'),
        throwsA(isA<AiToolArgException>()),
      );
    });

    test('requiredString fails with invalid_args when missing', () {
      expect(
        () => args({'a': ' '}).requiredString('a'),
        throwsA(
          isA<AiToolArgException>().having(
            (e) => e.toResult().code,
            'code',
            'invalid_args',
          ),
        ),
      );
    });
  });

  group('date', () {
    test('accepts YYYY-MM-DD and cuts a timestamp to its date', () {
      expect(args({'d': '2026-09-01'}).date('d'), '2026-09-01');
      expect(args({'d': '2026-09-01T10:30:00'}).date('d'), '2026-09-01');
      expect(args({'d': ''}).date('d'), isNull);
      expect(args({}).date('d'), isNull);
    });

    test('reports param, expected and received for anything else', () {
      for (final bad in ['01/09/2026', '2026-13-01', '2026-02-30', 'abc']) {
        try {
          args({'start_date': bad}).date('start_date');
          fail('$bad should be rejected');
        } on AiToolArgException catch (e) {
          final result = e.toResult();
          expect(result.ok, isFalse);
          expect(result.code, 'invalid_args');
          expect(
            result.message,
            'start_date: expected YYYY-MM-DD, got "$bad"',
          );
          expect(result.details, {
            'param': 'start_date',
            'expected': 'YYYY-MM-DD',
            'received': bad,
          });
        }
      }
    });
  });

  group('integer', () {
    test('uses the fallback, parses strings and rounds numbers', () {
      expect(args({}).integer('n', fallback: 5), 5);
      expect(args({'n': '12'}).integer('n', fallback: 5), 12);
      expect(args({'n': 7.6}).integer('n', fallback: 5), 8);
      expect(args({}).integerOrNull('n'), isNull);
    });

    test('clamps out-of-range values and records the adjustment', () {
      final a = args({'limit': 500, 'days': 0});
      expect(a.integer('limit', fallback: 10, min: 1, max: 30), 30);
      expect(a.integer('days', fallback: 10, min: 1, max: 90), 1);
      expect(a.adjusted, {
        'limit': {'requested': 500, 'used': 30},
        'days': {'requested': 0, 'used': 1},
      });
    });

    test('rejects non numeric input without leaking a Dart error', () {
      expect(
        () => args({'n': 'many'}).integer('n', fallback: 1),
        throwsA(isA<AiToolArgException>()),
      );
      expect(
        () => args({'n': true}).integer('n', fallback: 1),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });

  group('boolean and enum', () {
    test('boolean accepts true, false and their strings', () {
      expect(args({'f': true}).boolean('f'), isTrue);
      expect(args({'f': 'false'}).boolean('f'), isFalse);
      expect(args({'f': 'TRUE'}).boolean('f'), isTrue);
      expect(args({}).boolean('f'), isNull);
      expect(args({'f': ''}).flag('f', fallback: true), isTrue);
      expect(
        () => args({'f': 'yes'}).boolean('f'),
        throwsA(isA<AiToolArgException>()),
      );
    });

    test('enumValue is case-insensitive and lists the allowed values', () {
      const allowed = ['week', 'category'];
      expect(args({'g': 'Week'}).enumValue('g', allowed), 'week');
      expect(args({}).enumValue('g', allowed, fallback: 'week'), 'week');
      expect(args({'g': ''}).enumValue('g', allowed), isNull);
      try {
        args({'g': 'month'}).enumValue('g', allowed);
        fail('month should be rejected');
      } on AiToolArgException catch (e) {
        final result = e.toResult();
        expect(result.code, 'invalid_args');
        expect(result.details?['expected'], 'one of week, category');
        expect(result.details?['received'], 'month');
      }
    });
  });

  group('AiToolMath.window', () {
    final today = DateTime(2026, 9, 30, 15);

    test('defaults to the last N days ending today', () {
      final window = AiToolMath.window(
        today: today,
        defaultDays: 14,
        maxDays: 90,
      );
      expect(window.startKey, '2026-09-17');
      expect(window.endKey, '2026-09-30');
      expect(window.days, 14);
      expect(window.toApplied(), {
        'start_date': '2026-09-17',
        'end_date': '2026-09-30',
        'days': 14,
      });
    });

    test('days end at end_date and are capped at the maximum', () {
      final window = AiToolMath.window(
        today: today,
        days: 500,
        endDate: '2026-03-31',
        defaultDays: 14,
        maxDays: 90,
      );
      expect(window.endKey, '2026-03-31');
      expect(window.days, 90);
      final custom = AiToolMath.window(
        today: today,
        startDate: '2025-01-01',
        endDate: '2026-03-31',
        defaultDays: 14,
        maxDays: 90,
      );
      expect(custom.capped, isTrue);
      expect(custom.endKey, '2026-03-31');
      expect(custom.days, 90);
      expect(custom.toApplied()['capped'], isTrue);
    });

    test('a window over a daylight saving change keeps exact day counts', () {
      // 2026-03-08 is the US spring-forward day; the count must stay 10.
      final window = AiToolMath.window(
        today: DateTime(2026, 3, 10),
        days: 10,
        defaultDays: 10,
        maxDays: 90,
      );
      expect(window.startKey, '2026-03-01');
      expect(window.days, 10);
    });

    test('start_date alone runs until today; a reversed range is invalid', () {
      final window = AiToolMath.window(
        today: today,
        startDate: '2026-09-20',
        defaultDays: 14,
        maxDays: 90,
      );
      expect(window.endKey, '2026-09-30');
      expect(
        () => AiToolMath.window(
          today: today,
          startDate: '2026-09-20',
          endDate: '2026-09-10',
          defaultDays: 14,
          maxDays: 90,
        ),
        throwsA(isA<AiToolArgException>()),
      );
    });
  });
}
