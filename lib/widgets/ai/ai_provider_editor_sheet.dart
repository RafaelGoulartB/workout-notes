import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/utils/ai_endpoint_policy.dart';
import 'package:workout_notes/utils/ai_error_localizer.dart';
import 'package:workout_notes/widgets/ai/ai_provider_check_view.dart';

/// Fetches the model list of a freshly saved provider in the background; a
/// failure is not worth interrupting the user for (the editor and the model
/// picker have their own "Fetch models" action).
Future<void> aiAutoFetchModels(AiSettingsNotifier notifier, String id) async {
  try {
    await notifier.fetchModels(id);
  } catch (error) {
    debugPrint('Automatic model fetch failed: $error');
  }
}

/// Add / edit a provider: name, base URL, token, model (typed or picked from
/// the fetched list), utility model, API style, reasoning effort and a
/// connection test. "Test connection" and "Fetch models" save first, so they
/// always run against exactly what is on screen.
class AiProviderEditorSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;
  final AiProvider? existing;

  const AiProviderEditorSheet({
    super.key,
    required this.notifier,
    this.existing,
  });

  @override
  State<AiProviderEditorSheet> createState() => _AiProviderEditorSheetState();
}

class _AiProviderEditorSheetState extends State<AiProviderEditorSheet> {
  late final TextEditingController _name;
  late final TextEditingController _baseUrl;
  late final TextEditingController _token;
  late final TextEditingController _model;
  late final TextEditingController _utility;
  late AiApiStyle _style;
  late Map<String, AiReasoningEffort> _efforts;

  /// The provider once it exists in the settings (an edit, or after the first
  /// save of a new one).
  AiProvider? _saved;

  bool _showToken = false;
  bool _saving = false;
  bool _fetching = false;
  bool _testing = false;
  String? _nameError;
  String? _urlError;
  String? _message;
  AiProviderCheck? _check;

  @override
  void initState() {
    super.initState();
    final p = widget.existing;
    _saved = p;
    _name = TextEditingController(text: p?.name ?? '');
    _baseUrl = TextEditingController(
      text: p?.baseUrl ?? 'https://api.openai.com/v1',
    );
    _token = TextEditingController();
    _model = TextEditingController(text: p?.selectedModel ?? '');
    _utility = TextEditingController(text: p?.utilityModel ?? '');
    _style = p?.apiStyle ?? AiApiStyle.chatCompletions;
    _efforts = {...?p?.reasoningEffortByModel};
    _check = p?.lastCheck;
    _model.addListener(_onModelChanged);
  }

  @override
  void dispose() {
    _model.removeListener(_onModelChanged);
    _name.dispose();
    _baseUrl.dispose();
    _token.dispose();
    _model.dispose();
    _utility.dispose();
    super.dispose();
  }

  void _onModelChanged() {
    if (mounted) setState(() {});
  }

  bool get _busy => _saving || _fetching || _testing;

  AiReasoningEffort get _effort =>
      _efforts[_model.text.trim()] ?? AiReasoningEffort.automatic;

  /// Validates the fields, then adds or updates the provider. Returns it, or
  /// null when a field is invalid (the error is shown on the field).
  Future<AiProvider?> _persist() async {
    final l10n = AppLocalizations.of(context)!;
    final name = _name.text.trim();
    final url = _baseUrl.text.trim();
    final nameError = name.isEmpty ? l10n.aiSettingsNameRequired : null;
    final urlError = url.isEmpty
        ? l10n.aiSettingsBaseUrlRequired
        : !AiService.isValidBaseUri(url)
        ? l10n.aiSettingsBaseUrlInvalid
        : !AiEndpointPolicy.isAllowed(url)
        ? l10n.aiSettingsBaseUrlInsecure
        : null;
    setState(() {
      _nameError = nameError;
      _urlError = urlError;
    });
    if (nameError != null || urlError != null) return null;

    final model = _model.text.trim();
    final token = _token.text.trim();
    final efforts = {..._efforts}
      ..removeWhere((_, effort) => effort == AiReasoningEffort.automatic);
    final notifier = widget.notifier;
    final current = _saved;
    String id;
    if (current == null) {
      final created = await notifier.addProvider(
        name: name,
        baseUrl: url,
        token: token.isEmpty ? null : token,
        model: model,
      );
      id = created.id;
      await notifier.updateProvider(
        created.copyWith(
          utilityModel: _utility.text.trim(),
          apiStyle: _style,
          reasoningEffortByModel: efforts,
        ),
      );
    } else {
      id = current.id;
      await notifier.updateProvider(
        current.copyWith(
          name: name,
          baseUrl: url,
          selectedModel: model,
          utilityModel: _utility.text.trim(),
          apiStyle: _style,
          reasoningEffortByModel: efforts,
          clearLastCheck:
              current.apiStyle != _style ||
              current.selectedModel != model ||
              AiService.normalizeBaseUri(current.baseUrl) !=
                  AiService.normalizeBaseUri(url),
        ),
        token: token.isEmpty ? null : token,
      );
    }
    _token.clear();
    for (final p in notifier.settings.providers) {
      if (p.id == id) return _saved = p;
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final provider = await _persist();
      if (provider == null) {
        if (mounted) setState(() => _saving = false);
        return;
      }
      unawaited(aiAutoFetchModels(widget.notifier, provider.id));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = localizeAiError(error, AppLocalizations.of(context)!);
      });
    }
  }

  Future<void> _fetchModels() async {
    setState(() {
      _fetching = true;
      _message = null;
    });
    try {
      final provider = await _persist();
      if (provider == null) return;
      final models = await widget.notifier.fetchModels(provider.id);
      if (!mounted) return;
      setState(() {
        // The saved copy now carries the fetched list (the model picker).
        for (final p in widget.notifier.settings.providers) {
          if (p.id == provider.id) _saved = p;
        }
        _message = AppLocalizations.of(
          context,
        )!.aiSettingsModelsFetched(models.length);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = localizeAiError(error, AppLocalizations.of(context)!),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _message = null;
      _check = null;
    });
    try {
      final provider = await _persist();
      if (provider == null) return;
      final check = await widget.notifier.testConnection(provider.id);
      if (mounted) setState(() => _check = check);
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _message = localizeAiError(error, AppLocalizations.of(context)!),
        );
      }
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _pickModel() async {
    final models = _saved?.availableModels ?? const <String>[];
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) =>
          _ModelListSheet(models: models, current: _model.text.trim()),
    );
    if (picked != null && mounted) _model.text = picked;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final model = _model.text.trim();
    final hasModels = (_saved?.availableModels ?? const []).isNotEmpty;

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
                color: colors.outlineVariant,
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
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsProviderName,
              hintText: l10n.aiSettingsNameHint,
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _baseUrl,
            keyboardType: TextInputType.url,
            autocorrect: false,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsBaseUrl,
              hintText: l10n.aiSettingsBaseUrlHint,
              errorText: _urlError,
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
                tooltip: _showToken
                    ? l10n.aiSettingsHideToken
                    : l10n.aiSettingsShowToken,
                onPressed: () => setState(() => _showToken = !_showToken),
                icon: Icon(
                  _showToken
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _model,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsModelId,
              hintText: l10n.aiSettingsModelIdHint,
              helperText: l10n.aiSettingsModelIdHelp,
              helperMaxLines: 2,
              suffixIcon: hasModels
                  ? IconButton(
                      tooltip: l10n.aiSettingsPickModel,
                      onPressed: _busy ? null : _pickModel,
                      icon: const Icon(Icons.list_rounded),
                    )
                  : null,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : _fetchModels,
              icon: _fetching
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.cloud_download_outlined, size: 18),
              label: Text(l10n.aiSettingsFetchModels),
            ),
          ),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _message!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _utility,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l10n.aiSettingsUtilityModel,
              hintText: l10n.aiSettingsModelIdHint,
              helperText: l10n.aiSettingsUtilityModelHelp,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: 18),
          Text(l10n.aiSettingsApiStyle, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          SegmentedButton<AiApiStyle>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(
                value: AiApiStyle.chatCompletions,
                label: Text(l10n.aiSettingsApiStyleChat),
              ),
              ButtonSegment(
                value: AiApiStyle.responses,
                label: Text(l10n.aiSettingsApiStyleResponses),
              ),
            ],
            selected: {_style},
            onSelectionChanged: (value) => setState(() => _style = value.first),
          ),
          const SizedBox(height: 6),
          Text(
            _style == AiApiStyle.chatCompletions
                ? l10n.aiSettingsApiStyleChatHelp
                : l10n.aiSettingsApiStyleResponsesHelp,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (model.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              l10n.aiSettingsReasoningEffortFor(model),
              style: theme.textTheme.labelLarge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final effort in AiReasoningEffort.values)
                  ChoiceChip(
                    label: Text(_effortLabel(l10n, effort)),
                    selected: _effort == effort,
                    onSelected: (_) => setState(() => _efforts[model] = effort),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: _busy ? null : _test,
            icon: _testing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check_rounded),
            label: Text(
              _testing ? l10n.aiSettingsTesting : l10n.aiSettingsTestConnection,
            ),
          ),
          if (_check != null) ...[
            const SizedBox(height: 10),
            AiProviderCheckView(check: _check!),
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
                onPressed: _busy ? null : _save,
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

  String _effortLabel(AppLocalizations l10n, AiReasoningEffort effort) {
    return switch (effort) {
      AiReasoningEffort.automatic => l10n.aiProviderPickerEffortAutomatic,
      AiReasoningEffort.low => l10n.aiProviderPickerEffortLow,
      AiReasoningEffort.medium => l10n.aiProviderPickerEffortMedium,
      AiReasoningEffort.high => l10n.aiProviderPickerEffortHigh,
    };
  }
}

/// Searchable list of the provider's models; pops with the picked id.
class _ModelListSheet extends StatefulWidget {
  final List<String> models;
  final String current;

  const _ModelListSheet({required this.models, required this.current});

  @override
  State<_ModelListSheet> createState() => _ModelListSheetState();
}

class _ModelListSheetState extends State<_ModelListSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final query = _search.text.trim().toLowerCase();
    final models = [
      for (final model in widget.models)
        if (model.toLowerCase().contains(query)) model,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        12 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        children: [
          TextField(
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: l10n.aiProviderPickerSearch,
              prefixIcon: const Icon(Icons.search_rounded),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              itemCount: models.length,
              itemBuilder: (context, index) {
                final model = models[index];
                final active = model == widget.current;
                return ListTile(
                  title: Text(
                    model,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: Icon(
                    active ? Icons.check_circle_rounded : Icons.circle_outlined,
                    color: active ? colors.primary : colors.outline,
                  ),
                  onTap: () => Navigator.of(context).pop(model),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
