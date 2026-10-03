import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
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

  testWidgets('dates follow the app language', (tester) async {
    await initializeDateFormatting('pt_BR');
    await initializeDateFormatting('en');
    final now = DateTime.now();
    final old = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 20));
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
      12,
    ).subtract(const Duration(days: 1));
    await tester.runAsync(() async {
      final repo = DatabaseHelper.instance.aiChatRepo;
      await repo.upsertAiChatThread(
        id: 'old',
        title: 'Conversa antiga',
        createdAt: old,
        updatedAt: old,
      );
      await repo.upsertAiChatThread(
        id: 'recent',
        title: 'Conversa de ontem',
        createdAt: yesterday,
        updatedAt: yesterday,
      );
      await AiChatService.instance.newChat();
      await AiChatService.instance.refreshThreads();
    });

    Future<void> open(String locale) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale(locale),
          home: const AiChatHistoryScreen(),
        ),
      );
      await tester.pump();
    }

    String two(int n) => n.toString().padLeft(2, '0');
    await open('pt');
    expect(find.text('${two(old.day)}/${two(old.month)}'), findsOneWidget);
    expect(find.text('ontem'), findsOneWidget);

    await open('en');
    expect(find.text('${old.month}/${old.day}'), findsOneWidget);
    expect(find.text('yesterday'), findsOneWidget);
  });
}
