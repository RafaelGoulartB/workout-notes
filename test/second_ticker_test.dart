import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/widgets/second_ticker.dart';
import 'package:workout_notes/widgets/workout/active_session_banner.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SecondTicker', () {
    testWidgets('rebuilds only its own subtree once a second', (tester) async {
      var parentBuilds = 0;
      var tickBuilds = 0;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              parentBuilds++;
              return SecondTicker(
                builder: (_) {
                  tickBuilds++;
                  return const SizedBox();
                },
              );
            },
          ),
        ),
      );
      expect(parentBuilds, 1);
      expect(tickBuilds, 1);

      await tester.pump(const Duration(seconds: 3));
      // pump(duration) fires the periodic timer once per elapsed second.
      expect(tickBuilds, greaterThan(1));
      expect(parentBuilds, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('stops while its tab is hidden (TickerMode off)', (
      tester,
    ) async {
      var tickBuilds = 0;
      Widget build(bool enabled) => _host(
        TickerMode(
          enabled: enabled,
          child: SecondTicker(
            builder: (_) {
              tickBuilds++;
              return const SizedBox();
            },
          ),
        ),
      );

      await tester.pumpWidget(build(false));
      final afterFirstBuild = tickBuilds;
      await tester.pump(const Duration(seconds: 5));
      expect(tickBuilds, afterFirstBuild);

      // Visible again: it ticks again.
      await tester.pumpWidget(build(true));
      final visible = tickBuilds;
      await tester.pump(const Duration(seconds: 2));
      expect(tickBuilds, greaterThan(visible));

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('ActiveSessionBanner', () {
    testWidgets('its subtitle follows the listenable without the parent', (
      tester,
    ) async {
      final notifier = ValueNotifier<int>(1);
      addTearDown(notifier.dispose);
      var parentBuilds = 0;
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              parentBuilds++;
              return ActiveSessionBanner(
                background: Colors.blue,
                foreground: Colors.white,
                title: 'Run',
                refresh: notifier,
                subtitle: () => 'km ${notifier.value}',
                action: const SizedBox(),
                onTap: () {},
              );
            },
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('km 1'), findsOneWidget);

      notifier.value = 2;
      await tester.pump();
      expect(find.text('km 2'), findsOneWidget);
      expect(parentBuilds, 1);

      await tester.pumpWidget(const SizedBox());
    });
  });
}
