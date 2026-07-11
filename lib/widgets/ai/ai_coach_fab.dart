import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../navigation/ai_coach_navigation.dart';
import '../../state/ai_settings_notifier.dart';

/// Global entry point for the AI Coach, rendered above the app Navigator.
class AiCoachFab extends StatelessWidget {
  final VoidCallback onPressed;
  final AiSettingsNotifier settings;

  const AiCoachFab({
    super.key,
    required this.onPressed,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AnimatedBuilder(
      animation: Listenable.merge([AiCoachNavigation.observer, settings]),
      builder: (context, _) {
        final visible =
            settings.fabEnabled && !AiCoachNavigation.observer.shouldHideFab;
        final placeLeft = AiCoachNavigation.observer.shouldPlaceFabLeft;
        return AnimatedPositioned(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          left: placeLeft ? 16 : null,
          right: placeLeft ? null : 16,
          bottom: 16,
          child: SafeArea(
            child: IgnorePointer(
              ignoring: !visible,
              child: AnimatedScale(
                duration: const Duration(milliseconds: 180),
                scale: visible ? 1 : 0,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: visible ? 1 : 0,
                  child: FloatingActionButton(
                    heroTag: 'ai_coach_global_fab',
                    tooltip: l10n.aiCoachFabTooltip,
                    onPressed: onPressed,
                    child: const Icon(Icons.smart_toy_rounded),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
