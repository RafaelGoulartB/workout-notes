import 'dart:convert';

import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/utils/text_fold.dart';

/// Lifecycle of a user turn, stored on the user message that started it.
enum AiTurnStatus {
  running,
  done,
  failed,
  cancelled,
  interrupted;

  static AiTurnStatus? fromStorage(String? value) {
    for (final status in values) {
      if (status.name == value) return status;
    }
    return null;
  }
}

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

  /// Opaque provider fields of an assistant message (reasoning content,
  /// reasoning details, Responses reasoning items) echoed back inside the
  /// turn that produced them.
  final Map<String, dynamic> providerExtras;

  /// Set on user messages: how the turn they started ended.
  final AiTurnStatus? turnStatus;

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
    this.providerExtras = const {},
    this.turnStatus,
  });

  bool get isUser => role == AiMessageRole.user;
  bool get isAssistant => role == AiMessageRole.assistant;
  bool get isTool => role == AiMessageRole.tool;
  bool get isEvent => role == AiMessageRole.event;

  AiChatMessage copyWith({
    String? content,
    List<AiToolCall>? toolCalls,
    AiToolResult? toolResult,
    List<AiImageAttachment>? attachments,
    AiTurnStatus? turnStatus,
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
      providerExtras: providerExtras,
      turnStatus: turnStatus ?? this.turnStatus,
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
    'provider_extras': providerExtras.isEmpty
        ? null
        : jsonEncode(providerExtras),
    'turn_status': turnStatus?.name,
    'search_text': (isUser || isAssistant) && (content?.isNotEmpty ?? false)
        ? foldForSearch(content!)
        : null,
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
      } catch (_) {
        // Unreadable tool calls: show the message without them.
      }
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
      } catch (_) {
        // Unreadable attachments: show the message without them.
      }
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
      providerExtras: _decodeMap(row['provider_extras']),
      turnStatus: AiTurnStatus.fromStorage(row['turn_status'] as String?),
    );
  }

  static Map<String, dynamic> _decodeMap(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : const {};
    } on FormatException {
      return const {};
    }
  }
}
