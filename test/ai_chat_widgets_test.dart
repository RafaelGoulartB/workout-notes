import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_error_details.dart';
import 'package:workout_notes/models/ai_chat_state.dart';
import 'package:workout_notes/utils/ai_error_localizer.dart';
import 'package:workout_notes/widgets/ai/ai_chat_timeline.dart';
import 'package:workout_notes/widgets/ai/ai_consent_dialog.dart';
import 'package:workout_notes/widgets/ai/ai_error_banner.dart';
import 'package:workout_notes/widgets/ai/ai_live_turn.dart';
import 'package:workout_notes/widgets/ai/ai_status_lines.dart';
import 'package:workout_notes/widgets/ai/ai_tool_steps.dart';

import 'support/ai_ui_support.dart';

AiToolStep _step(
  String id,
  String name, {
  Map<String, dynamic>? args,
  Map<String, dynamic>? result,
}) {
  final call = aiCall(id, name, args);
  return AiToolStep(
    call: call,
    result: result == null ? null : aiToolMessage('t-$id', call, result),
  );
}

AiTurnProgress _turn({
  AiTurnPhase phase = AiTurnPhase.waiting,
  String draft = '',
  List<String> tools = const [],
  bool cancelling = false,
  DateTime? startedAt,
}) => AiTurnProgress(
  threadId: 't1',
  userMessageId: 'u1',
  phase: phase,
  startedAt: startedAt ?? DateTime.now(),
  toolNames: tools,
  draftText: draft,
  cancelling: cancelling,
);

void main() {
  group('tool steps row', () {
    testWidgets('summarizes the consulted tools and expands to the steps', (
      tester,
    ) async {
      final steps = [
        _step(
          'c1',
          'get_sleep',
          args: {'days': 7},
          result: {'ok': true, 'data': {}},
        ),
        _step('c2', 'get_nutrition', result: {'ok': true}),
        _step('c3', 'list_goals', result: {'ok': true}),
        _step(
          'c4',
          'get_workout_history',
          result: {'ok': false, 'code': 'not_found'},
        ),
      ];
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(aiTestApp(AiToolStepsRow(steps: steps)));

      expect(find.text('Consulted: Sleep, Nutrition (+2)'), findsOneWidget);
      // The argument summary shows as a chip.
      expect(find.text('last 7 days'), findsOneWidget);
      // One of the steps failed: a subtle warning is on the collapsed row.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      expect(find.text('Goals'), findsNothing);
      expect(
        tester.getSemantics(find.byType(InkWell).first),
        matchesSemantics(
          label: 'Consulted: Sleep, Nutrition (+2)',
          isButton: true,
          hasTapAction: true,
          hasExpandedState: true,
          isExpanded: false,
        ),
      );

      await tester.tap(find.text('Consulted: Sleep, Nutrition (+2)'));
      await tester.pump();
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('Workout history'), findsOneWidget);
      expect(find.text('That data was not found.'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline_rounded), findsNWidgets(3));
      expect(find.textContaining('"ok"'), findsNothing);
      semantics.dispose();
    });

    testWidgets('a call without a result shows as not finished', (
      tester,
    ) async {
      await tester.pumpWidget(
        aiTestApp(AiToolStepsRow(steps: [_step('c1', 'get_sleep')])),
      );
      await tester.tap(find.text('Consulted: Sleep'));
      await tester.pump();
      expect(find.text('No result'), findsOneWidget);
      expect(find.byIcon(Icons.pending_outlined), findsOneWidget);
    });

    testWidgets('raw JSON only exists in developer mode and is built lazily', (
      tester,
    ) async {
      final big = {
        'ok': true,
        'data': {'rows': List.generate(2000, (i) => 'row number $i')},
      };
      final step = _step('c1', 'get_sleep', args: {'days': 7}, result: big);

      await tester.pumpWidget(aiTestApp(AiToolStepsRow(steps: [step])));
      await tester.tap(find.text('Consulted: Sleep'));
      await tester.pump();
      expect(find.text('Raw data'), findsNothing);

      await tester.pumpWidget(
        aiTestApp(AiToolStepsRow(steps: [step], developerMode: true)),
      );
      await tester.pump();
      // Collapsed by default: nothing was decoded or pretty-printed yet.
      expect(find.text('Raw data'), findsOneWidget);
      expect(find.textContaining('row number'), findsNothing);

      await tester.tap(find.text('Raw data'));
      await tester.pump();
      final shown = tester
          .widget<SelectableText>(find.byType(SelectableText))
          .data!;
      expect(shown.length, kAiRawPreviewChars);
      expect(shown, contains('"arguments"'));
      expect(find.textContaining('Showing the first 8 KB'), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy raw data'));
      await tester.pump();
      // "Copy" gets everything, not just the preview.
      expect(copied!.length, greaterThan(kAiRawPreviewChars));
      expect(copied, contains('row number 1999'));
    });
  });

  group('status lines', () {
    AiToolStep memory(Map<String, dynamic> result) =>
        _step('m1', 'save_memory', result: result);

    testWidgets('memory saved shows its text and an undo action', (
      tester,
    ) async {
      var undone = 0;
      await tester.pumpWidget(
        aiTestApp(
          AiMemoryLine(
            step: memory({
              'ok': true,
              'data': {'status': 'saved', 'content': 'Knee injury'},
            }),
            onUndo: () => undone++,
          ),
        ),
      );
      expect(find.text('Memory saved: Knee injury'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      expect(undone, 1);
    });

    testWidgets('updated, removed and already-saved variants', (tester) async {
      Future<void> show(Map<String, dynamic> data) => tester.pumpWidget(
        aiTestApp(
          AiMemoryLine(step: memory({'ok': true, 'data': data}), onUndo: () {}),
        ),
      );
      await show({'status': 'updated', 'content': 'Trains at home'});
      expect(find.text('Memory updated: Trains at home'), findsOneWidget);
      await show({'status': 'deleted', 'content': 'Old note'});
      expect(find.text('Memory removed: Old note'), findsOneWidget);
      await show({'status': 'already_saved'});
      expect(find.text('Already in memory'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('undo disappears once the change was undone', (tester) async {
      await tester.pumpWidget(
        aiTestApp(
          AiMemoryLine(
            step: memory({
              'ok': true,
              'data': {
                'status': 'saved',
                'content': 'Knee injury',
                'undone': true,
              },
            }),
            onUndo: () {},
          ),
          locale: 'pt',
        ),
      );
      expect(find.text('Desfazer'), findsNothing);
      expect(find.text('Desfeito'), findsOneWidget);
    });

    testWidgets('a failed memory call shows a quiet warning', (tester) async {
      await tester.pumpWidget(
        aiTestApp(
          AiMemoryLine(
            step: memory({'ok': false, 'code': 'limit_reached'}),
            onUndo: () {},
          ),
        ),
      );
      expect(find.text('Could not update memory'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('event lines are localized and unknown ones are empty', (
      tester,
    ) async {
      Future<void> show(Map<String, dynamic>? payload, String locale) => tester
          .pumpWidget(aiTestApp(AiEventLine(payload: payload), locale: locale));
      await show({'type': 'proposal_outcome', 'status': 'applied'}, 'en');
      expect(find.text('Change applied'), findsOneWidget);
      await show({'type': 'proposal_outcome', 'status': 'rejected'}, 'pt');
      expect(find.text('Proposta recusada'), findsOneWidget);
      await show({'type': 'proposal_outcome', 'status': 'stale'}, 'en');
      expect(
        find.text('Proposal outdated, nothing was changed'),
        findsOneWidget,
      );
      await show({'type': 'memory_change_undone'}, 'en');
      expect(find.text('Memory change undone'), findsOneWidget);
      await show({'type': 'something_new'}, 'en');
      expect(find.byType(Text), findsNothing);
      await show(null, 'en');
      expect(find.byType(Text), findsNothing);
    });
  });

  group('live turn', () {
    testWidgets('names the phase and streams the draft as markdown', (
      tester,
    ) async {
      await tester.pumpWidget(aiTestApp(AiLiveTurnBubble(turn: _turn())));
      expect(find.text('Thinking…'), findsOneWidget);

      await tester.pumpWidget(
        aiTestApp(
          AiLiveTurnBubble(
            turn: _turn(
              phase: AiTurnPhase.usingTools,
              tools: ['get_sleep', 'get_nutrition', 'get_sleep'],
            ),
          ),
        ),
      );
      expect(find.text('Reading: Sleep, Nutrition'), findsOneWidget);

      await tester.pumpWidget(
        aiTestApp(AiLiveTurnBubble(turn: _turn(phase: AiTurnPhase.compacting))),
      );
      expect(find.text('Organizing earlier messages…'), findsOneWidget);

      await tester.pumpWidget(
        aiTestApp(
          AiLiveTurnBubble(
            turn: _turn(
              phase: AiTurnPhase.writing,
              draft: 'You slept **well**',
            ),
          ),
        ),
      );
      expect(find.text('Writing…'), findsOneWidget);
      expect(find.text('You slept well'), findsOneWidget);

      await tester.pumpWidget(
        aiTestApp(
          AiLiveTurnBubble(turn: _turn(cancelling: true)),
          locale: 'pt',
        ),
      );
      expect(find.text('Parando…'), findsOneWidget);
    });

    testWidgets('elapsed seconds appear only after ten seconds', (
      tester,
    ) async {
      await tester.pumpWidget(
        aiTestApp(
          AiLiveTurnBubble(
            turn: _turn(
              startedAt: DateTime.now().subtract(const Duration(seconds: 3)),
            ),
          ),
        ),
      );
      expect(find.textContaining(' s'), findsNothing);

      await tester.pumpWidget(
        aiTestApp(
          AiLiveTurnBubble(
            turn: _turn(
              startedAt: DateTime.now().subtract(const Duration(seconds: 25)),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('· 25 s'), findsOneWidget);
    });

    testWidgets('the phase is a live region for screen readers', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(aiTestApp(AiLiveTurnBubble(turn: _turn())));
      final node = tester.getSemantics(find.bySemanticsLabel('Thinking…'));
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('redraws the draft at most every 90 ms', (tester) async {
      Widget bubble(String draft) => aiTestApp(
        AiLiveTurnBubble(
          turn: _turn(phase: AiTurnPhase.writing, draft: draft),
        ),
      );
      await tester.pumpWidget(bubble('Hello'));
      expect(find.text('Hello'), findsOneWidget);

      // A burst of deltas right after a redraw is coalesced.
      await tester.pumpWidget(bubble('Hello w'));
      await tester.pumpWidget(bubble('Hello wor'));
      await tester.pumpWidget(bubble('Hello world'));
      await tester.pump(
        kAiDraftRedrawInterval + const Duration(milliseconds: 5),
      );
      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('a new round clears the draft at once', (tester) async {
      Widget bubble(String draft) => aiTestApp(
        AiLiveTurnBubble(
          turn: _turn(phase: AiTurnPhase.writing, draft: draft),
        ),
      );
      await tester.pumpWidget(bubble('Partial text'));
      expect(find.text('Partial text'), findsOneWidget);
      await tester.pumpWidget(bubble(''));
      expect(find.text('Partial text'), findsNothing);
    });

    testWidgets('developer info sums the rounds', (tester) async {
      await tester.pumpWidget(
        aiTestApp(
          const AiTurnInfoRow(
            rounds: [
              AiRoundDiagnostics(
                round: 1,
                requestChars: 1000,
                durationMs: 2000,
                promptTokens: 300,
                cachedTokens: 100,
                completionTokens: 20,
              ),
              AiRoundDiagnostics(
                round: 2,
                requestChars: 1500,
                durationMs: 3400,
                promptTokens: 500,
                cachedTokens: 400,
                completionTokens: 80,
              ),
            ],
          ),
        ),
      );
      expect(
        find.text(
          '2 rounds · 2500 characters sent · '
          '800 tokens in, 500 cached, 100 out · 5 s',
        ),
        findsOneWidget,
      );
    });
  });

  group('error banner', () {
    testWidgets('one localized line, details on demand, retry and dismiss', (
      tester,
    ) async {
      var retried = 0;
      var dismissed = 0;
      await tester.pumpWidget(
        aiTestApp(
          AiErrorBanner(
            error: 'ai_error:rate_limited',
            details: const AiChatErrorDetails(
              code: 'rate_limited',
              stage: 'round_2',
              httpStatus: 429,
              model: 'gpt-x',
              provider: 'OpenAI',
              requestCharacters: 9000,
              message: 'Slow down please',
            ),
            onRetry: () => retried++,
            onDismiss: () => dismissed++,
          ),
        ),
      );

      expect(
        find.text('Too many requests. Wait a moment and try again.'),
        findsOneWidget,
      );
      // Technical lines stay hidden until asked for.
      expect(find.textContaining('HTTP 429'), findsNothing);
      await tester.tap(find.text('Details'));
      await tester.pump();
      expect(find.textContaining('HTTP 429'), findsOneWidget);
      expect(find.textContaining('OpenAI / gpt-x'), findsOneWidget);
      expect(find.textContaining('Slow down please'), findsOneWidget);

      await tester.tap(find.byTooltip('Retry'));
      await tester.tap(find.byTooltip('Dismiss'));
      expect(retried, 1);
      expect(dismissed, 1);
    });

    testWidgets('no retry button without a retryable error', (tester) async {
      await tester.pumpWidget(
        aiTestApp(
          AiErrorBanner(error: 'ai_error:missing_token', onDismiss: () {}),
        ),
      );
      expect(find.byTooltip('Retry'), findsNothing);
      expect(find.byTooltip('Dismiss'), findsOneWidget);
    });

    testWidgets('developer mode opens the details and caps their height', (
      tester,
    ) async {
      await tester.pumpWidget(
        aiTestApp(
          AiErrorBanner(
            error: 'ai_error:bad_request',
            developerMode: true,
            details: AiChatErrorDetails(
              code: 'bad_request',
              stage: 'round_1',
              message: List.filled(60, 'long provider message').join(' '),
              compatibilityAdjustments: List.filled(40, 'dropped_param'),
            ),
            onDismiss: () {},
          ),
        ),
      );
      expect(find.text('Hide details'), findsOneWidget);
      final scroll = find.ancestor(
        of: find.byType(SelectableText),
        matching: find.byType(ConstrainedBox),
      );
      final capped = tester
          .widgetList<ConstrainedBox>(scroll)
          .any((box) => box.constraints.maxHeight == 150);
      expect(capped, isTrue);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('Copy details'));
      await tester.pump();
      expect(copied, contains('bad_request'));
      expect(copied, contains('long provider message'));
    });
  });

  group('error localizer', () {
    testWidgets('every code has an English and a Portuguese text', (
      tester,
    ) async {
      const codes = [
        'missing_provider',
        'consent_required',
        'missing_model',
        'missing_token',
        'too_many_images',
        'image_missing',
        'image_too_large',
        'unsupported_image',
        'timeout',
        'connection_error',
        'cancelled',
        'invalid_token',
        'payment_required',
        'forbidden',
        'not_found',
        'payload_too_large',
        'context_length_exceeded',
        'bad_request',
        'rate_limited',
        'provider_unavailable',
        'invalid_response',
        'empty_choices',
        'empty_answer',
        'vision_not_supported',
        'proposal_failed',
        'proposal_stale',
        'generic',
      ];
      late AppLocalizations en;
      late AppLocalizations pt;
      await tester.pumpWidget(
        aiTestApp(
          Builder(
            builder: (context) {
              en = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpWidget(
        aiTestApp(
          Builder(
            builder: (context) {
              pt = AppLocalizations.of(context)!;
              return const SizedBox();
            },
          ),
          locale: 'pt',
        ),
      );
      final generic = {
        localizeAiError('ai_error:generic', en),
        localizeAiError('ai_error:generic', pt),
      };
      for (final code in codes) {
        final english = localizeAiError('ai_error:$code', en);
        final portuguese = localizeAiError('ai_error:$code', pt);
        expect(english, isNotEmpty, reason: code);
        expect(portuguese, isNot(english), reason: 'pt differs for $code');
        if (code != 'generic') {
          expect(generic.contains(english), isFalse, reason: 'specific $code');
        }
      }
      // proposal_<code> falls back to the generic proposal failure.
      expect(
        localizeAiError('ai_error:proposal_something_odd', en),
        localizeAiError('ai_error:proposal_failed', en),
      );
      expect(
        localizeAiError('ai_error:routine_apply_failed:abc', en),
        localizeAiError('ai_error:proposal_failed', en),
      );
      expect(localizeAiError('ai_error:never_heard_of_it', en), generic.first);
      expect(localizeAiError(null, en), generic.first);
      expect(aiErrorCode('ai_error:rate_limited'), 'rate_limited');
      expect(aiErrorCode('timeout'), 'timeout');
      expect(aiErrorCode(null), isNull);
    });
  });

  group('consent dialog', () {
    testWidgets('names the provider and resolves on the choice', (
      tester,
    ) async {
      bool? result;
      await tester.pumpWidget(
        aiTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showAiConsentDialog(
                context,
                providerName: 'OpenRouter',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Send your data to OpenRouter?'), findsOneWidget);
      expect(find.textContaining('your messages'), findsOneWidget);
      expect(find.textContaining('OpenRouter'), findsWidgets);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isFalse);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agree and send'));
      await tester.pumpAndSettle();
      expect(result, isTrue);
    });

    testWidgets('falls back to a generic provider name', (tester) async {
      await tester.pumpWidget(
        aiTestApp(
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showAiConsentDialog(context),
              child: const Text('open'),
            ),
          ),
          locale: 'pt',
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enviar seus dados para seu provedor de IA?'),
        findsOneWidget,
      );
    });
  });
}
