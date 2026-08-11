import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/navigation/ai_coach_navigation.dart';
import 'package:workout_notes/screens/workout/ai_chat_screen.dart';

/// Compact AI Coach entry point for primary dashboard app bars.
///
/// This widget is intentionally added only to the workout, sleep and
/// nutrition root screens so it never floats above content or leaks into
/// secondary flows.
class AiCoachHeaderButton extends StatelessWidget {
  const AiCoachHeaderButton({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: l10n.aiCoachHeaderTooltip,
        icon: const Icon(Icons.auto_awesome_rounded, size: 20),
        onPressed: () {
          Navigator.of(context).push(
            AiCoachNavigation.route(
              kind: AiCoachRouteKind.aiFlow,
              builder: (_) => const AiChatScreen(),
            ),
          );
        },
      ),
    );
  }
}
