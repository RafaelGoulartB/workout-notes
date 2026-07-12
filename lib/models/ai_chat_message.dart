import 'dart:convert';

import 'ai_message_role.dart';
import 'ai_tool_call.dart';

/// A single chat message, persisted in `ai_chat_messages`.
class AiChatMessage {
  final String id;
  final String threadId;
  final AiMessageRole role;
  final String? content;
  final String? toolCallId;
  final String? toolName;
  final List<AiToolCall> toolCalls;
  final AiToolResult? toolResult;
  final DateTime createdAt;

  const AiChatMessage({
    required this.id,
    required this.threadId,
    required this.role,
    required this.createdAt,
    this.content,
    this.toolCallId,
    this.toolName,
    this.toolCalls = const [],
    this.toolResult,
  });

  bool get isUser => role == AiMessageRole.user;
  bool get isAssistant => role == AiMessageRole.assistant;
  bool get isTool => role == AiMessageRole.tool;
  bool get isSystem => role == AiMessageRole.system;

  AiChatMessage copyWith({
    String? content,
    List<AiToolCall>? toolCalls,
    AiToolResult? toolResult,
  }) {
    return AiChatMessage(
      id: id,
      threadId: threadId,
      role: role,
      createdAt: createdAt,
      content: content ?? this.content,
      toolCallId: toolCallId,
      toolName: toolName,
      toolCalls: toolCalls ?? this.toolCalls,
      toolResult: toolResult ?? this.toolResult,
    );
  }

  AiChatMessage withThreadId(String value) {
    return AiChatMessage(
      id: id,
      threadId: value,
      role: role,
      createdAt: createdAt,
      content: content,
      toolCallId: toolCallId,
      toolName: toolName,
      toolCalls: toolCalls,
      toolResult: toolResult,
    );
  }

  Map<String, dynamic> toRow() {
    return {
      'id': id,
      'thread_id': threadId,
      'role': role.wireValue,
      'content': content,
      'tool_call_id': toolCallId,
      'tool_name': toolName,
      'tool_calls_json': toolCalls.isEmpty
          ? null
          : jsonEncode(toolCalls.map((c) => c.toJson()).toList()),
      'created_at': createdAt.toIso8601String(),
    };
  }

  static AiChatMessage fromRow(Map<String, dynamic> row) {
    final callsJson = row['tool_calls_json'] as String?;
    final List<AiToolCall> calls = [];
    if (callsJson != null && callsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(callsJson);
        if (decoded is List) {
          for (final raw in decoded) {
            if (raw is Map) {
              calls.add(AiToolCall.fromJson(raw.cast<String, dynamic>()));
            }
          }
        }
      } catch (_) {}
    }
    return AiChatMessage(
      id: row['id'] as String,
      threadId: row['thread_id'] as String,
      role: AiMessageRoleX.fromWire(row['role'] as String?),
      content: row['content'] as String?,
      toolCallId: row['tool_call_id'] as String?,
      toolName: row['tool_name'] as String?,
      toolCalls: calls,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
