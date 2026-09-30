import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/screens/settings/settings_preferences_controller.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// App-wide appearance preferences: theme mode, accent colour and language.
class GeneralSettingsScreen extends StatefulWidget {
  const GeneralSettingsScreen({super.key});

  @override
  State<GeneralSettingsScreen> createState() => _GeneralSettingsScreenState();
}

class _GeneralSettingsScreenState extends State<GeneralSettingsScreen> {
  final _controller = AppearanceController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _accentColorLabel(int index, AppLocalizations loc) {
    switch (index) {
      case 0:
        return loc.accentColorRed;
      case 1:
        return loc.accentColorDarkOrange;
      case 2:
        return loc.accentColorOrange;
      case 3:
        return loc.accentColorAmber;
      case 4:
        return loc.accentColorDeepPurple;
      case 5:
        return loc.accentColorDarkBlue;
      case 6:
        return loc.accentColorGraphite;
      case 7:
        return loc.accentColorForestGreen;
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: SettingsAppBar(title: loc.settingsGeneralTitle),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) {
          final themeMode = _controller.themeMode;
          final accentIndex = _controller.accentIndex;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // ===== APARÊNCIA =====
              AppSectionHeader(loc.settingsSectionAppearance, padding: AppSectionHeader.compactPadding),
              SettingsCard(
                title: loc.settingsThemeMode,
                icon: Icons.dark_mode_outlined,
                children: [
                  SettingsRadioOption(
                    icon: Icons.brightness_auto,
                    label: loc.settingsSystem,
                    subtitle: loc.settingsSystemSubtitle,
                    selected: themeMode == ThemeMode.system,
                    onTap: () => _controller.changeThemeMode(ThemeMode.system),
                  ),
                  const SettingsCardDivider(),
                  SettingsRadioOption(
                    icon: Icons.light_mode,
                    label: loc.settingsLight,
                    subtitle: loc.settingsLightSubtitle,
                    selected: themeMode == ThemeMode.light,
                    onTap: () => _controller.changeThemeMode(ThemeMode.light),
                  ),
                  const SettingsCardDivider(),
                  SettingsRadioOption(
                    icon: Icons.dark_mode,
                    label: loc.settingsDark,
                    subtitle: loc.settingsDarkSubtitle,
                    selected: themeMode == ThemeMode.dark,
                    onTap: () => _controller.changeThemeMode(ThemeMode.dark),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsCard(
                title: loc.settingsThemeColor,
                icon: Icons.palette_outlined,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(AccentColors.options.length, (i) {
                        final isSelected = accentIndex == i;
                        final color = AccentColors.options[i];
                        return SettingsColorSwatch(
                          color: color,
                          isSelected: isSelected,
                          onTap: () => _controller.changeAccentColor(i),
                        );
                      }),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AccentColors.options[accentIndex],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _accentColorLabel(accentIndex, loc),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SettingsCard(
                title: loc.settingsLanguage,
                icon: Icons.language_outlined,
                children: [
                  SettingsRadioOption(
                    icon: Icons.translate,
                    label: loc.settingsPortuguese,
                    subtitle: loc.settingsLanguageSubtitle,
                    selected:
                        Localizations.localeOf(context).languageCode == 'pt',
                    onTap: () =>
                        _controller.changeLocale(const Locale('pt', 'BR')),
                  ),
                  const SettingsCardDivider(),
                  SettingsRadioOption(
                    icon: Icons.translate,
                    label: loc.settingsEnglish,
                    subtitle: loc.settingsLanguageSubtitle,
                    selected:
                        Localizations.localeOf(context).languageCode == 'en',
                    onTap: () => _controller.changeLocale(const Locale('en')),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
