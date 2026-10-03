import 'dart:convert';

import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_tool_call.dart';

/// Tools whose result is shown as a one-line memory note (with undo) instead
/// of a tool step.
const Set<String> kAiMemoryToolNames = {'save_memory', 'delete_memory'};

/// What a tool message says, read lazily and only once.
class AiToolOutcome {
  final bool ok;
  final String? code;
  final String? message;
  final Map<String, dynamic>? data;

  const AiToolOutcome({required this.ok, this.code, this.message, this.data});

  /// A tool message without readable content counts as a failure.
  static const AiToolOutcome unreadable = AiToolOutcome(ok: false);

  /// Reads `{ok, data, code, message}`. Successful results of ordinary read
  /// tools can be large, so [decodeData] stays false for them.
  static AiToolOutcome parse(String? content, {bool decodeData = false}) {
    if (content == null || content.isEmpty) return unreadable;
    // `AiToolResult.toMap` always writes `ok` first.
    if (!decodeData) {
      if (content.startsWith('{"ok":true')) {
        return const AiToolOutcome(ok: true);
      }
    }
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map) return unreadable;
      final data = decoded['data'];
      return AiToolOutcome(
        ok: decoded['ok'] == true,
        code: decoded['code'] as String?,
        message: decoded['message'] as String?,
        data: data is Map ? data.cast<String, dynamic>() : null,
      );
    } on FormatException {
      return unreadable;
    }
  }
}

/// One tool call of an assistant message and the tool message that answered
/// it (null while it has no result).
class AiToolStep {
  final AiToolCall call;
  final AiChatMessage? result;

  AiToolStep({required this.call, required this.result});

  bool get hasResult => result != null;

  AiToolOutcome? _outcome;
  AiToolOutcome? _fullOutcome;

  /// Cheap outcome: ok / failed (+ code), no payload.
  AiToolOutcome? get outcome {
    final message = result;
    if (message == null) return null;
    return _outcome ??= AiToolOutcome.parse(message.content);
  }

  /// Outcome with the decoded `data` (memory lines, proposal links).
  AiToolOutcome? get fullOutcome {
    final message = result;
    if (message == null) return null;
    return _fullOutcome ??= AiToolOutcome.parse(
      message.content,
      decodeData: true,
    );
  }

  bool get failed => hasResult && outcome?.ok != true;
  bool get isMemory => kAiMemoryToolNames.contains(call.name);
}

/// A row of the chat list, in conversation order.
sealed class AiChatItem {
  /// Stable across rebuilds and when later messages join the same item.
  String get key;
}

class AiUserItem extends AiChatItem {
  final AiChatMessage message;
  AiUserItem(this.message);

  @override
  String get key => 'user:${message.id}';
}

/// Assistant text: the final answer, or the text before a tool step.
class AiAssistantItem extends AiChatItem {
  final AiChatMessage message;
  final bool intermediate;
  AiAssistantItem(this.message, {this.intermediate = false});

  @override
  String get key => 'assistant:${message.id}';
}

/// The compact "Consulted: …" row of one or more consecutive tool steps.
class AiStepsItem extends AiChatItem {
  final String id;
  final List<AiToolStep> steps;
  AiStepsItem(this.id, this.steps);

  @override
  String get key => 'steps:$id';
}

/// A `save_memory` / `delete_memory` call.
class AiMemoryItem extends AiChatItem {
  final AiToolStep step;
  AiMemoryItem(this.step);

  @override
  String get key => 'memory:${step.call.id}';
}

/// The card of a proposal made by a tool call.
class AiProposalItem extends AiChatItem {
  final String toolCallId;
  AiProposalItem(this.toolCallId);

  @override
  String get key => 'proposal:$toolCallId';
}

/// A status line the app wrote (proposal outcome, memory change undone).
class AiEventItem extends AiChatItem {
  final AiChatMessage message;
  AiEventItem(this.message);

  @override
  String get key => 'event:${message.id}';

  Map<String, dynamic>? get payload {
    try {
      final decoded = jsonDecode(message.content ?? '');
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }
}

/// Turns the stored messages into list rows. Pure: the screen caches the
/// result per message list.
///
/// Consecutive assistant steps that only call tools (no visible text) share
/// one row, so a long investigation reads "Consulted: Sleep, Nutrition (+3)"
/// instead of a stack of rows. [proposalCallIds] are the tool calls that
/// produced an inline proposal card.
List<AiChatItem> buildAiChatItems(
  List<AiChatMessage> messages, {
  Set<String> proposalCallIds = const {},
}) {
  final items = <AiChatItem>[];
  var i = 0;
  while (i < messages.length) {
    final message = messages[i];
    if (message.isUser) {
      items.add(AiUserItem(message));
      i++;
    } else if (message.isEvent) {
      items.add(AiEventItem(message));
      i++;
    } else if (message.isAssistant) {
      if (message.toolCalls.isEmpty) {
        if (_hasText(message)) items.add(AiAssistantItem(message));
        i++;
        continue;
      }
      if (_hasText(message)) {
        items.add(AiAssistantItem(message, intermediate: true));
      }
      final firstId = message.id;
      final steps = <AiToolStep>[];
      var next = _collectStep(messages, i, steps);
      // Merge following tool-only steps into the same row.
      while (next < messages.length &&
          messages[next].isAssistant &&
          messages[next].toolCalls.isNotEmpty &&
          !_hasText(messages[next])) {
        next = _collectStep(messages, next, steps);
      }
      final plain = [
        for (final step in steps)
          if (!step.isMemory) step,
      ];
      if (plain.isNotEmpty) items.add(AiStepsItem(firstId, plain));
      for (final step in steps) {
        if (step.isMemory) items.add(AiMemoryItem(step));
      }
      for (final step in steps) {
        if (proposalCallIds.contains(step.call.id)) {
          items.add(AiProposalItem(step.call.id));
        }
      }
      i = next;
    } else {
      // A tool message whose assistant message is not loaded (older page).
      i++;
    }
  }
  return items;
}

bool _hasText(AiChatMessage message) =>
    message.content?.trim().isNotEmpty == true;

/// Adds the steps of the assistant message at [index] and returns the index
/// after its tool messages.
int _collectStep(
  List<AiChatMessage> messages,
  int index,
  List<AiToolStep> out,
) {
  final assistant = messages[index];
  final results = <String, AiChatMessage>{};
  var next = index + 1;
  while (next < messages.length && messages[next].isTool) {
    final id = messages[next].toolCallId;
    if (id != null) results[id] = messages[next];
    next++;
  }
  for (final call in assistant.toolCalls) {
    out.add(AiToolStep(call: call, result: results[call.id]));
  }
  return next;
}
