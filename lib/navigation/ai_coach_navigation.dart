import 'package:flutter/material.dart';

/// Route categories used to control the global AI Coach FAB.
enum AiCoachRouteKind { normal, normalWithFab, activeWorkout, aiFlow }

/// Shared navigation utilities for surfaces that can open the AI Coach.
class AiCoachNavigation {
  AiCoachNavigation._();

  static final navigatorKey = GlobalKey<NavigatorState>();
  static final observer = AiCoachNavigationObserver();

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

/// Tracks the top route so widgets outside the Navigator can react to it.
class AiCoachNavigationObserver extends NavigatorObserver with ChangeNotifier {
  Route<dynamic>? _topRoute;

  AiCoachRouteKind get topRouteKind {
    final routeName = _topRoute?.settings.name;
    return AiCoachRouteKind.values.firstWhere(
      (kind) => kind.name == routeName,
      orElse: () => AiCoachRouteKind.normal,
    );
  }

  bool get shouldHideFab =>
      topRouteKind == AiCoachRouteKind.activeWorkout ||
      topRouteKind == AiCoachRouteKind.aiFlow;

  bool get shouldPlaceFabLeft => topRouteKind == AiCoachRouteKind.normalWithFab;

  void _setTopRoute(Route<dynamic>? route) {
    if (identical(_topRoute, route)) return;
    _topRoute = route;
    notifyListeners();
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _setTopRoute(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _setTopRoute(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _setTopRoute(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didRemove(route, previousRoute);
    if (identical(route, _topRoute)) _setTopRoute(previousRoute);
  }
}
