import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';

void main() {
  test('observer hides the FAB only for active workouts and AI routes', () {
    final observer = AiCoachNavigationObserver();
    final normal = AiCoachNavigation.route<void>(
      builder: (_) => const SizedBox(),
    );
    final activeWorkout = AiCoachNavigation.route<void>(
      kind: AiCoachRouteKind.activeWorkout,
      builder: (_) => const SizedBox(),
    );
    final aiFlow = AiCoachNavigation.route<void>(
      kind: AiCoachRouteKind.aiFlow,
      builder: (_) => const SizedBox(),
    );

    observer.didPush(normal, null);
    expect(observer.shouldHideFab, isFalse);

    observer.didPush(activeWorkout, normal);
    expect(observer.shouldHideFab, isTrue);

    observer.didPop(activeWorkout, normal);
    expect(observer.shouldHideFab, isFalse);

    observer.didPush(aiFlow, normal);
    expect(observer.shouldHideFab, isTrue);

    observer.didPop(aiFlow, normal);
    observer.didPush(
      AiCoachNavigation.route<void>(
        kind: AiCoachRouteKind.normalWithFab,
        builder: (_) => const SizedBox(),
      ),
      normal,
    );
    expect(observer.shouldHideFab, isFalse);
    expect(observer.shouldPlaceFabLeft, isTrue);
  });
}
