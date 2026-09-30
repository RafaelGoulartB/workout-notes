import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/ai/ai_chat_history_screen.dart';
import 'package:workout_notes/state/ai_chat_service.dart';

import 'support/ai_test_db.dart';

void main() {
  setUp(installAiTestDb);
  tearDown(uninstallAiTestDb);

  testWidgets('search reaches a conversation outside the loaded pages', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final repo = DatabaseHelper.instance.aiChatRepo;
      final base = DateTime.now().subtract(const Duration(days: 30));
      for (var i = 0; i < 130; i++) {
        await repo.upsertAiChatThread(
          id: 't$i',
          title: i == 0 ? 'Plano de creatina antigo' : 'Conversa $i',
          createdAt: base,
          updatedAt: base.add(Duration(minutes: i)),
        );
      }
      await AiChatService.instance.newChat();
      await AiChatService.instance.refreshThreads();
    });
    expect(AiChatService.instance.state.threads, hasLength(100));

    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('en'),
        home: AiChatHistoryScreen(),
      ),
    );
    await tester.pump();

    // The counter reports every stored conversation, not the loaded page.
    expect(find.text('130 conversations'), findsOneWidget);
    expect(find.text('Plano de creatina antigo'), findsNothing);

    await tester.enterText(find.byType(TextField), 'creatina');
    await tester.pump(const Duration(milliseconds: 400));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.text('Plano de creatina antigo'), findsOneWidget);
    expect(find.text('1 conversation'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '');
    await tester.pump();
    expect(find.text('130 conversations'), findsOneWidget);
  });
}
