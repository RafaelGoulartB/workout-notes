import 'dart:convert';

import 'ai_image_attachment.dart';
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
  final List<AiImageAttachment> attachments;
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
    this.attachments = const [],
  });

  bool get isUser => role == AiMessageRole.user;
  bool get isAssistant => role == AiMessageRole.assistant;
  bool get isTool => role == AiMessageRole.tool;
  bool get isSystem => role == AiMessageRole.system;

  AiChatMessage copyWith({
    String? content,
    List<AiToolCall>? toolCalls,
    AiToolResult? toolResult,
    List<AiImageAttachment>? attachments,
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
      attachments: attachments ?? this.attachments,
    );
  }

  Map<String, dynamic> toRow() => {
    'id': id,
    'thread_id': threadId,
    'role': role.wireValue,
    'content': content,
    'tool_call_id': toolCallId,
    'tool_name': toolName,
    'tool_calls_json': toolCalls.isEmpty
        ? null
        : jsonEncode(toolCalls.map((call) => call.toJson()).toList()),
    'attachments_json': attachments.isEmpty
        ? null
        : jsonEncode(attachments.map((item) => item.toJson()).toList()),
    'created_at': createdAt.toIso8601String(),
  };

  static AiChatMessage fromRow(Map<String, dynamic> row) {
    final calls = <AiToolCall>[];
    final callsJson = row['tool_calls_json'] as String?;
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

    final attachments = <AiImageAttachment>[];
    final attachmentsJson = row['attachments_json'] as String?;
    if (attachmentsJson != null && attachmentsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(attachmentsJson);
        if (decoded is List) {
          for (final raw in decoded) {
            if (raw is Map) {
              attachments.add(
                AiImageAttachment.fromJson(raw.cast<String, dynamic>()),
              );
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
      attachments: attachments,
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}
