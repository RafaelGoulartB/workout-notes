import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';

import 'support/ai_proposal_fixtures.dart';
import 'support/test_db.dart';

const _tool = 'propose_goal';

void main() {
  late Database db;
  late AiProposalService service;

  setUp(() async {
    db = await installTestDb();
    service = AiProposalService();
    await AiProposalFixtures.seedThread(db);
  });

  tearDown(uninstallTestDb);

  Future<void> seedGoal({
    String id = 'g1',
    String metric = 'volume',
    String scope = 'anaerobic',
    double target = 20000,
    bool active = true,
  }) => db.insert('user_goals', {
    'id': id,
    'title': 'Volume',
    'scope': scope,
    'metric': metric,
    'period': 'weekly',
    'target_value': target,
    'created_at': AiProposalFixtures.now,
    'is_active': active ? 1 : 0,
  });

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

  group('create', () {
    Map<String, dynamic> create({
      String scope = 'aerobic',
      String metric = 'distance',
      String period = 'weekly',
      num target = 30,
    }) => {
      'action': 'create',
      'scope': scope,
      'metric': metric,
      'period': period,
      'target_value': target,
      'title': 'Run more',
    };

    test('stores the target in the unit the goal screens use', () async {
      final id = await prepareProposal(service, _tool, create());
      expect(await db.query('user_goals'), isEmpty);
      final applied = await service.approve(id);
      expect(applied.status, AiProposalStatus.applied);
      await service.approve(id);
      final goal = (await db.query('user_goals')).single;
      expect(goal['id'], id);
      expect(goal['target_value'], 30);
      expect(goal['metric'], 'distance');
      expect(goal['is_active'], 1);
    });

    test('a time goal is given in minutes and stored in seconds', () async {
      final id = await prepareProposal(
        service,
        _tool,
        create(metric: 'time', target: 150),
      );
      final preview = (await service.get(id))!.preview;
      expect(dig(preview, 'goal.target'), 150);
      expect(dig(preview, 'goal.unit'), 'min');
      await service.approve(id);
      expect((await db.query('user_goals')).single['target_value'], 9000);
    });

    test('rejects a metric that does not fit the scope', () async {
      final error = await refused(
        create(scope: 'anaerobic', metric: 'distance'),
      );
      expect(error['code'], 'invalid_args');
      expect((error['data'] as Map)['expected'], contains('volume'));
    });

    test('rejects out-of-range and fractional targets', () async {
      for (final args in [
        create(target: 0),
        create(target: -5),
        create(metric: 'days', target: 9),
        create(metric: 'days', period: 'monthly', target: 40),
        create(metric: 'days', target: 3.5),
        create(metric: 'distance', target: 99999),
      ]) {
        expect((await refused(args))['code'], 'invalid_args', reason: '$args');
      }
    });

    test('a goal id is not allowed and a duplicate is a warning', () async {
      expect(
        ((await refused({...create(), 'goal_id': 'g'}))['data']
            as Map)['param'],
        'goal_id',
      );
      await seedGoal(metric: 'distance', scope: 'aerobic', target: 20);
      final id = await prepareProposal(service, _tool, create());
      final warnings = (await service.get(id))!.preview['warnings'] as List;
      expect(codes(warnings), contains('similar_goal_exists'));
    });
  });

  group('update, activate, deactivate', () {
    test('update changes only the target and shows before to after', () async {
      await seedGoal();
      final id = await prepareProposal(service, _tool, {
        'action': 'update',
        'goal_id': 'g1',
        'target_value': 25000,
      });
      final preview = (await service.get(id))!.preview;
      expect(dig(preview, 'changes.target'), {'from': 20000.0, 'to': 25000.0});
      await service.approve(id);
      final goal = (await db.query('user_goals')).single;
      expect(goal['target_value'], 25000);
      expect(goal['title'], 'Volume');
      expect(goal['metric'], 'volume');
    });

    test(
      'scope and metric cannot change; no-op and unknown ids refused',
      () async {
        await seedGoal();
        expect(
          (await refused({
            'action': 'update',
            'goal_id': 'g1',
            'metric': 'days',
          }))['code'],
          'invalid_args',
        );
        expect(
          (await refused({
            'action': 'update',
            'goal_id': 'g1',
            'target_value': 20000,
          }))['code'],
          'no_changes',
        );
        expect(
          (await refused({
            'action': 'update',
            'goal_id': 'zz',
            'target_value': 1,
          }))['code'],
          'not_found',
        );
        expect(
          ((await refused({'action': 'update', 'target_value': 1}))['data']
              as Map)['param'],
          'goal_id',
        );
      },
    );

    test('changing a days goal to monthly keeps the target valid', () async {
      await seedGoal(metric: 'days', target: 5);
      final id = await prepareProposal(service, _tool, {
        'action': 'update',
        'goal_id': 'g1',
        'period': 'monthly',
      });
      await service.approve(id);
      expect((await db.query('user_goals')).single['period'], 'monthly');
    });

    test('pause and resume', () async {
      await seedGoal();
      expect(
        (await refused({'action': 'activate', 'goal_id': 'g1'}))['code'],
        'no_changes',
      );
      final id = await prepareProposal(service, _tool, {
        'action': 'deactivate',
        'goal_id': 'g1',
      });
      await service.approve(id);
      expect((await db.query('user_goals')).single['is_active'], 0);
    });

    test(
      'a goal edited by the user after the proposal makes it stale',
      () async {
        await seedGoal();
        final id = await prepareProposal(service, _tool, {
          'action': 'update',
          'goal_id': 'g1',
          'target_value': 25000,
        });
        await db.update('user_goals', {'target_value': 22000});
        final result = await service.approve(id);
        expect(result.status, AiProposalStatus.stale);
        expect(result.errorCode, 'stale_revision');
        expect((await db.query('user_goals')).single['target_value'], 22000);
      },
    );

    test('a deleted goal makes the proposal stale', () async {
      await seedGoal();
      final id = await prepareProposal(service, _tool, {
        'action': 'deactivate',
        'goal_id': 'g1',
      });
      await db.delete('user_goals');
      final result = await service.approve(id);
      expect(result.status, AiProposalStatus.stale);
      expect(result.errorCode, 'stale_target_missing');
    });
  });

  group('placeholders models write into optional fields', () {
    test('pause/resume ignores fields that do not apply', () async {
      await seedGoal(active: false);
      final id = await prepareProposal(service, _tool, {
        'action': 'activate',
        'goal_id': 'g1',
        'scope': 'aerobic',
        'metric': 'time',
        'period': 'monthly',
        'target_value': 0,
        'title': '',
      });
      await service.approve(id);
      final goal = (await db.query('user_goals')).single;
      expect(goal['is_active'], 1);
      expect(goal['scope'], 'anaerobic');
      expect(goal['metric'], 'volume');
    });

    test('update accepts the unchanged scope/metric and a 0 target', () async {
      await seedGoal();
      final id = await prepareProposal(service, _tool, {
        'action': 'update',
        'goal_id': 'g1',
        'scope': 'anaerobic',
        'metric': 'volume',
        'target_value': 0,
        'title': 'Heavier',
      });
      await service.approve(id);
      final goal = (await db.query('user_goals')).single;
      expect(goal['title'], 'Heavier');
      expect(goal['target_value'], 20000);
    });

    test('a different metric on update is still refused', () async {
      await seedGoal();
      final error = await refused({
        'action': 'update',
        'goal_id': 'g1',
        'metric': 'days',
        'target_value': 4,
      });
      expect(error['code'], 'invalid_args');
    });
  });
}
