import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('en'),
  home: Scaffold(body: child),
);

void main() {
  testWidgets('FadeSlideIn fades in once and is not replayed by rebuilds', (
    tester,
  ) async {
    Widget build(String text) => _host(
      FadeSlideIn(
        delay: const Duration(milliseconds: 100),
        slideY: 0.05,
        child: Text(text),
      ),
    );
    double opacity() => tester
        .widget<FadeTransition>(find.byType(FadeTransition).last)
        .opacity
        .value;

    await tester.pumpWidget(build('a'));
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(opacity(), 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(opacity(), 1);
    await tester.pumpWidget(build('b'));
    expect(opacity(), 1);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('AppPulsingDot animates and stops when its ticker is muted', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const AppPulsingDot(color: Colors.red)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpWidget(
      _host(
        const TickerMode(
          enabled: false,
          child: AppPulsingDot(color: Colors.red),
        ),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('showConfirmDialog resolves true only on confirm', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showConfirmDialog(
              context,
              title: 'Delete?',
              message: 'Really',
              confirmLabel: 'Yes',
              destructive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Delete?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yes'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}
