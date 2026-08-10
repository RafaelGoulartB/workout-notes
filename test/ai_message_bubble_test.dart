import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/widgets/ai/ai_chat_input_bar.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';
import 'package:workout_notes/widgets/ai/ai_tool_result_bubble.dart';

void main() {
  testWidgets('renders markdown captures instead of literal dollar one', (
    tester,
  ) async {
    final message = AiChatMessage(
      id: 'message-1',
      threadId: 'thread-1',
      role: AiMessageRole.assistant,
      content: '**Agachamento**: 60x10\n*Supino reto*: 50x10',
      createdAt: DateTime(2026, 6, 30),
    );

    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: message, showTimestamp: false)),
    );

    expect(find.textContaining('Agachamento: 60x10'), findsOneWidget);
    expect(find.textContaining('Supino reto: 50x10'), findsOneWidget);
    expect(find.textContaining(r'$1'), findsNothing);
  });

  testWidgets('assistant response stays readable at narrow mobile width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final message = AiChatMessage(
      id: 'assistant-mobile',
      threadId: 'thread-1',
      role: AiMessageRole.assistant,
      content:
          '## Recuperação\n\nSeu sono e sua alimentação serão analisados em conjunto.',
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(_testApp(AiMessageBubble(message: message)));

    expect(find.text('Treinador IA'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tool call card exposes status and expandable details', (
    tester,
  ) async {
    final message = AiChatMessage(
      id: 'tool-1',
      threadId: 'thread-1',
      role: AiMessageRole.tool,
      content: '{"ok":true,"data":{"recordedNights":7}}',
      toolCallId: 'call-1',
      toolName: 'get_sleep_summary',
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(
      _testApp(
        AiToolResultBubble(
          message: message,
          toolLabel: 'Analisando sono recente',
        ),
      ),
    );

    expect(find.text('Analisando sono recente'), findsOneWidget);
    expect(find.text('Consulta concluída'), findsOneWidget);
    expect(
      tester
          .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .crossFadeState,
      CrossFadeState.showFirst,
    );

    await tester.tap(find.text('Analisando sono recente'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .crossFadeState,
      CrossFadeState.showSecond,
    );
    expect(find.textContaining('recordedNights'), findsOneWidget);
  });

  testWidgets('tool call card can start expanded from chat preference', (
    tester,
  ) async {
    final message = AiChatMessage(
      id: 'tool-expanded',
      threadId: 'thread-1',
      role: AiMessageRole.tool,
      content: '{"ok":true,"data":{"days":7}}',
      toolCallId: 'call-expanded',
      toolName: 'get_weekly_recovery_trend',
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(
      _testApp(
        AiToolResultBubble(
          message: message,
          toolLabel: 'Recuperação semanal',
          initiallyExpanded: true,
        ),
      ),
    );

    expect(
      tester
          .widget<AnimatedCrossFade>(find.byType(AnimatedCrossFade))
          .crossFadeState,
      CrossFadeState.showSecond,
    );
    expect(find.textContaining('days'), findsOneWidget);
  });

  testWidgets('composer enables send only after meaningful input', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sends = 0;
    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: false,
          onSend: () => sends++,
        ),
      ),
    );

    final send = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Enviar mensagem',
    );
    expect(tester.widget<IconButton>(send).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Analise meu sono');
    await tester.pump();
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    await tester.tap(send);
    expect(sends, 1);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  locale: const Locale('pt'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
