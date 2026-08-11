import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
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

  testWidgets('user message renders persisted image attachments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final message = AiChatMessage(
      id: 'user-image',
      threadId: 'thread-1',
      role: AiMessageRole.user,
      content: 'Analise esta execução',
      attachments: const [
        AiImageAttachment(
          id: 'image-1',
          path: 'missing-image-for-widget-test.jpg',
          mimeType: 'image/jpeg',
          fileName: 'execução.jpg',
          sizeBytes: 20,
        ),
      ],
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: message, showTimestamp: false)),
    );
    await tester.pump();

    expect(find.text('Analise esta execução'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
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

  testWidgets('composer can send images without typed text', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var sends = 0;
    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: false,
          images: [
            AiPendingImage(
              bytes: _tinyPng,
              mimeType: 'image/png',
              fileName: 'photo.png',
            ),
          ],
          onSend: () => sends++,
        ),
      ),
    );

    final send = find.byWidgetPredicate(
      (widget) => widget is IconButton && widget.tooltip == 'Enviar mensagem',
    );
    expect(tester.widget<IconButton>(send).onPressed, isNotNull);
    expect(find.byTooltip('Remover imagem'), findsOneWidget);
    await tester.tap(send);
    expect(sends, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('composer supports five image previews on a narrow screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final image = AiPendingImage(
      bytes: _tinyPng,
      mimeType: 'image/png',
      fileName: 'photo.png',
    );

    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: false,
          images: List.filled(5, image),
          onAddImages: () {},
          onSend: () {},
        ),
      ),
    );

    final addButton = find.ancestor(
      of: find.byIcon(Icons.add_photo_alternate_outlined),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(addButton).onPressed, isNull);
    expect(find.byTooltip('Remover imagem'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Widget _testApp(Widget child) => MaterialApp(
  locale: const Locale('pt'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
);
