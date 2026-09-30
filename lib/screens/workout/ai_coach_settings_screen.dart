import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/screens/workout/ai_chat_screen.dart';
import 'package:workout_notes/screens/workout/ai_settings_screen.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// AI section of the settings hub: opens the coach chat (or its provider
/// setup when nothing is configured yet) and the provider settings.
class AiCoachSettingsScreen extends StatelessWidget {
  const AiCoachSettingsScreen({super.key});

  void _openAiCoach(BuildContext context) {
    final settings = WorkoutNotesApp.aiSettings;
    final loc = AppLocalizations.of(context)!;
    if (!settings.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(loc.aiCoachConfigureBeforeChat),
          duration: const Duration(seconds: 2),
        ),
      );
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const AiSettingsScreen()));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AiChatScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsAiTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ===== INTELIGÊNCIA ARTIFICIAL =====
          AppSectionHeader(loc.aiCoachSection, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.smart_toy_rounded,
                iconColor: theme.colorScheme.primary,
                title: loc.aiCoachEntry,
                subtitle: loc.aiCoachEntrySubtitle,
                onTap: () => _openAiCoach(context),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.tune_rounded,
                iconColor: theme.colorScheme.onSurfaceVariant,
                title: loc.aiCoachConfigureEntry,
                subtitle: loc.aiCoachConfigureEntrySubtitle,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
