import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:workout_notes/utils/clock_format.dart';

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR', null));

  Future<String> render(
    WidgetTester tester, {
    required bool use24Hour,
    Locale locale = const Locale('en'),
  }) async {
    late String text;
    await tester.pumpWidget(
      MaterialApp(
        locale: locale,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: [locale],
        home: MediaQuery(
          data: MediaQueryData(alwaysUse24HourFormat: use24Hour),
          child: Builder(
            builder: (context) {
              text = ClockFormat.format(context, DateTime(2026, 3, 5, 15, 5));
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    return text;
  }

  testWidgets('24 hour setting prints HH:mm', (tester) async {
    expect(await render(tester, use24Hour: true), '15:05');
  });

  testWidgets('12 hour setting prints the locale 12 hour clock', (
    tester,
  ) async {
    final text = await render(tester, use24Hour: false);
    expect(text.replaceAll(RegExp(r'\s'), ' '), '3:05 PM');
  });

  testWidgets('Portuguese 24 hour clock', (tester) async {
    expect(
      await render(tester, use24Hour: true, locale: const Locale('pt', 'BR')),
      '15:05',
    );
  });
}
