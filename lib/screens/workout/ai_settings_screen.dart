import 'package:flutter/material.dart';

import '../../main.dart';
import '../../l10n/app_localizations.dart';
import '../../models/ai_provider.dart';
import '../../models/ai_settings.dart';
import '../../services/ai_service.dart';
import '../../state/ai_settings_notifier.dart';
import '../../utils/ai_error_localizer.dart';
import '../../widgets/empty_state_placeholder.dart';

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
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final settings = _notifier.settings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildProvidersCard(theme, settings),
          const SizedBox(height: 16),
          _buildContextModeCard(theme, settings),
          const SizedBox(height: 16),
          _buildSystemPromptCard(theme),
          const SizedBox(height: 16),
          _buildAboutCard(theme),
        ],
      ),
    );
  }

  Widget _buildProvidersCard(ThemeData theme, AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.aiSettingsProvidersCard,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiSettingsProvidersHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (settings.providers.isEmpty)
              EmptyStatePlaceholder(
                icon: Icons.cloud_off_rounded,
                title: l10n.aiSettingsNoProviders,
                subtitle: l10n.aiSettingsNoProvidersSubtitle,
              )
            else
              ...settings.providers.map((p) => _buildProviderTile(p, settings)),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _showAddProviderSheet(),
                icon: const Icon(Icons.add_rounded),
                label: Text(l10n.aiSettingsAddProvider),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderTile(AiProvider p, AiSettings settings) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isActive = p.id == settings.activeProviderId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive
            ? theme.colorScheme.primaryContainer.withAlpha(80)
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant,
          width: isActive ? 1.5 : 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isActive ? Icons.check_circle_rounded : Icons.cloud_outlined,
                size: 18,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  p.name,
                  style: theme.textTheme.titleSmall,
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
          Text(
            p.baseUrl,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (p.selectedModel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.aiSettingsModelValue(p.selectedModel),
                style: theme.textTheme.bodySmall,
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
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: Text(l10n.aiSettingsRemoveConfirmTitle(p.name)),
                      content: Text(l10n.aiSettingsRemoveConfirmBody),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: Text(l10n.commonCancel),
                        ),
                        FilledButton.tonal(
                          onPressed: () => Navigator.pop(context, true),
                          child: Text(l10n.aiSettingsRemove),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _notifier.deleteProvider(p.id);
                  }
                },
                icon: const Icon(Icons.delete_outline_rounded, size: 16),
                label: Text(l10n.aiSettingsRemove),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContextModeCard(ThemeData theme, AiSettings settings) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.aiSettingsContextMode,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiSettingsContextModeHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            for (final mode in AiContextMode.values)
              RadioListTile<AiContextMode>(
                value: mode,
                groupValue: settings.contextMode,
                title: Text(_modeLabel(mode, l10n)),
                subtitle: Text(_modeSubtitle(mode, l10n)),
                onChanged: (v) {
                  if (v != null) _notifier.setContextMode(v);
                },
              ),
          ],
        ),
      ),
    );
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

  Widget _buildSystemPromptCard(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.edit_note_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  l10n.aiSettingsSystemPrompt,
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l10n.aiSettingsSystemPromptHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            _SystemPromptField(notifier: _notifier),
          ],
        ),
      ),
    );
  }

  Widget _buildAboutCard(ThemeData theme) {
    final l10n = AppLocalizations.of(context)!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(l10n.aiSettingsAbout, style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(l10n.aiSettingsAboutBody),
          ],
        ),
      ),
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
                      if (!mounted) return;
                      setState(() => _dirty = false);
                      ScaffoldMessenger.of(context).showSnackBar(
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
