import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/widgets/settings/settings.dart';

/// Plan section preferences. Currently controls whether the Plan tab is
/// shown in the main navigation bar.
class PlanSettingsScreen extends StatefulWidget {
  const PlanSettingsScreen({super.key});

  @override
  State<PlanSettingsScreen> createState() => _PlanSettingsScreenState();
}

class _PlanSettingsScreenState extends State<PlanSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WorkoutNotesApp.sections.addListener(_onSectionsChanged);
  }

  @override
  void dispose() {
    WorkoutNotesApp.sections.removeListener(_onSectionsChanged);
    super.dispose();
  }

  void _onSectionsChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsPlanTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          SettingsSectionHeader(text: loc.settingsSectionPlan),
          SettingsCard(
            children: [
              SettingsSwitchTile(
                icon: Icons.view_timeline_outlined,
                title: loc.settingsPlanSectionToggle,
                subtitle: loc.settingsPlanSectionToggleBody,
                value: WorkoutNotesApp.sections.planEnabled,
                onChanged: WorkoutNotesApp.sections.setPlanEnabled,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
