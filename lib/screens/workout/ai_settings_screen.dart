import 'package:flutter/material.dart';

import '../../main.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_provider.dart';
import '../../models/ai_settings.dart';
import '../../services/ai_service.dart';
import '../../state/ai_settings_notifier.dart';
import '../../utils/ai_error_localizer.dart';
import '../../widgets/ai/ai_provider_picker_sheet.dart';
import '../../widgets/empty_state_placeholder.dart';
import '../../widgets/settings/settings.dart';

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
          SettingsSectionHeader(text: l10n.aiSettingsSectionConnection),
          _buildProvidersCard(settings),
          SettingsSectionHeader(text: l10n.aiSettingsSectionBehavior),
          _buildResponseStyleCard(settings),
          _buildContextModeCard(settings),
          SettingsSectionHeader(text: l10n.aiSettingsSectionAppearance),
          _buildAppearanceCard(settings),
          SettingsSectionHeader(text: l10n.aiSettingsSectionAdvanced),
          _buildAdvancedCard(),
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
            child: EmptyStatePlaceholder(
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
    final ok = await SettingsConfirmDialog.show(
      context: context,
      title: l10n.aiSettingsRemoveConfirmTitle(p.name),
      message: l10n.aiSettingsRemoveConfirmBody,
      confirmLabel: l10n.aiSettingsRemove,
      cancelLabel: l10n.commonCancel,
    );
    if (ok == true) {
      await _notifier.deleteProvider(p.id);
    }
  }

  Widget _buildContextModeCard(AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      title: l10n.aiSettingsContextMode,
      icon: Icons.tune_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            l10n.aiSettingsContextModeHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (var i = 0; i < AiContextMode.values.length; i++) ...[
          SettingsRadioOption(
            icon: _modeIcon(AiContextMode.values[i]),
            label: _modeLabel(AiContextMode.values[i], l10n),
            subtitle: _modeSubtitle(AiContextMode.values[i], l10n),
            selected: settings.contextMode == AiContextMode.values[i],
            onTap: () => _notifier.setContextMode(AiContextMode.values[i]),
          ),
          if (i < AiContextMode.values.length - 1) const SettingsCardDivider(),
        ],
      ],
    );
  }

  IconData _modeIcon(AiContextMode mode) {
    switch (mode) {
      case AiContextMode.minimal:
        return Icons.eco_outlined;
      case AiContextMode.standard:
        return Icons.balance_outlined;
      case AiContextMode.full:
        return Icons.dashboard_outlined;
    }
  }

  String _modeLabel(AiContextMode mode, AppLocalizations l10n) {
    switch (mode) {
      case AiContextMode.minimal:
        return l10n.aiSettingsContextModeMinimal;
      case AiContextMode.standard:
        return l10n.aiSettingsContextModeStandard;
      case AiContextMode.full:
        return l10n.aiSettingsContextModeFull;
    }
  }

  String _modeSubtitle(AiContextMode mode, AppLocalizations l10n) {
    switch (mode) {
      case AiContextMode.minimal:
        return l10n.aiSettingsContextModeMinimalSubtitle;
      case AiContextMode.standard:
        return l10n.aiSettingsContextModeStandardSubtitle;
      case AiContextMode.full:
        return l10n.aiSettingsContextModeFullSubtitle;
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
        const SettingsCardDivider(),
        SettingsSwitchTile(
          icon: Icons.data_object_rounded,
          title: l10n.aiSettingsExpandTools,
          subtitle: l10n.aiSettingsExpandToolsSubtitle,
          value: settings.autoExpandToolDetails,
          onChanged: _notifier.setAutoExpandToolDetails,
        ),
        const SettingsCardDivider(),
        SettingsSwitchTile(
          icon: Icons.smart_toy_outlined,
          title: l10n.aiSettingsFabTitle,
          subtitle: l10n.aiSettingsFabSubtitle,
          value: _notifier.fabEnabled,
          onChanged: _notifier.setFabEnabled,
        ),
      ],
    );
  }

  Widget _buildAdvancedCard() {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      children: [
        SettingsLinkTile(
          icon: Icons.edit_note_rounded,
          title: l10n.aiSettingsSystemPrompt,
          subtitle: l10n.aiSettingsSystemPromptSubtitle,
          onTap: _showSystemPromptEditor,
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
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ProviderEditorSheet(notifier: _notifier, existing: existing),
      ),
    );
  }

  void _showSystemPromptEditor() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _SystemPromptEditorSheet(notifier: _notifier),
      ),
    );
  }
}

class _ProviderEditorSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;
  final AiProvider? existing;
  const _ProviderEditorSheet({required this.notifier, this.existing});

  @override
  State<_ProviderEditorSheet> createState() => _ProviderEditorSheetState();
}

class _ProviderEditorSheetState extends State<_ProviderEditorSheet> {
  late TextEditingController _name;
  late TextEditingController _baseUrl;
  late TextEditingController _token;
  bool _saving = false;
  bool _showToken = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _baseUrl = TextEditingController(
      text: widget.existing?.baseUrl ?? 'https://api.openai.com/v1',
    );
    _token = TextEditingController();
  }

  @override
  void dispose() {
    _name.dispose();
    _baseUrl.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            widget.existing == null
                ? l10n.aiSettingsNewProvider
                : l10n.aiSettingsEditProvider,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsProviderName,
              hintText: l10n.aiSettingsNameHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsBaseUrl,
              hintText: l10n.aiSettingsBaseUrlHint,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            obscureText: !_showToken,
            enableSuggestions: false,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: widget.existing == null
                  ? l10n.aiSettingsToken
                  : l10n.aiSettingsTokenHint,
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(
                  _showToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _onSave,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.commonSave),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    final name = _name.text.trim();
    final baseUrl = AiService.normalizeBaseUri(_baseUrl.text.trim());
    final token = _token.text.trim();
    if (name.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context)!.aiSettingsNameRequired,
      );
      return;
    }
    if (baseUrl.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context)!.aiSettingsBaseUrlRequired,
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.existing == null) {
        await widget.notifier.addProvider(
          name: name,
          baseUrl: baseUrl,
          token: token.isEmpty ? null : token,
        );
      } else {
        final updated = widget.existing!.copyWith(name: name, baseUrl: baseUrl);
        await widget.notifier.updateProvider(
          updated,
          token: token.isEmpty ? null : token,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() {
        _saving = false;
        _error = localizeAiError(e, AppLocalizations.of(context)!);
      });
    }
  }
}

class _SystemPromptEditorSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;
  const _SystemPromptEditorSheet({required this.notifier});

  @override
  State<_SystemPromptEditorSheet> createState() =>
      _SystemPromptEditorSheetState();
}

class _SystemPromptEditorSheetState extends State<_SystemPromptEditorSheet> {
  late TextEditingController _controller;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.notifier.systemPrompt);
    _controller.addListener(() {
      if (!_dirty) setState(() => _dirty = true);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: .9,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.aiSettingsSystemPrompt,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiSettingsSystemPromptHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                textAlignVertical: TextAlignVertical.top,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await widget.notifier.resetSystemPrompt();
                  if (!mounted) return;
                  _controller.text = widget.notifier.systemPrompt;
                  setState(() => _dirty = false);
                },
                icon: const Icon(Icons.restart_alt_rounded, size: 18),
                label: Text(l10n.aiSettingsRestoreDefault),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: !_dirty
                      ? null
                      : () async {
                          await widget.notifier.setSystemPrompt(
                            _controller.text,
                          );
                          if (!context.mounted) return;
                          Navigator.of(context).pop();
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.aiSettingsSaved)),
                          );
                        },
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
