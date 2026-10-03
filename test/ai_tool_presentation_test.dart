import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/widgets/ai/ai_tool_presentation.dart';

import 'support/ai_test_db.dart';

const _proposalAndMemoryTools = [
  'propose_routine_change',
  'propose_manual_food_creation',
  'propose_meal_log',
  'propose_body_measurement',
  'propose_goal',
  'propose_nutrition_goal',
  'propose_workout_schedule',
  'propose_run_plan_adjustment',
  'save_memory',
  'delete_memory',
];

void main() {
  late AppLocalizations en;
  late AppLocalizations pt;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    pt = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  test('every read, proposal and memory tool has its own label and icon', () async {
    await installAiTestDb();
    addTearDown(uninstallAiTestDb);
    final names = [
      ...AiToolRegistry().readToolNames,
      ..._proposalAndMemoryTools,
    ];
    final generic = en.aiToolGeneric;
    final labels = <String>{};
    final icons = <IconData>{};
    for (final name in names) {
      final label = AiToolPresentation.label(name, en);
      expect(label, isNotEmpty, reason: name);
      expect(label, isNot(generic), reason: '$name has no label of its own');
      expect(labels.add(label), isTrue, reason: 'duplicate label "$label"');
      final labelPt = AiToolPresentation.label(name, pt);
      expect(labelPt, isNotEmpty, reason: name);
      expect(labelPt, isNot(pt.aiToolGeneric), reason: name);
      final icon = AiToolPresentation.icon(name);
      expect(icon, isNot(Icons.search_rounded), reason: name);
      icons.add(icon);
    }
    expect(icons.length, greaterThan(names.length - 3));
  });

  test('an unknown tool gets the generic label and icon', () {
    expect(AiToolPresentation.label('discover_app_capabilities', en),
        en.aiToolGeneric);
    expect(AiToolPresentation.label('', pt), pt.aiToolGeneric);
    expect(AiToolPresentation.icon('whatever'), Icons.search_rounded);
  });

  group('argsSummary', () {
    String? summary(String tool, Map<String, dynamic> args,
            [AppLocalizations? l10n]) =>
        AiToolPresentation.argsSummary(tool, args, l10n ?? en);

    test('day windows, ranges and pages', () {
      expect(summary('get_sleep', {'days': 7}), 'last 7 days');
      expect(summary('get_sleep', {'days': 7}, pt), 'últimos 7 dias');
      expect(
        summary('get_workout_history', {
          'start_date': '2026-09-01',
          'end_date': '2026-09-30',
        }),
        '2026-09-01 → 09-30',
      );
      expect(
        summary('get_workout_history', {
          'start_date': '2025-12-01',
          'end_date': '2026-01-31',
        }),
        '2025-12-01 → 2026-01-31',
      );
      expect(summary('list_run_activities', {'page': 2}), 'page 2');
      expect(summary('list_run_activities', {'page': 1}), isNull);
      expect(summary('get_run_schedule', {'start_date': '2026-10-01'}),
          'from 2026-10-01');
    });

    test('periods, modes and filters', () {
      expect(summary('get_run_progress', {'period': '12_weeks'}),
          'last 12 weeks');
      expect(summary('get_run_progress', {'period': 'all'}), 'all time');
      expect(summary('get_sleep', {'detail': 'nightly', 'days': 30}),
          'last 30 days · night by night');
      expect(
        summary('get_sleep', {'detail': 'night', 'end_date': '2026-09-12'}),
        '2026-09-12',
      );
      expect(
        summary('list_exercises', {
          'sort': 'least_recent',
          'name_contains': 'bench',
        }),
        'least recently trained · "bench"',
      );
      expect(summary('get_training_summary', {'group_by': 'category'}),
          'by category');
      expect(summary('get_workout_history', {'status': 'planned'}), 'planned');
      expect(summary('get_training_plan', {'review': 'week'}), 'week review');
      expect(summary('list_goals', {'history_periods': 4}),
          '4 past periods');
      expect(summary('list_body_measurements', {'latest_per_type': true}),
          'latest values');
    });

    test('ids and empty arguments say nothing; camelCase is understood', () {
      expect(summary('get_workout_detail', {'workout_id': 'abc'}), isNull);
      expect(summary('list_routines', const {}), isNull);
      expect(summary('get_sleep', {'days': ''}), isNull);
      expect(summary('get_sleep', {'endDate': '2026-09-12', 'detail': 'night'}),
          '2026-09-12');
    });
  });
}
