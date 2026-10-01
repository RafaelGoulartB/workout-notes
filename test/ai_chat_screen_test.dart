import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/screens/ai/ai_chat_screen.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/state/ai_chat_service.dart';

import 'support/ai_chat_harness.dart';
import 'support/ai_proposal_fixtures.dart';
import 'support/ai_ui_support.dart';

void main() {
  AiChatHarness? harness;

  tearDown(() async {
    await harness?.dispose();
    harness = null;
  });

  Future<AiChatHarness> start(
    WidgetTester tester, {
    AiScript? script,
    bool consent = true,
    String locale = 'en',
    bool developerMode = false,
  }) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final h = await tester.runAsync(
      () => AiChatHarness.start(
        script: script,
        consent: consent,
        locale: locale,
        developerMode: developerMode,
      ),
    );
    harness = h;
    await tester.runAsync(h!.chat.ensureReady);
    return h;
  }

  Future<void> show(WidgetTester tester, {String locale = 'en'}) async {
    await tester.pumpWidget(
      aiTestApp(const AiChatScreen(), scaffold: false, locale: locale),
    );
    await tester.pump();
  }

  /// Lets [ms] of real time pass, redrawing as it goes: work started by a tap
  /// (inside the fake-async zone) only finishes when real time and frames
  /// interleave.
  Future<void> pumpReal(WidgetTester tester, [int ms = 60]) async {
    for (var i = 0; i < ms ~/ 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
  }

  Future<void> until(
    WidgetTester tester,
    bool Function() condition, {
    String? reason,
  }) async {
    for (var i = 0; i < 600 && !condition(); i++) {
      await pumpReal(tester, 10);
    }
    expect(condition(), isTrue, reason: reason ?? 'condition not reached');
    await tester.pump(const Duration(milliseconds: 150));
  }

  Future<void> send(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
  }

  /// Drags the list and lets the fling it leaves behind run out.
  Future<void> scrollBy(WidgetTester tester, double dy) async {
    await tester.drag(find.byType(ListView).first, Offset(0, dy));
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// Waits for the work a tap started, then for the running turn to end.
  Future<void> idle(WidgetTester tester) async {
    await pumpReal(tester, 120);
    await until(tester, () => harness!.chat.state.turn == null, reason: 'turn');
  }

  testWidgets('shows the welcome until the first message', (tester) async {
    await start(tester);
    await show(tester);
    expect(find.text("Hi! I'm your AI Coach."), findsOneWidget);
    expect(find.byTooltip('Send message'), findsOneWidget);
  });

  testWidgets(
    'a turn renders the steps row, the answer and keeps the composer',
    (tester) async {
      await start(
        tester,
        script: (payload) => aiToolMessageCount(payload) == 0
            ? AiReply.tools([
                aiWireCall('c1', 'get_sleep', {'days': 7}),
                aiWireCall('c2', 'get_nutrition', {'days': 7}),
              ])
            : const AiReply.text('You **slept** well.'),
      );
      await show(tester);
      await send(tester, 'How was my week?');
      await idle(tester);

      expect(find.text('How was my week?'), findsOneWidget);
      expect(find.text('Consulted: Sleep, Nutrition'), findsOneWidget);
      expect(find.text('last 7 days'), findsOneWidget);
      expect(find.text('You slept well.'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(find.byTooltip('Stop'), findsNothing);
      // The composer was cleared on acceptance.
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '',
      );
      // Raw JSON stays out of the way for regular users.
      expect(find.textContaining('"ok"'), findsNothing);
      expect(find.text('Raw data'), findsNothing);
    },
  );

  testWidgets(
    'streams the draft live, offers Stop, then shows Stopped and retry',
    (tester) async {
      final gate = Completer<void>();
      final h = await start(
        tester,
        script: (_) => AiReply.held('Partial answer', gate.future),
      );
      await show(tester);
      await send(tester, 'Plan my week');
      await until(
        tester,
        () => h.chat.state.turn?.draftText == 'Partial answer',
        reason: 'draft',
      );

      // The live bubble: streamed markdown plus the phase, and a Stop button.
      expect(find.text('Partial answer'), findsOneWidget);
      expect(find.text('Writing…'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsNothing);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);

      await tester.tap(find.byTooltip('Stop'));
      await tester.pump();
      expect(find.text('Stopping…'), findsOneWidget);
      await idle(tester);

      expect(h.provider.aborted, 1);
      expect(find.text('Partial answer'), findsNothing);
      expect(find.text('Stopped'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byTooltip('Send message'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);

      // Retry answers the same message again.
      h.provider.script = (_) => const AiReply.text('Here is the plan.');
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await idle(tester);
      expect(find.text('Here is the plan.'), findsOneWidget);
      expect(find.text('Stopped'), findsNothing);
      expect(find.text('Plan my week'), findsOneWidget);
    },
  );

  testWidgets('a provider error becomes one calm line with details and retry', (
    tester,
  ) async {
    final h = await start(
      tester,
      script: (_) => const AiReply.error(
        429,
        '{"error":{"message":"slow down","type":"rate_limit"}}',
      ),
    );
    await show(tester);
    await send(tester, 'Hello');
    await idle(tester);

    expect(
      find.text('Too many requests. Wait a moment and try again.'),
      findsOneWidget,
    );
    // Technical details stay folded until asked for.
    expect(find.textContaining('HTTP 429'), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(find.textContaining('HTTP 429'), findsOneWidget);

    h.provider.script = (_) => const AiReply.text('Hi there!');
    await tester.tap(find.byTooltip('Retry'));
    await tester.pump();
    await idle(tester);
    expect(find.text('Hi there!'), findsOneWidget);
    expect(
      find.text('Too many requests. Wait a moment and try again.'),
      findsNothing,
    );
  });

  testWidgets('the error banner can be dismissed', (tester) async {
    await start(
      tester,
      script: (_) =>
          const AiReply.error(401, '{"error":{"message":"bad key"}}'),
    );
    await show(tester);
    await send(tester, 'Hello');
    await idle(tester);

    expect(find.byTooltip('Dismiss'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(find.byTooltip('Dismiss'), findsNothing);
    expect(harness!.chat.state.error, isNull);
  });

  testWidgets('first message asks for consent and names the provider', (
    tester,
  ) async {
    final h = await start(tester, consent: false);
    await show(tester);
    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();

    expect(find.text('Send your data to TestAI?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(h.settings.settings.dataSharingAccepted, isFalse);
    expect(h.provider.payloads, isEmpty);
    // The typed text is kept.
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello',
    );

    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and send'));
    await tester.pump();
    await until(tester, () => h.provider.payloads.isNotEmpty, reason: 'sent');
    await idle(tester);
    expect(h.settings.settings.dataSharingAccepted, isTrue);
    expect(find.text('ok'), findsOneWidget);

    // Later messages do not ask again.
    await send(tester, 'And now?');
    expect(find.text('Send your data to TestAI?'), findsNothing);
    await idle(tester);
  });

  testWidgets('a consent_required error offers to allow it and carry on', (
    tester,
  ) async {
    final h = await start(tester);
    await show(tester);
    await tester.runAsync(() async {
      await h.settings.setDataSharingAccepted(false);
      await h.chat.send('Hello');
    });
    await tester.pump();
    expect(
      find.text(
        'Allow the coach to send your data to the provider to continue.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byTooltip('Retry'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agree and send'));
    await tester.pumpAndSettle();
    expect(h.settings.settings.dataSharingAccepted, isTrue);
    expect(
      find.text(
        'Allow the coach to send your data to the provider to continue.',
      ),
      findsNothing,
    );
  });

  testWidgets('a saved memory shows a line with undo, and undo is recorded', (
    tester,
  ) async {
    final h = await start(
      tester,
      script: (payload) => aiToolMessageCount(payload) == 0
          ? AiReply.tools([
              aiWireCall('m1', 'save_memory', {
                'content': 'Left knee is sore',
                'category': 'health',
              }),
            ])
          : const AiReply.text('Noted.'),
    );
    await show(tester);
    await send(tester, 'My left knee hurts');
    await idle(tester);

    expect(find.text('Memory saved: Left knee is sore'), findsOneWidget);
    expect(find.text('Noted.'), findsOneWidget);
    expect((await tester.runAsync(h.memory.all))!, hasLength(1));

    await tester.tap(find.text('Undo'));
    await until(
      tester,
      () => h.chat.state.messages.any((m) => m.isEvent),
      reason: 'undo event',
    );

    expect((await tester.runAsync(h.memory.all))!, isEmpty);
    expect(find.text('Undo'), findsNothing);
    expect(find.text('Undone'), findsOneWidget);
    expect(find.text('Memory change undone'), findsOneWidget);
  });

  testWidgets(
    'a turn in another conversation blocks the composer with a way there',
    (tester) async {
      final gate = Completer<void>();
      final h = await start(
        tester,
        script: (_) => AiReply.held('Still working', gate.future),
      );
      await show(tester);
      await send(tester, 'Long question');
      await until(
        tester,
        () => h.chat.state.turn?.draftText == 'Still working',
        reason: 'draft',
      );
      final running = h.chat.state.turn!.threadId;

      await tester.runAsync(h.chat.newChat);
      await tester.pump();
      expect(
        find.text('The coach is answering in another conversation'),
        findsWidgets,
      );
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
      expect(find.text('Still working'), findsNothing);

      await tester.tap(find.text('Open'));
      await until(
        tester,
        () => h.chat.state.activeThreadId == running,
        reason: 'opened',
      );
      expect(find.text('Still working'), findsOneWidget);
      expect(find.byTooltip('Stop'), findsOneWidget);

      gate.complete();
      await idle(tester);
      expect(find.text('Still workingStill working'), findsNothing);
    },
  );

  testWidgets('developer mode shows raw data and turn info, others never do', (
    tester,
  ) async {
    Future<void> run(WidgetTester tester, {required bool developerMode}) async {
      await start(
        tester,
        developerMode: developerMode,
        script: (payload) => aiToolMessageCount(payload) == 0
            ? AiReply.tools([
                aiWireCall('c1', 'get_sleep', {'days': 7}),
              ])
            : const AiReply.text('All good.'),
      );
      await show(tester);
      await send(tester, 'Check my sleep');
      await idle(tester);
    }

    await run(tester, developerMode: true);
    expect(find.textContaining('rounds'), findsOneWidget);
    expect(find.textContaining('characters sent'), findsOneWidget);
    await tester.tap(find.text('Consulted: Sleep'));
    await tester.pump();
    expect(find.text('Raw data'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(harness!.dispose);
    harness = null;
    await run(tester, developerMode: false);
    expect(find.textContaining('characters sent'), findsNothing);
    await tester.tap(find.text('Consulted: Sleep'));
    await tester.pump();
    expect(find.text('Raw data'), findsNothing);
  });

  testWidgets('a proposal card appears under its step and approving it works', (
    tester,
  ) async {
    final h = await start(tester);
    final created = DateTime(2026, 9, 30, 9);
    final call = aiCall('call_1', 'propose_body_measurement', {
      'measurements': [
        {'type': 'weight', 'value': 80},
      ],
    });
    await tester.runAsync(() async {
      await h.seedThread('t1', [
        aiUserMessage('u1', 'Log my weight', minute: 0),
        aiAssistantMessage('a1', calls: [call], minute: 1),
        aiToolMessage('tm1', call, {'ok': true, 'data': {}}, minute: 2),
        aiAssistantMessage('a2', text: 'I prepared it.', minute: 3),
      ]);
      await prepareProposal(
        AiProposalService(now: () => created),
        'propose_body_measurement',
        {
          'measurements': [
            {'type': 'weight', 'value': 80},
          ],
        },
        threadId: 't1',
        toolCallId: 'call_1',
      );
      await h.chat.openThread('t1');
    });
    await show(tester);

    expect(find.text('Log measurements'), findsWidgets);
    expect(find.text('Awaiting approval'), findsOneWidget);
    expect(find.text('I prepared it.'), findsOneWidget);

    await tester.tap(find.text('Approve and apply'));
    await until(
      tester,
      () => h.chat.state.messages.any((m) => m.isEvent),
      reason: 'applied',
    );
    expect(find.text('Applied'), findsWidgets);
    expect(find.text('Change applied'), findsOneWidget);
  });

  group('long conversations', () {
    List<AiChatMessage> conversation(int pairs) => [
      for (var i = 0; i < pairs; i++) ...[
        aiUserMessage('u$i', 'Question $i', minute: i * 2),
        aiAssistantMessage(
          'a$i',
          text: 'Answer $i\n\nA second paragraph of answer $i.',
          minute: i * 2 + 1,
        ),
      ],
    ];

    Future<void> openLong(WidgetTester tester) async {
      final h = await start(tester);
      await tester.runAsync(() async {
        await h.seedThread('long', conversation(100));
        await h.chat.openThread('long');
      });
      await show(tester);
    }

    int? visibleQuestion(WidgetTester tester) {
      for (var i = 0; i < 100; i++) {
        final finder = find.text('Question $i');
        if (finder.evaluate().isNotEmpty) return i;
      }
      return null;
    }

    testWidgets('opens at the newest message', (tester) async {
      await openLong(tester);
      expect(find.text('Answer 99'), findsOneWidget);
      expect(find.text('Question 0'), findsNothing);
      expect(harness!.chat.state.messages, hasLength(80));
      expect(harness!.chat.state.hasOlderMessages, isTrue);
    });

    testWidgets('loading older messages keeps what is being read in place', (
      tester,
    ) async {
      final h = await start(tester);
      await tester.runAsync(() async {
        await h.seedThread('long', conversation(100));
        await h.chat.openThread('long');
      });
      await show(tester);

      // Scroll up until the previous page is requested.
      var guard = 0;
      while (!h.chat.state.isLoadingOlderMessages &&
          h.chat.state.messages.length == 80 &&
          guard++ < 60) {
        await scrollBy(tester, 500);
      }
      final reading = visibleQuestion(tester);
      expect(reading, isNotNull);
      final before = tester.getTopLeft(find.text('Question $reading')).dy;

      await until(
        tester,
        () => h.chat.state.messages.length > 80,
        reason: 'older page',
      );
      expect(h.chat.state.messages.length, 160);

      final after = tester.getTopLeft(find.text('Question $reading')).dy;
      expect(after, closeTo(before, 1));
    });

    testWidgets('"Latest" appears when scrolled away and returns to the end', (
      tester,
    ) async {
      await openLong(tester);
      double opacity() => tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('ai-jump-to-latest')),
          )
          .opacity;
      expect(opacity(), 0);

      await scrollBy(tester, 700);
      expect(opacity(), 1);
      expect(find.text('Answer 99'), findsNothing);

      await tester.tap(find.text('Latest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Answer 99'), findsOneWidget);
      expect(opacity(), 0);
    });

    testWidgets(
      'streaming keeps following the end but never drags a reader along',
      (tester) async {
        final gate = Completer<void>();
        final finish = Completer<void>();
        final h = await start(
          tester,
          script: (_) => AiReply.held(
            'Start',
            gate.future,
            finish: finish.future,
            rest: List.generate(
              30,
              (i) => '\n\nLine number $i of the answer',
            ).join(),
          ),
        );
        await tester.runAsync(() async {
          await h.seedThread('long', conversation(100));
          await h.chat.openThread('long');
        });
        await show(tester);
        await send(tester, 'Tell me more');
        await until(
          tester,
          () => h.chat.state.turn?.draftText == 'Start',
          reason: 'draft',
        );
        // The reader scrolls up while the answer is still being written.
        await scrollBy(tester, 900);
        final reading = visibleQuestion(tester)!;
        final before = tester.getTopLeft(find.text('Question $reading')).dy;

        // The answer grows by dozens of lines below them: nothing moves.
        gate.complete();
        await until(
          tester,
          () => (h.chat.state.turn?.draftText.length ?? 0) > 500,
          reason: 'long draft',
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Question $reading'), findsOneWidget);
        final during = tester.getTopLeft(find.text('Question $reading')).dy;
        expect(during, closeTo(before, 2));

        // When the answer is stored the text still is where they were reading.
        finish.complete();
        await idle(tester);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Question $reading'), findsOneWidget);
        final after = tester.getTopLeft(find.text('Question $reading')).dy;
        expect(after, closeTo(before, 150));
      },
    );

    testWidgets('a reader at the end follows the streaming answer', (
      tester,
    ) async {
      final gate = Completer<void>();
      final finish = Completer<void>();
      final h = await start(
        tester,
        script: (_) => AiReply.held(
          'Start',
          gate.future,
          finish: finish.future,
          rest: List.generate(
            30,
            (i) => '\n\nLine number $i of the answer',
          ).join(),
        ),
      );
      await tester.runAsync(() async {
        await h.seedThread('long', conversation(100));
        await h.chat.openThread('long');
      });
      await show(tester);
      await send(tester, 'Tell me more');
      await until(
        tester,
        () => h.chat.state.turn?.draftText == 'Start',
        reason: 'draft',
      );
      // The service redraws at most every 60 ms of real time.
      await pumpReal(tester, 100);
      gate.complete();
      await until(
        tester,
        () => (h.chat.state.turn?.draftText.length ?? 0) > 500,
        reason: 'long draft',
      );
      await tester.pump(const Duration(milliseconds: 300));

      // The newest line of the draft is on screen.
      expect(find.textContaining('Line number 29'), findsOneWidget);
      finish.complete();
      await idle(tester);
    });
  });
}
