import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/models/ai_settings.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/screens/settings/ai_memory_screen.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/widgets/ai/ai_custom_instructions_sheet.dart';
import 'package:workout_notes/widgets/ai/ai_provider_editor_sheet.dart';
import 'package:workout_notes/widgets/ai/ai_provider_picker_sheet.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class AiSettingsScreen extends StatefulWidget {
  const AiSettingsScreen({super.key});

  @override
  State<AiSettingsScreen> createState() => _AiSettingsScreenState();
}

class _AiSettingsScreenState extends State<AiSettingsScreen> {
  late AiSettingsNotifier _notifier;

  @override
  void initState() {
    super.initState();
    _notifier = WorkoutNotesApp.aiSettings;
    _notifier.addListener(_onChange);
  }

  @override
  void dispose() {
    _notifier.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = _notifier.settings;
    return Scaffold(
      appBar: SettingsAppBar(title: l10n.aiSettingsTitle),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _buildConnectionStatus(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionConnection,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildProvidersCard(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionData,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildDataCard(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionPersonalize,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildPersonalizeCard(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionBehavior,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildResponseStyleCard(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionAppearance,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildAppearanceCard(settings),
          AppSectionHeader(
            l10n.aiSettingsSectionAdvanced,
            padding: AppSectionHeader.compactPadding,
          ),
          _buildAdvancedCard(settings),
          _buildAboutCard(),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(AiSettings settings) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final provider = settings.activeProvider;
    final isReady =
        settings.isConfigured &&
        provider != null &&
        provider.selectedModel.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isReady
            ? colors.primaryContainer.withAlpha(90)
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.outlineVariant.withAlpha(100)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isReady ? colors.primary : colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              isReady ? Icons.auto_awesome_rounded : Icons.tune_rounded,
              color: isReady ? colors.onPrimary : colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isReady ? l10n.aiSettingsReady : l10n.aiSettingsNeedsSetup,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  isReady
                      ? l10n.aiSettingsReadySubtitle(
                          provider.name,
                          provider.selectedModel,
                        )
                      : l10n.aiSettingsNeedsSetupSubtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProvidersCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      title: l10n.aiSettingsProvidersCard,
      icon: Icons.cloud_outlined,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text(
            l10n.aiSettingsProvidersHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (settings.providers.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: AppEmptyState(
              icon: Icons.cloud_off_rounded,
              title: l10n.aiSettingsNoProviders,
              subtitle: l10n.aiSettingsNoProvidersSubtitle,
            ),
          )
        else
          for (var i = 0; i < settings.providers.length; i++) ...[
            _buildProviderTile(settings.providers[i], settings),
            if (i < settings.providers.length - 1) const SettingsCardDivider(),
          ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
          child: Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _showAddProviderSheet,
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.aiSettingsAddProvider),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProviderTile(AiProvider p, AiSettings settings) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isActive = p.id == settings.activeProviderId;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isActive
                      ? theme.colorScheme.primary.withAlpha(25)
                      : theme.colorScheme.surfaceContainerHighest.withAlpha(
                          120,
                        ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isActive ? Icons.check_circle_rounded : Icons.cloud_outlined,
                  size: 18,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      p.baseUrl,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!isActive)
                TextButton(
                  onPressed: () => _notifier.setActiveProvider(p.id),
                  child: Text(l10n.aiSettingsActivate),
                )
              else
                Icon(
                  Icons.check_circle_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
              PopupMenuButton<String>(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                onSelected: (value) {
                  if (value == 'edit') _showEditProviderSheet(p);
                  if (value == 'remove') _confirmRemove(p);
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l10n.aiSettingsEdit),
                    ),
                  ),
                  PopupMenuItem(
                    value: 'remove',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        Icons.delete_outline_rounded,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        l10n.aiSettingsRemove,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showModelPicker(p),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.smart_toy_outlined,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.aiSettingsDefaultModel,
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                p.selectedModel.isEmpty
                                    ? l10n.aiSettingsNoModelSelected
                                    : p.selectedModel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
                if (p.lastCheck != null) _CheckSummary(check: p.lastCheck!),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResponseStyleCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      title: l10n.aiSettingsResponseStyle,
      icon: Icons.notes_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.aiSettingsResponseStyleHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < AiResponseStyle.values.length; i++) ...[
          SettingsRadioOption(
            icon: _responseStyleIcon(AiResponseStyle.values[i]),
            label: _responseStyleLabel(AiResponseStyle.values[i], l10n),
            subtitle: _responseStyleSubtitle(AiResponseStyle.values[i], l10n),
            selected: settings.responseStyle == AiResponseStyle.values[i],
            onTap: () => _notifier.setResponseStyle(AiResponseStyle.values[i]),
          ),
          if (i < AiResponseStyle.values.length - 1)
            const SettingsCardDivider(),
        ],
      ],
    );
  }

  IconData _responseStyleIcon(AiResponseStyle style) {
    switch (style) {
      case AiResponseStyle.concise:
        return Icons.short_text_rounded;
      case AiResponseStyle.balanced:
        return Icons.notes_rounded;
      case AiResponseStyle.detailed:
        return Icons.subject_rounded;
    }
  }

  String _responseStyleLabel(AiResponseStyle style, AppLocalizations l10n) {
    switch (style) {
      case AiResponseStyle.concise:
        return l10n.aiSettingsResponseConcise;
      case AiResponseStyle.balanced:
        return l10n.aiSettingsResponseBalanced;
      case AiResponseStyle.detailed:
        return l10n.aiSettingsResponseDetailed;
    }
  }

  String _responseStyleSubtitle(AiResponseStyle style, AppLocalizations l10n) {
    switch (style) {
      case AiResponseStyle.concise:
        return l10n.aiSettingsResponseConciseSubtitle;
      case AiResponseStyle.balanced:
        return l10n.aiSettingsResponseBalancedSubtitle;
      case AiResponseStyle.detailed:
        return l10n.aiSettingsResponseDetailedSubtitle;
    }
  }

  Future<void> _confirmRemove(AiProvider p) async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showConfirmDialog(
      context,
      title: l10n.aiSettingsRemoveConfirmTitle(p.name),
      message: l10n.aiSettingsRemoveConfirmBody,
      confirmLabel: l10n.aiSettingsRemove,
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (ok == true) {
      await _notifier.deleteProvider(p.id);
    }
  }

  Widget _buildAppearanceCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      children: [
        SettingsSwitchTile(
          icon: Icons.schedule_rounded,
          title: l10n.aiSettingsShowTimestamps,
          subtitle: l10n.aiSettingsShowTimestampsSubtitle,
          value: settings.showMessageTimestamps,
          onChanged: _notifier.setShowMessageTimestamps,
        ),
      ],
    );
  }

  Widget _buildAdvancedCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      children: [
        SettingsSwitchTile(
          icon: Icons.bug_report_outlined,
          title: l10n.aiSettingsDeveloperMode,
          subtitle: l10n.aiSettingsDeveloperModeSubtitle,
          value: settings.developerMode,
          onChanged: _notifier.setDeveloperMode,
        ),
      ],
    );
  }

  Widget _buildDataCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SettingsCard(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Text(
            l10n.aiSettingsDomainsHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final domain in AiToolDomain.optional) ...[
          SettingsSwitchTile(
            icon: _domainIcon(domain),
            title: _domainTitle(domain, l10n),
            subtitle: _domainSubtitle(domain, l10n),
            value: settings.enabledDomains.contains(domain),
            onChanged: (value) => _notifier.setDomainEnabled(domain, value),
          ),
          const SettingsCardDivider(),
        ],
        SettingsSwitchTile(
          icon: Icons.shield_outlined,
          title: l10n.aiSettingsDataSharing,
          subtitle: l10n.aiSettingsDataSharingSubtitle,
          value: settings.dataSharingAccepted,
          onChanged: _notifier.setDataSharingAccepted,
        ),
      ],
    );
  }

  IconData _domainIcon(AiToolDomain domain) {
    switch (domain) {
      case AiToolDomain.workouts:
        return Icons.fitness_center_rounded;
      case AiToolDomain.running:
        return Icons.directions_run_rounded;
      case AiToolDomain.sleep:
        return Icons.bedtime_outlined;
      case AiToolDomain.nutrition:
        return Icons.restaurant_outlined;
      case AiToolDomain.body:
        return Icons.monitor_weight_outlined;
      case AiToolDomain.goals:
        return Icons.flag_outlined;
      case AiToolDomain.planning:
        return Icons.event_note_rounded;
      case AiToolDomain.core:
        return Icons.psychology_alt_outlined;
    }
  }

  String _domainTitle(AiToolDomain domain, AppLocalizations l10n) {
    switch (domain) {
      case AiToolDomain.workouts:
        return l10n.aiSettingsDomainWorkouts;
      case AiToolDomain.running:
        return l10n.aiSettingsDomainRunning;
      case AiToolDomain.sleep:
        return l10n.aiSettingsDomainSleep;
      case AiToolDomain.nutrition:
        return l10n.aiSettingsDomainNutrition;
      case AiToolDomain.body:
        return l10n.aiSettingsDomainBody;
      case AiToolDomain.goals:
        return l10n.aiSettingsDomainGoals;
      case AiToolDomain.planning:
        return l10n.aiSettingsDomainPlanning;
      case AiToolDomain.core:
        return l10n.aiSettingsMemory;
    }
  }

  String _domainSubtitle(AiToolDomain domain, AppLocalizations l10n) {
    switch (domain) {
      case AiToolDomain.workouts:
        return l10n.aiSettingsDomainWorkoutsSubtitle;
      case AiToolDomain.running:
        return l10n.aiSettingsDomainRunningSubtitle;
      case AiToolDomain.sleep:
        return l10n.aiSettingsDomainSleepSubtitle;
      case AiToolDomain.nutrition:
        return l10n.aiSettingsDomainNutritionSubtitle;
      case AiToolDomain.body:
        return l10n.aiSettingsDomainBodySubtitle;
      case AiToolDomain.goals:
        return l10n.aiSettingsDomainGoalsSubtitle;
      case AiToolDomain.planning:
        return l10n.aiSettingsDomainPlanningSubtitle;
      case AiToolDomain.core:
        return l10n.aiSettingsMemorySubtitle;
    }
  }

  Widget _buildPersonalizeCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    final hasInstructions = settings.customInstructions.isNotEmpty;
    return SettingsCard(
      children: [
        SettingsLinkTile(
          icon: Icons.edit_note_rounded,
          title: l10n.aiSettingsCustomInstructions,
          subtitle: hasInstructions
              ? settings.customInstructions.replaceAll(RegExp(r'\s+'), ' ')
              : l10n.aiSettingsCustomInstructionsNotSet,
          onTap: _showCustomInstructionsEditor,
        ),
        const SettingsCardDivider(),
        SettingsLinkTile(
          icon: Icons.psychology_alt_outlined,
          title: l10n.aiSettingsMemory,
          subtitle: l10n.aiSettingsMemorySubtitle,
          onTap: () {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const AiMemoryScreen()));
          },
        ),
      ],
    );
  }

  Widget _buildAboutCard() {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      title: l10n.aiSettingsAbout,
      icon: Icons.info_outline_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(l10n.aiSettingsAboutBody),
        ),
      ],
    );
  }

  // ===========================================================================

  void _showAddProviderSheet() {
    _showProviderEditor(null);
  }

  void _showEditProviderSheet(AiProvider provider) {
    _showProviderEditor(provider);
  }

  void _showModelPicker(AiProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiProviderPickerSheet(
        notifier: _notifier,
        initialProviderId: provider.id,
      ),
    );
  }

  void _showProviderEditor(AiProvider? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: AiProviderEditorSheet(notifier: _notifier, existing: existing),
      ),
    );
  }

  void _showCustomInstructionsEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: AiCustomInstructionsSheet(notifier: _notifier),
      ),
    );
  }
}

/// One line under a provider: the outcome of its last connection test.
class _CheckSummary extends StatelessWidget {
  final AiProviderCheck check;
  const _CheckSummary({required this.check});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final ok = check.ok;
    final warn = ok && !check.toolsSupported;
    final color = !ok
        ? colors.error
        : warn
        ? colors.tertiary
        : colors.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 0, 0),
      child: Row(
        children: [
          Icon(
            !ok
                ? Icons.error_outline_rounded
                : warn
                ? Icons.warning_amber_rounded
                : Icons.check_circle_outline_rounded,
            size: 16,
            color: color,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              !ok
                  ? l10n.aiSettingsCheckFailed
                  : warn
                  ? l10n.aiSettingsCheckNoTools
                  : '${l10n.aiSettingsCheckOk} · '
                        '${l10n.aiSettingsCheckLatency(check.latencyMs)}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
