import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/widgets/ai/ai_proposal_card.dart';

AiProposal _proposal({
  String kind = 'routine',
  AiProposalStatus status = AiProposalStatus.awaiting,
  Map<String, dynamic>? preview,
  String? errorCode,
}) => AiProposal(
  id: 'p1',
  threadId: 't',
  toolCallId: 'c',
  kind: kind,
  payload: const {},
  preview: preview ?? _routineUpdatePreview(),
  status: status,
  errorCode: errorCode,
  createdAt: DateTime(2026, 9, 30),
);

Map<String, dynamic> _ex(
  String name,
  String status, {
  Map<String, dynamic>? extra,
}) => {
  'status': status,
  'exercise_id': name,
  'name': name,
  'exercise_type': 'weightReps',
  'set_count': 3,
  'sets': const [],
  ...?extra,
};

/// "Push" renamed to "Push v2": bench becomes squat with 60 → 200 kg, a
/// cable fly is removed, a plank is added, Wednesday is dropped.
Map<String, dynamic> _routineUpdatePreview() => {
  'v': 2,
  'action': 'update',
  'routine_name': 'Push v2',
  'current_name': 'Push',
  'name_changed': true,
  'notes_changed': false,
  'days_reordered': false,
  'counts': {
    'days_added': 0,
    'days_removed': 1,
    'exercises_added': 1,
    'exercises_removed': 2,
    'exercises_swapped': 1,
    'exercises_moved': 0,
    'sets_added': 1,
    'sets_removed': 0,
    'sets_changed': 1,
  },
  'days': [
    {
      'status': 'changed',
      'name': 'Monday',
      'exercises': [
        _ex(
          'Squat',
          'changed',
          extra: {
            'old': {'name': 'Bench press', 'exercise_id': 'bench'},
            'sets': [
              {
                'status': 'changed',
                'values': {'weight': 200.0, 'reps': 10},
                'changes': {
                  'weight': {'from': 60.0, 'to': 200.0},
                },
              },
            ],
          },
        ),
        _ex('Cable fly', 'removed'),
        _ex(
          'Plank',
          'added',
          extra: {
            'set_count': 1,
            'sets': [
              {
                'status': 'added',
                'values': {'time_seconds': 60},
              },
            ],
          },
        ),
        _ex('Curl', 'unchanged'),
      ],
    },
    {
      'status': 'removed',
      'name': 'Wednesday',
      'exercises': [_ex('Row', 'removed')],
    },
  ],
  'removals': [
    {'type': 'exercise', 'name': 'Cable fly', 'day': 'Monday', 'sets': 3},
    {'type': 'day', 'name': 'Wednesday', 'exercises': 1},
    {'type': 'exercise', 'name': 'Row', 'day': 'Wednesday', 'sets': 3},
  ],
  'replacements': [
    {
      'type': 'exercise',
      'from': {'name': 'Bench press'},
      'to': {'name': 'Squat'},
    },
  ],
  'warnings': const [],
};

Widget _app(Widget child, {String locale = 'en'}) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: Locale(locale),
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

Future<void> _pump(
  WidgetTester tester,
  AiProposal proposal, {
  bool busy = false,
  Future<void> Function()? onApprove,
  Future<void> Function()? onReject,
  String locale = 'en',
}) => tester.pumpWidget(
  _app(
    AiProposalCard(
      proposal: proposal,
      busy: busy,
      onApprove: onApprove ?? () async {},
      onReject: onReject ?? () async {},
    ),
    locale: locale,
  ),
);

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('pt_BR');
  });

  group('routine diff', () {
    testWidgets('shows what changes: names, swaps, removals and values', (
      tester,
    ) async {
      await _pump(tester, _proposal());
      expect(find.text('Update routine'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.textContaining('Renamed from "Push"'), findsOneWidget);
      // The swap, the removed items by name, the added one, the changed value.
      expect(find.textContaining('Bench press → Squat'), findsOneWidget);
      expect(
        find.textContaining('Cable fly', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Wednesday', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Plank', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Weight: 60 kg → 200 kg', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('1 unchanged exercise'), findsOneWidget);
      expect(find.text('Removed'), findsOneWidget);
      expect(find.text('1 exercise replaced'), findsOneWidget);
      expect(find.text('2 exercises removed'), findsOneWidget);
    });

    testWidgets('is localized and formats numbers for pt-BR', (tester) async {
      await _pump(tester, _proposal(), locale: 'pt');
      expect(find.text('Atualizar rotina'), findsOneWidget);
      expect(find.text('Aguardando aprovação'), findsOneWidget);
      expect(find.textContaining('Carga: 60 kg → 200 kg'), findsOneWidget);
      expect(find.textContaining('Renomeada de "Push"'), findsOneWidget);
      expect(find.text('Aprovar e aplicar'), findsOneWidget);
      expect(find.text('Rejeitar'), findsOneWidget);
    });

    testWidgets('a new routine lists its days and set summaries', (
      tester,
    ) async {
      await _pump(
        tester,
        _proposal(
          preview: {
            'v': 2,
            'action': 'create',
            'routine_name': 'Pull',
            'counts': {'exercises_added': 1, 'sets_added': 3},
            'days': [
              {
                'status': 'added',
                'name': 'Day A',
                'exercises': [
                  _ex(
                    'Row',
                    'added',
                    extra: {
                      'sets': [
                        for (var i = 0; i < 3; i++)
                          {
                            'status': 'added',
                            'values': {'weight': 40.0, 'reps': 10},
                          },
                      ],
                    },
                  ),
                ],
              },
            ],
            'removals': const [],
            'replacements': const [],
            'warnings': [
              {'code': 'routine_name_exists'},
            ],
          },
        ),
      );
      expect(find.text('New routine'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('3 sets'), findsWidgets);
      expect(
        find.text('You already have a routine with this name.'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('ai-proposal-routine-details')));
      await tester.pump();
      expect(find.text('3× 40 kg × 10'), findsOneWidget);
    });
  });

  group('buttons', () {
    testWidgets('approve and reject call back once without a confirmation '
        'when nothing is removed', (tester) async {
      var approvals = 0;
      var rejections = 0;
      await _pump(
        tester,
        _proposal(
          kind: 'body_measurement',
          preview: {
            'v': 2,
            'date': '2026-09-30',
            'items': [
              {'type': 'weight', 'value': 80.0, 'unit': 'kg'},
            ],
            'warnings': const [],
          },
        ),
        onApprove: () async => approvals++,
        onReject: () async => rejections++,
      );
      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(approvals, 1);
      await tester.tap(find.byKey(const Key('ai-proposal-reject')));
      await tester.pumpAndSettle();
      expect(rejections, 1);
    });

    testWidgets('a second tap while applying is ignored and the buttons show '
        'a busy state', (tester) async {
      final gate = Completer<void>();
      var approvals = 0;
      await _pump(
        tester,
        _proposal(
          kind: 'goal',
          preview: {
            'v': 2,
            'action': 'create',
            'goal': {
              'metric': 'volume',
              'period': 'weekly',
              'target': 20000,
              'unit': 'kg',
              'scope': 'anaerobic',
              'title': '',
            },
            'warnings': const [],
          },
        ),
        onApprove: () {
          approvals++;
          return gate.future;
        },
      );
      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pump();
      expect(find.text('Applying…'), findsOneWidget);
      final approve = tester.widget<FilledButton>(
        find.byKey(const Key('ai-proposal-approve')),
      );
      final reject = tester.widget<OutlinedButton>(
        find.byKey(const Key('ai-proposal-reject')),
      );
      expect(approve.onPressed, isNull);
      expect(reject.onPressed, isNull);
      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pump();
      expect(approvals, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Applying…'), findsNothing);
    });

    testWidgets('the orchestrator busy flag disables both buttons', (
      tester,
    ) async {
      await _pump(tester, _proposal(), busy: true);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-proposal-approve')))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('ai-proposal-reject')))
            .onPressed,
        isNull,
      );
    });
  });

  group('confirmation', () {
    testWidgets('removals and replacements are listed by name and must be '
        'confirmed', (tester) async {
      var approvals = 0;
      await _pump(tester, _proposal(), onApprove: () async => approvals++);
      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pumpAndSettle();
      expect(find.text('Apply this change?'), findsOneWidget);
      expect(find.textContaining('3 items will be removed.'), findsOneWidget);
      expect(
        find.textContaining('1 exercise will be replaced by another one.'),
        findsOneWidget,
      );
      expect(find.textContaining('• Cable fly (Monday)'), findsOneWidget);
      expect(find.textContaining('• Wednesday'), findsOneWidget);
      expect(find.textContaining('• Bench press → Squat'), findsOneWidget);
      expect(approvals, 0);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(approvals, 0, reason: 'cancelling applies nothing');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('ai-proposal-approve')))
            .onPressed,
        isNotNull,
        reason: 'the card is usable again',
      );

      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Apply changes'));
      await tester.pumpAndSettle();
      expect(approvals, 1);
    });

    test('only removals and replacements need confirmation', () {
      expect(
        AiProposalCard.destructiveItems({
          'removals': const [],
          'replacements': const [],
        }),
        isEmpty,
      );
      expect(
        AiProposalCard.destructiveItems(_routineUpdatePreview()),
        hasLength(4),
      );
    });
  });

  group('statuses', () {
    testWidgets('applied and rejected cards have no buttons', (tester) async {
      await _pump(tester, _proposal(status: AiProposalStatus.applied));
      expect(find.text('Applied'), findsOneWidget);
      expect(find.text('The change was applied.'), findsOneWidget);
      expect(find.byKey(const Key('ai-proposal-approve')), findsNothing);

      await _pump(tester, _proposal(status: AiProposalStatus.rejected));
      expect(find.text('Rejected'), findsOneWidget);
      expect(find.byKey(const Key('ai-proposal-approve')), findsNothing);
      expect(find.byKey(const Key('ai-proposal-reject')), findsNothing);
    });

    testWidgets('stale and failed cards explain why from the stable code', (
      tester,
    ) async {
      await _pump(
        tester,
        _proposal(status: AiProposalStatus.stale, errorCode: 'stale_revision'),
      );
      expect(find.text('Outdated'), findsOneWidget);
      expect(
        find.text(
          'The data changed after this proposal was made. Ask the AI for a new one.',
        ),
        findsOneWidget,
      );
      await _pump(
        tester,
        _proposal(status: AiProposalStatus.stale, errorCode: 'stale_revision'),
        locale: 'pt',
      );
      expect(find.text('Desatualizada'), findsOneWidget);
      expect(
        find.text(
          'Os dados mudaram depois desta proposta. Peça uma nova à IA.',
        ),
        findsOneWidget,
      );
      await _pump(
        tester,
        _proposal(status: AiProposalStatus.failed, errorCode: 'apply_failed'),
      );
      expect(find.text('Failed'), findsOneWidget);
      expect(
        find.text('This could not be applied and nothing was changed.'),
        findsOneWidget,
      );
      await _pump(
        tester,
        _proposal(
          status: AiProposalStatus.stale,
          errorCode: 'stale_week_started',
        ),
      );
      expect(find.textContaining('A new week started'), findsOneWidget);
    });

    testWidgets('expired cards say so', (tester) async {
      await _pump(
        tester,
        _proposal(status: AiProposalStatus.expired, errorCode: 'expired'),
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(find.byKey(const Key('ai-proposal-approve')), findsNothing);
    });

    testWidgets('a proposal from another version shows a neutral note', (
      tester,
    ) async {
      await _pump(
        tester,
        _proposal(kind: 'brand_new_kind', preview: const {'v': 9}),
      );
      expect(find.text('Proposal'), findsOneWidget);
      expect(find.textContaining('another version of the app'), findsOneWidget);
      // Old previews (no version) are not rendered as if they were current.
      await _pump(
        tester,
        _proposal(
          preview: const {
            'removed': {'total': 1},
          },
        ),
      );
      expect(find.textContaining('another version of the app'), findsOneWidget);
    });
  });

  group('manual food', () {
    final preview = {
      'v': 2,
      'name': 'Banana prata',
      'brand': null,
      'reference': {'amount': 100.0, 'unit': 'g'},
      'values': {
        'calories': 98.0,
        'protein_g': 1.3,
        'carbs_g': 26.0,
        'fat_g': 0.1,
        'potassium_mg': 358.0,
      },
      'servings': [
        {
          'label': '1 unidade média',
          'quantity': 1.0,
          'unit': 'unidade',
          'grams_equivalent': 80.0,
        },
      ],
      'notes': 'Valores típicos.',
      'estimated': true,
      'warnings': const [],
    };

    testWidgets('approval opens the form and nothing is saved by the card', (
      tester,
    ) async {
      var approvals = 0;
      var rejections = 0;
      await _pump(
        tester,
        _proposal(kind: 'manual_food', preview: preview),
        onApprove: () async => approvals++,
        onReject: () async => rejections++,
        locale: 'pt',
      );
      expect(find.text('Banana prata'), findsOneWidget);
      expect(find.textContaining('98 kcal'), findsOneWidget);
      expect(find.text('Aprovar e revisar formulário'), findsOneWidget);
      expect(find.text('Descartar'), findsOneWidget);
      expect(
        find.text(
          'Aprovar abre o formulário editável. Nada é salvo até você salvar lá.',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('ai-proposal-food-details')));
      await tester.pumpAndSettle();
      expect(find.textContaining('358 mg'), findsOneWidget);
      expect(find.textContaining('1 unidade média'), findsOneWidget);

      await tester.tap(find.byKey(const Key('ai-proposal-approve')));
      await tester.pumpAndSettle();
      expect(approvals, 1);
      expect(rejections, 0);
    });
  });

  group('plan and goal bodies', () {
    testWidgets('run plan: lighter week and moved session', (tester) async {
      await _pump(
        tester,
        _proposal(
          kind: 'run_plan',
          preview: {
            'v': 2,
            'action': 'scale_week',
            'plan': '10k',
            'week': 4,
            'factor': 0.8,
            'before_m': 21800,
            'after_m': 17600,
            'reason': 'tired',
            'sessions': [
              {'name': 'Long 3', 'before_m': 12000, 'after_m': 9600},
              {'name': 'Intervals 3', 'before_m': 4800, 'after_m': 4800},
            ],
            'warnings': const [],
          },
        ),
        locale: 'pt',
      );
      expect(find.text('Semana de corrida mais leve'), findsOneWidget);
      expect(find.text('Volume planejado 21,8 km → 17,6 km'), findsOneWidget);
      expect(
        find.textContaining('Long 3: 12 km → 9,6 km', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Intervals 3'),
        findsNothing,
        reason: 'unchanged sessions are not listed',
      );
      expect(find.text('Motivo: tired'), findsOneWidget);

      await _pump(
        tester,
        _proposal(
          kind: 'run_plan',
          preview: {
            'v': 2,
            'action': 'move_session',
            'plan': '10k',
            'week': 3,
            'session': {'name': 'Intervals', 'distance_m': 4800},
            'from_day': 4,
            'to_day': 6,
            'date': '2026-10-03',
            'warnings': [
              {'code': 'run_hard_back_to_back', 'other': 'Long 3'},
              {'code': 'run_better_day', 'day_of_week': 5},
            ],
          },
        ),
      );
      expect(find.text('Move run'), findsOneWidget);
      expect(find.text('Intervals: Thursday → Saturday'), findsOneWidget);
      expect(find.text('Two hard days in a row with Long 3.'), findsOneWidget);
      expect(
        find.text('A better day for this session would be Friday.'),
        findsOneWidget,
      );
    });

    testWidgets('goal update and nutrition goal on a plan phase', (
      tester,
    ) async {
      await _pump(
        tester,
        _proposal(
          kind: 'goal',
          preview: {
            'v': 2,
            'action': 'update',
            'goal': {
              'title': 'Cardio',
              'scope': 'aerobic',
              'metric': 'distance',
              'period': 'weekly',
              'target': 35,
              'unit': 'km',
              'active': true,
            },
            'changes': {
              'target': {'from': 30, 'to': 35},
            },
            'warnings': const [],
          },
        ),
      );
      expect(find.text('Update goal'), findsOneWidget);
      expect(
        find.textContaining('Distance: 30 km → 35 km', findRichText: true),
        findsOneWidget,
      );

      await _pump(
        tester,
        _proposal(
          kind: 'nutrition_goal',
          preview: {
            'v': 2,
            'scope': 'active_phase',
            'before': {'calories': 2400, 'protein_g': 160},
            'after': {'calories': 2000, 'protein_g': 160},
            'phase': {
              'name': 'Cut',
              'from_week': 3,
              'weeks_changed': 2,
              'total_weeks': 4,
            },
            'warnings': [
              {'code': 'rest_day_unchanged'},
              {
                'code': 'macros_do_not_match_calories',
                'macro_calories': 2500,
                'calories': 2000,
              },
            ],
          },
        ),
      );
      expect(
        find.text('Plan phase "Cut" from week 3 to the end (2 weeks)'),
        findsOneWidget,
      );
      expect(find.text('2,400 kcal'), findsOneWidget);
      expect(find.text('2,000 kcal'), findsOneWidget);
      expect(find.text('Weeks already lived are not changed.'), findsOneWidget);
      expect(
        find.text(
          'The macros add up to 2500 kcal, but the calorie target is 2000 kcal.',
        ),
        findsOneWidget,
      );
    });
  });
}
