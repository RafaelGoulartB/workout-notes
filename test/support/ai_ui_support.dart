import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_call.dart';

/// A localized `MaterialApp` around [child] for AI widget tests.
Widget aiTestApp(Widget child, {String locale = 'en', bool scaffold = true}) =>
    MaterialApp(
      locale: Locale(locale),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: scaffold ? Scaffold(body: child) : child,
    );

final DateTime _base = DateTime(2026, 9, 30, 9);

AiChatMessage aiUserMessage(
  String id,
  String text, {
  int minute = 0,
  AiTurnStatus? status,
}) => AiChatMessage(
  id: id,
  threadId: 't1',
  role: AiMessageRole.user,
  content: text,
  createdAt: _base.add(Duration(minutes: minute)),
  turnStatus: status,
);

AiToolCall aiCall(String id, String name, [Map<String, dynamic>? args]) =>
    AiToolCall(id: id, name: name, arguments: args ?? const {});

AiChatMessage aiAssistantMessage(
  String id, {
  String? text,
  List<AiToolCall> calls = const [],
  int minute = 1,
}) => AiChatMessage(
  id: id,
  threadId: 't1',
  role: AiMessageRole.assistant,
  content: text,
  toolCalls: calls,
  createdAt: _base.add(Duration(minutes: minute)),
);

AiChatMessage aiToolMessage(
  String id,
  AiToolCall call,
  Map<String, dynamic> result, {
  int minute = 1,
}) => AiChatMessage(
  id: id,
  threadId: 't1',
  role: AiMessageRole.tool,
  content: jsonEncode(result),
  toolCallId: call.id,
  toolName: call.name,
  createdAt: _base.add(Duration(minutes: minute)),
);

AiChatMessage aiEventMessage(
  String id,
  Map<String, dynamic> event, {
  int minute = 5,
}) => AiChatMessage(
  id: id,
  threadId: 't1',
  role: AiMessageRole.event,
  content: jsonEncode(event),
  createdAt: _base.add(Duration(minutes: minute)),
);
