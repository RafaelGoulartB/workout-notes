import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/widgets/ai/ai_chat_input_bar.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';

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

  testWidgets('a cut-off answer shows a notice, a complete one does not', (
    tester,
  ) async {
    AiChatMessage answer({required bool cutOff}) => AiChatMessage(
      id: 'm-$cutOff',
      threadId: 't',
      role: AiMessageRole.assistant,
      content: 'Resposta pela metade',
      createdAt: DateTime(2026, 9, 30),
      providerExtras: {if (cutOff) kAiCutOffExtra: true},
    );

    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: answer(cutOff: true))),
    );
    expect(find.text('Esta resposta foi cortada antes do fim.'), findsOneWidget);

    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: answer(cutOff: false))),
    );
    expect(find.text('Esta resposta foi cortada antes do fim.'), findsNothing);
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

  testWidgets('a user turn that did not finish shows its status and retry', (
    tester,
  ) async {
    var retries = 0;
    final message = AiChatMessage(
      id: 'user-stopped',
      threadId: 'thread-1',
      role: AiMessageRole.user,
      content: 'Analise meu treino',
      turnStatus: AiTurnStatus.cancelled,
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(
      _testApp(
        AiMessageBubble(
          message: message,
          showTimestamp: false,
          onRetryTurn: () => retries++,
        ),
      ),
    );

    expect(find.text('Interrompido por você'), findsOneWidget);
    await tester.tap(find.text('Tentar de novo'));
    expect(retries, 1);

    final interrupted = message.copyWith(turnStatus: AiTurnStatus.interrupted);
    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: interrupted, showTimestamp: false)),
    );
    expect(find.text('Interrompido'), findsOneWidget);
    // No retry unless the screen offers one (only the last message).
    expect(find.text('Tentar de novo'), findsNothing);

    final done = message.copyWith(turnStatus: AiTurnStatus.done);
    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: done, showTimestamp: false)),
    );
    expect(find.text('Interrompido'), findsNothing);
    expect(find.text('Interrompido por você'), findsNothing);
  });

  testWidgets('markdown never loads images and links only show their address', (
    tester,
  ) async {
    final message = AiChatMessage(
      id: 'assistant-md',
      threadId: 'thread-1',
      role: AiMessageRole.assistant,
      content:
          '![gráfico de sono](https://example.com/chart.png)\n\n'
          'Veja [o guia](https://example.com/guia) agora.',
      createdAt: DateTime(2026, 8, 10, 20),
    );

    await tester.pumpWidget(
      _testApp(AiMessageBubble(message: message, showTimestamp: false)),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.text('gráfico de sono'), findsOneWidget);

    // Tapping the link opens nothing: it shows the address with a copy action.
    final selectable = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.textSpan?.toPlainText().contains('o guia') ?? false),
    );
    expect(selectable, findsOneWidget);
    final span = _findLinkSpan(
      tester.widget<SelectableText>(selectable).textSpan!,
    );
    expect(span, isNotNull);
    (span!.recognizer! as TapGestureRecognizer).onTap!();
    await tester.pump();
    expect(find.text('https://example.com/guia'), findsOneWidget);
    expect(find.text('Copiar'), findsOneWidget);
  });

  testWidgets('composer swaps send for a stop button while a turn runs', (
    tester,
  ) async {
    final controller = TextEditingController(text: 'pergunta');
    addTearDown(controller.dispose);
    var stops = 0;
    var sends = 0;
    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: true,
          onStop: () => stops++,
          onSend: () => sends++,
        ),
      ),
    );

    expect(find.byTooltip('Enviar mensagem'), findsNothing);
    expect(find.bySemanticsLabel('Parar a resposta'), findsOneWidget);
    // The field is locked while the turn runs.
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.byTooltip('Parar'));
    expect(stops, 1);
    expect(sends, 0);

    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: true,
          stopping: true,
          onStop: () => stops++,
          onSend: () => sends++,
        ),
      ),
    );
    expect(find.byTooltip('Parar'), findsNothing);
  });

  testWidgets('composer waits for a turn that runs in another conversation', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var opened = 0;
    await tester.pumpWidget(
      _testApp(
        AiChatInputBar(
          controller: controller,
          enabled: true,
          sending: true,
          busyElsewhere: true,
          onStop: () {},
          onOpenBusyConversation: () => opened++,
          onSend: () {},
        ),
      ),
    );

    expect(
      find.text('O treinador está respondendo em outra conversa'),
      findsWidgets,
    );
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    await tester.tap(find.text('Abrir'));
    expect(opened, 1);
  });

  testWidgets('removing a pending image has a 48 dp touch target', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    var removed = -1;
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
          onRemoveImage: (index) => removed = index,
          onSend: () {},
        ),
      ),
    );

    final target = find.ancestor(
      of: find.byIcon(Icons.close_rounded),
      matching: find.byType(InkResponse),
    );
    final size = tester.getSize(target);
    expect(size.width, greaterThanOrEqualTo(48));
    expect(size.height, greaterThanOrEqualTo(48));
    await tester.tap(find.byTooltip('Remover imagem'));
    expect(removed, 0);
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

TextSpan? _findLinkSpan(InlineSpan root) {
  TextSpan? found;
  root.visitChildren((span) {
    if (span is TextSpan && span.recognizer is TapGestureRecognizer) {
      found = span;
      return false;
    }
    return true;
  });
  return found;
}
