import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/widgets/ai/ai_chat_timeline.dart';

import 'support/ai_ui_support.dart';

void main() {
  test('one agent step becomes text, a steps row and the final answer', () {
    final sleep = aiCall('c1', 'get_sleep', {'days': 7});
    final food = aiCall('c2', 'get_nutrition');
    final items = buildAiChatItems([
      aiUserMessage('u1', 'How was my week?'),
      aiAssistantMessage('a1', text: 'Let me look.', calls: [sleep, food]),
      aiToolMessage('t1', sleep, {'ok': true, 'data': {}}),
      aiToolMessage('t2', food, {'ok': false, 'code': 'not_found'}),
      aiAssistantMessage('a2', text: 'You slept well.'),
    ]);

    expect(items.map((i) => i.runtimeType), [
      AiUserItem,
      AiAssistantItem,
      AiStepsItem,
      AiAssistantItem,
    ]);
    expect((items[1] as AiAssistantItem).intermediate, isTrue);
    expect((items[3] as AiAssistantItem).intermediate, isFalse);
    final steps = (items[2] as AiStepsItem).steps;
    expect(steps.map((s) => s.call.name), ['get_sleep', 'get_nutrition']);
    expect(steps[0].failed, isFalse);
    expect(steps[1].failed, isTrue);
    expect(steps[1].outcome?.code, 'not_found');
  });

  test('tool-only steps merge into one row with a stable key', () {
    final c1 = aiCall('c1', 'get_sleep');
    final c2 = aiCall('c2', 'get_nutrition');
    final c3 = aiCall('c3', 'list_goals');
    List<AiChatItem> build(int upTo) => buildAiChatItems([
      aiUserMessage('u1', 'Hi'),
      aiAssistantMessage('a1', calls: [c1]),
      aiToolMessage('t1', c1, {'ok': true}),
      if (upTo >= 2) ...[
        aiAssistantMessage('a2', calls: [c2, c3]),
        aiToolMessage('t2', c2, {'ok': true}),
        aiToolMessage('t3', c3, {'ok': true}),
      ],
    ]);

    final early = build(1);
    final late = build(2);
    expect(early.whereType<AiStepsItem>(), hasLength(1));
    expect(late.whereType<AiStepsItem>(), hasLength(1));
    expect((late[1] as AiStepsItem).steps, hasLength(3));
    // The row keeps its identity while later steps join it.
    expect(early[1].key, late[1].key);
  });

  test('a step with text starts a new row', () {
    final c1 = aiCall('c1', 'get_sleep');
    final c2 = aiCall('c2', 'get_nutrition');
    final items = buildAiChatItems([
      aiUserMessage('u1', 'Hi'),
      aiAssistantMessage('a1', calls: [c1]),
      aiToolMessage('t1', c1, {'ok': true}),
      aiAssistantMessage('a2', text: 'Now food.', calls: [c2]),
      aiToolMessage('t2', c2, {'ok': true}),
    ]);

    expect(items.map((i) => i.runtimeType), [
      AiUserItem,
      AiStepsItem,
      AiAssistantItem,
      AiStepsItem,
    ]);
  });

  test('memory calls and proposals leave the steps row', () {
    final read = aiCall('c1', 'get_sleep');
    final save = aiCall('c2', 'save_memory', {'content': 'Knee injury'});
    final propose = aiCall('c3', 'propose_goal');
    final items = buildAiChatItems(
      [
        aiUserMessage('u1', 'Hi'),
        aiAssistantMessage('a1', calls: [read, save, propose]),
        aiToolMessage('t1', read, {'ok': true}),
        aiToolMessage('t2', save, {
          'ok': true,
          'data': {'status': 'saved', 'content': 'Knee injury'},
        }),
        aiToolMessage('t3', propose, {'ok': true}),
      ],
      proposalCallIds: {'c3'},
    );

    expect(items.map((i) => i.runtimeType), [
      AiUserItem,
      AiStepsItem,
      AiMemoryItem,
      AiProposalItem,
    ]);
    // The proposal call stays visible as a step; the memory call does not.
    expect((items[1] as AiStepsItem).steps.map((s) => s.call.name), [
      'get_sleep',
      'propose_goal',
    ]);
    expect(
      (items[2] as AiMemoryItem).step.fullOutcome?.data?['status'],
      'saved',
    );
    expect((items[3] as AiProposalItem).toolCallId, 'c3');
  });

  test('events, unanswered calls and orphaned tool messages', () {
    final orphan = aiCall('c0', 'get_sleep');
    final pending = aiCall('c1', 'get_nutrition');
    final items = buildAiChatItems([
      aiToolMessage('t0', orphan, {'ok': true}, minute: 0),
      aiUserMessage('u1', 'Hi'),
      aiAssistantMessage('a1', calls: [pending]),
      aiEventMessage('e1', {'type': 'memory_change_undone'}),
    ]);

    expect(items.map((i) => i.runtimeType), [
      AiUserItem,
      AiStepsItem,
      AiEventItem,
    ]);
    final step = (items[1] as AiStepsItem).steps.single;
    expect(step.hasResult, isFalse);
    expect(step.failed, isFalse);
    expect((items[2] as AiEventItem).payload?['type'], 'memory_change_undone');
  });

  test('outcome parsing is cheap for ok results and tolerant of junk', () {
    expect(AiToolOutcome.parse('{"ok":true,"data":{"a":1}}').ok, isTrue);
    expect(AiToolOutcome.parse('{"ok":true,"data":{"a":1}}').data, isNull);
    expect(
      AiToolOutcome.parse('{"ok":true,"data":{"a":1}}', decodeData: true).data,
      {'a': 1},
    );
    final failed = AiToolOutcome.parse('{"ok":false,"code":"invalid_args"}');
    expect(failed.ok, isFalse);
    expect(failed.code, 'invalid_args');
    expect(AiToolOutcome.parse('not json').ok, isFalse);
    expect(AiToolOutcome.parse(null).ok, isFalse);
  });
}
