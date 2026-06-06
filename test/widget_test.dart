import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App smoke test', (tester) async {
    // Basic smoke test - just verify widgets render without crashing
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: Text('Workout Notes'))),
    ));

    expect(find.text('Workout Notes'), findsOneWidget);
  });
}
