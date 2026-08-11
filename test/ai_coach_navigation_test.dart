import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';

void main() {
  test('AI Coach routes retain their semantic route kind', () {
    final route = AiCoachNavigation.route<void>(
      kind: AiCoachRouteKind.aiFlow,
      builder: (_) => const SizedBox(),
    );

    expect(route.settings.name, AiCoachRouteKind.aiFlow.name);
  });
}
