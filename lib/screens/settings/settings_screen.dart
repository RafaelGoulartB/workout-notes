import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/screens/settings/ai_coach_settings_screen.dart';
import 'package:workout_notes/screens/settings/data_privacy_screen.dart';
import 'package:workout_notes/screens/settings/general_settings_screen.dart';
import 'package:workout_notes/screens/nutrition/nutrition_settings_screen.dart';
import 'package:workout_notes/screens/settings/plan_settings_screen.dart';
import 'package:workout_notes/screens/sleep/sleep_settings_screen.dart';
import 'package:workout_notes/screens/settings/workout_settings_screen.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Application-wide settings entry point. The same screen is opened from the
/// workout, sleep and nutrition tabs so global preferences never appear to
/// belong to one tracking area.
class AppSettingsScreen extends StatelessWidget {
  const AppSettingsScreen({super.key});

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          AppSectionHeader(loc.settingsAppPreferencesSection, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.tune_rounded,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsGeneralTitle,
                subtitle: loc.settingsGeneralSubtitle,
                onTap: () => _open(context, const GeneralSettingsScreen()),
              ),
            ],
          ),
          AppSectionHeader(loc.settingsBySectionTitle, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.fitness_center_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabWorkout,
                subtitle: loc.settingsWorkoutSubtitle,
                onTap: () => _open(context, const WorkoutSettingsScreen()),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.nightlight_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabSleep,
                subtitle: loc.settingsSleepSubtitle,
                onTap: () => _open(context, const SleepSettingsScreen()),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.restaurant_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabNutrition,
                subtitle: loc.settingsNutritionSubtitle,
                onTap: () => _open(
                  context,
                  NutritionSettingsScreen(
                    repository: DatabaseHelper.instance.nutritionRepo,
                  ),
                ),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.view_timeline_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.tabPlan,
                subtitle: loc.settingsPlanSubtitle,
                onTap: () => _open(context, const PlanSettingsScreen()),
              ),
            ],
          ),
          AppSectionHeader(loc.settingsResourcesSection, padding: AppSectionHeader.compactPadding),
          SettingsCard(
            children: [
              SettingsLinkTile(
                icon: Icons.smart_toy_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsAiTitle,
                subtitle: loc.settingsAiSubtitle,
                onTap: () => _open(context, const AiCoachSettingsScreen()),
              ),
              const SettingsCardDivider(),
              SettingsLinkTile(
                icon: Icons.shield_outlined,
                iconColor: theme.colorScheme.primary,
                title: loc.settingsDataPrivacyTitle,
                subtitle: loc.settingsDataPrivacySubtitle,
                onTap: () => _open(context, const DataPrivacyScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
