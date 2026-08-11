import 'package:flutter/material.dart';

/// Route categories retained as semantic names for important app flows.
enum AiCoachRouteKind { normal, normalWithFab, activeWorkout, aiFlow }

/// Shared navigation utilities for surfaces that can open the AI Coach.
class AiCoachNavigation {
  AiCoachNavigation._();

  static final navigatorKey = GlobalKey<NavigatorState>();

  static MaterialPageRoute<T> route<T>({
    required WidgetBuilder builder,
    AiCoachRouteKind kind = AiCoachRouteKind.normal,
  }) {
    return MaterialPageRoute<T>(
      settings: RouteSettings(name: kind.name),
      builder: builder,
    );
  }
}
