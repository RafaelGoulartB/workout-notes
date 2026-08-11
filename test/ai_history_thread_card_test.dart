import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/widgets/ai/ai_history_thread_card.dart';

void main() {
  testWidgets('history card is readable on a narrow mobile viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final thread = _thread(
      title: 'Recuperação, sono e evolução desta semana',
      preview:
          'Seu sono apresentou boa regularidade, mas ainda há poucos registros.',
    );

    await tester.pumpWidget(
      _testApp(
        Padding(
          padding: const EdgeInsets.all(12),
          child: AiHistoryThreadCard(
            thread: thread,
            timestamp: '20:16',
            preview: thread.lastMessagePreview,
            onTap: () {},
            onRename: () {},
            onTogglePinned: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.textContaining('Recuperação, sono'), findsOneWidget);
    expect(find.text('20:16'), findsOneWidget);
    expect(find.textContaining('Seu sono apresentou'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('history card menu exposes rename, pin and delete actions', (
    tester,
  ) async {
    var renamed = false;
    var pinned = false;
    var deleted = false;
    await tester.pumpWidget(
      _testApp(
        AiHistoryThreadCard(
          thread: _thread(title: 'Minha conversa'),
          timestamp: 'ontem',
          preview: null,
          onTap: () {},
          onRename: () => renamed = true,
          onTogglePinned: () => pinned = true,
          onDelete: () => deleted = true,
        ),
      ),
    );

    Future<void> choose(String label) async {
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    await choose('Renomear');
    expect(renamed, isTrue);
    await choose('Fixar');
    expect(pinned, isTrue);
    await choose('Excluir');
    expect(deleted, isTrue);
  });
}

AiChatThread _thread({
  required String title,
  String? preview,
  bool pinned = false,
}) => AiChatThread(
  id: 'thread-1',
  title: title,
  createdAt: DateTime(2026, 8, 10, 19),
  updatedAt: DateTime(2026, 8, 10, 20, 16),
  lastMessagePreview: preview,
  isPinned: pinned,
);

Widget _testApp(Widget child) => MaterialApp(
  locale: const Locale('pt'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);
