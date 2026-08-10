import 'package:flutter/material.dart';

import '../../main.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_provider.dart';
import '../../models/ai_settings.dart';
import '../../services/ai_service.dart';
import '../../state/ai_settings_notifier.dart';
import '../../utils/ai_error_localizer.dart';
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
          _buildProvidersCard(settings),
          SettingsSectionHeader(text: l10n.aiSettingsSectionBehavior),
          _buildContextModeCard(settings),
          _buildSystemPromptCard(),
          _buildAboutCard(),
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
                        : theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.check_circle_rounded
                        : Icons.cloud_outlined,
                    size: 18,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    p.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isActive)
                  TextButton(
                    onPressed: () => _notifier.setActiveProvider(p.id),
                    child: Text(l10n.aiSettingsActivate),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 48),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    p.baseUrl,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (p.selectedModel.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        l10n.aiSettingsModelValue(p.selectedModel),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _showEditProviderSheet(p),
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(l10n.aiSettingsEdit),
                ),
                TextButton.icon(
                  onPressed: () => _confirmRemove(p),
                  icon: const Icon(Icons.delete_outline_rounded, size: 16),
                  label: Text(l10n.aiSettingsRemove),
                ),
              ],
            ),
          ],
        ),
      );
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

  Widget _buildSystemPromptCard() {
    final l10n = AppLocalizations.of(context)!;
    return SettingsCard(
      title: l10n.aiSettingsSystemPrompt,
      icon: Icons.edit_note_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Text(
            l10n.aiSettingsSystemPromptHelp,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: _SystemPromptField(notifier: _notifier),
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

  void _showProviderEditor(AiProvider? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: _ProviderEditorSheet(notifier: _notifier, existing: existing),
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
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
            obscureText: true,
            decoration: InputDecoration(
              labelText: widget.existing == null
                  ? l10n.aiSettingsToken
                  : l10n.aiSettingsTokenHint,
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

class _SystemPromptField extends StatefulWidget {
  final AiSettingsNotifier notifier;
  const _SystemPromptField({required this.notifier});

  @override
  State<_SystemPromptField> createState() => _SystemPromptFieldState();
}

class _SystemPromptFieldState extends State<_SystemPromptField> {
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          maxLines: 12,
          minLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () async {
                await widget.notifier.resetSystemPrompt();
                if (!mounted) return;
                _controller.text = widget.notifier.systemPrompt;
                setState(() => _dirty = false);
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(l10n.aiSettingsRestoreDefault),
            ),
            const SizedBox(width: 8),
            FilledButton.tonal(
              onPressed: !_dirty
                  ? null
                  : () async {
                      await widget.notifier.setSystemPrompt(_controller.text);
                      if (!context.mounted) return;
                      final messenger = ScaffoldMessenger.of(context);
                      setState(() => _dirty = false);
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.aiSettingsSaved)),
                      );
                    },
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ],
    );
  }
}
