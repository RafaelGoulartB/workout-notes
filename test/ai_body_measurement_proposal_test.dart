import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_body_measurement';

void main() {
  late Database db;
  late AiProposalService service;

  setUp(() async {
    db = await installTestDb();
    service = AiProposalService(now: () => DateTime(2026, 9, 30, 9));
    await AiProposalFixtures.seedThread(db);
  });

  tearDown(uninstallTestDb);

  Future<Map<String, dynamic>> refused(Map<String, dynamic> args) async {
    final result = await service.prepare(
      threadId: AiProposalFixtures.threadId,
      toolCallId: 'c',
      toolName: _tool,
      args: args,
    );
    expect(result.ok, isFalse, reason: '${result.toMap()}');
    return result.toMap();
  }

  Map<String, dynamic> weight(num value, {String? date}) => {
    'date': ?date,
    'measurements': [
      {'type': 'weight', 'value': value},
    ],
  };

  group('validation', () {
    test('rejects implausible values with the unit in the hint', () async {
      for (final value in [8, 800, -3]) {
        final error = await refused(weight(value));
        expect(error['code'], 'invalid_args', reason: '$value');
        expect((error['data'] as Map)['expected'], contains('between'));
      }
    });

    test('rejects a future date and a malformed date', () async {
      expect(
        (await refused(weight(80, date: '2026-10-01')))['code'],
        'invalid_args',
      );
      expect(
        (await refused(weight(80, date: '2026-02-30')))['code'],
        'invalid_args',
      );
    });

    test('blood pressure needs both numbers in the right order', () async {
      var error = await refused({
        'measurements': [
          {'type': 'bloodPressure', 'value': 120},
        ],
      });
      expect(
        (error['data'] as Map)['param'],
        'measurements[0].secondary_value',
      );
      error = await refused({
        'measurements': [
          {'type': 'bloodPressure', 'value': 80, 'secondary_value': 120},
        ],
      });
      expect(error['message'], contains('Systolic'));
    });

    test(
      'placeholder fields that do not apply to the type are ignored '
      '(seen with real models: weight with secondary_value 0, side left)',
      () async {
        final result = await service.prepare(
          threadId: AiProposalFixtures.threadId,
          toolCallId: 'c-placeholders',
          toolName: _tool,
          args: {
            'is_fasted': true,
            'measurements': [
              {
                'type': 'weight',
                'value': 80.5,
                'secondary_value': 0,
                'side': 'left',
              },
              {'type': 'waist', 'value': 82, 'side': 'right'},
            ],
          },
        );
        expect(result.ok, isTrue, reason: '${result.toMap()}');
        final proposal = await service.get(
          (result.data as Map)['proposal_id'] as String,
        );
        final items = (proposal!.payload['measurements'] as List).cast<Map>();
        expect(items.first['secondary_value'], isNull);
        expect(items.first['side'], isNull);
        expect(items.last['side'], isNull);
      },
    );

    test('duplicates and unknown keys are refused', () async {
      var error = await refused({
        'measurements': [
          {'type': 'arm', 'value': 35, 'side': 'left'},
          {'type': 'arm', 'value': 36, 'side': 'left'},
        ],
      });
      expect(error['code'], 'invalid_args');
      error = await refused({
        'measurements': [
          {'type': 'weight', 'value': 80, 'unit': 'kg'},
        ],
      });
      expect(error['message'], contains('unit'));
      error = await refused({'measurements': []});
      expect(error['code'], 'invalid_args');
      error = await refused({
        'measurements': [
          {'type': 'height', 'value': 180},
        ],
      });
      expect((error['data'] as Map)['expected'], contains('weight'));
    });
  });

  group('preview and approval', () {
    test('shows the previous value and warns on a large jump', () async {
      await db.insert('body_measurements', {
        'id': 'old',
        'type': 'weight',
        'value': 80.0,
        'unit': 'kg',
        'date': '2026-09-20',
        'created_at': '2026-09-20T08:00:00',
      });
      final id = await prepareProposal(service, _tool, weight(95));
      final preview = (await service.get(id))!.preview;
      final item = (preview['items'] as List).single as Map;
      expect(dig(item, 'previous.value'), 80.0);
      expect(item['unit'], 'kg');
      expect(codes(preview['warnings']), contains('large_change'));
    });

    test('warns when the type is already logged that day', () async {
      await db.insert('body_measurements', {
        'id': 'today',
        'type': 'weight',
        'value': 80.0,
        'unit': 'kg',
        'date': '2026-09-30',
        'created_at': '2026-09-30T07:00:00',
      });
      final id = await prepareProposal(service, _tool, weight(80.4));
      final warnings = (await service.get(id))!.preview['warnings'] as List;
      expect(codes(warnings), contains('already_logged'));
    });

    test('approval writes every measurement once with the type unit', () async {
      final id = await prepareProposal(service, _tool, {
        'date': '2026-09-29',
        'time_of_day': 'morning',
        'is_fasted': true,
        'comment': 'after waking',
        'measurements': [
          {'type': 'weight', 'value': 81.2},
          {'type': 'bodyFat', 'value': 18.5},
          {'type': 'arm', 'value': 35.5, 'side': 'right'},
          {'type': 'bloodPressure', 'value': 118, 'secondary_value': 76},
        ],
      });
      expect(await db.query('body_measurements'), isEmpty);
      final applied = await service.approve(id);
      expect(applied.status, AiProposalStatus.applied);
      await service.approve(id);
      final rows = await db.query('body_measurements', orderBy: 'type');
      expect(rows, hasLength(4));
      final byType = {for (final r in rows) r['type'] as String: r};
      expect(byType['weight']!['unit'], 'kg');
      expect(byType['bodyFat']!['unit'], '%');
      expect(byType['arm']!['unit'], 'cm');
      expect(byType['arm']!['side'], 'right');
      expect(byType['bloodPressure']!['secondary_value'], 76);
      expect(byType['weight']!['date'], '2026-09-29');
      expect(byType['weight']!['time_of_day'], 'morning');
      expect(byType['weight']!['is_fasted'], 1);
      expect(byType['weight']!['comment'], 'after waking');
      expect(service.outcomeFacts(applied)['result'], {
        'saved': 4,
        'date': '2026-09-29',
      });
    });

    test('rejecting writes nothing', () async {
      final id = await prepareProposal(service, _tool, weight(80));
      await service.reject(id);
      await service.approve(id);
      expect(await db.query('body_measurements'), isEmpty);
    });

    test('defaults to today', () async {
      final id = await prepareProposal(service, _tool, weight(80));
      await service.approve(id);
      expect(
        (await db.query('body_measurements')).single['date'],
        '2026-09-30',
      );
    });
  });

  test('blank date and time of day are treated as not given', () async {
    final id = await prepareProposal(service, _tool, {
      'date': '',
      'time_of_day': '',
      'comment': '',
      'measurements': [
        {'type': 'weight', 'value': 80, 'side': '', 'secondary_value': 0},
      ],
    });
    await service.approve(id);
    final row = (await db.query('body_measurements')).single;
    expect(row['date'], '2026-09-30');
    expect(row['time_of_day'], isNull);
    expect(row['side'], isNull);
  });
}
