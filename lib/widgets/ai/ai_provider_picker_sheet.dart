import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_provider.dart';
import '../../state/ai_settings_notifier.dart';
import '../../utils/ai_error_localizer.dart';

class AiProviderPickerSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;
  final String? initialProviderId;

  const AiProviderPickerSheet({
    super.key,
    required this.notifier,
    this.initialProviderId,
  });

  @override
  State<AiProviderPickerSheet> createState() => _AiProviderPickerSheetState();
}

class _AiProviderPickerSheetState extends State<AiProviderPickerSheet> {
  final _search = TextEditingController();
  String? _selectedId;
  String _draftModel = '';
  AiReasoningEffort _draftEffort = AiReasoningEffort.automatic;
  String _query = '';
  bool _fetching = false;
  bool _saving = false;
  bool _showModels = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _selectedId =
        widget.initialProviderId ?? widget.notifier.settings.activeProvider?.id;
    _loadProviderDraft();
    _search.addListener(
      () => setState(() => _query = _search.text.trim().toLowerCase()),
    );
    widget.notifier.addListener(_onChange);
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChange);
    _search.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  AiProvider? get _selectedProvider => widget.notifier.settings.providers
      .cast<AiProvider?>()
      .firstWhere((p) => p?.id == _selectedId, orElse: () => null);

  void _loadProviderDraft() {
    final provider = _selectedProvider;
    _draftModel = provider?.selectedModel ?? '';
    _draftEffort =
        provider?.reasoningEffortFor(_draftModel) ??
        AiReasoningEffort.automatic;
  }

  void _selectProvider(AiProvider provider) {
    FocusScope.of(context).unfocus();
    setState(() {
      _selectedId = provider.id;
      _query = '';
      _search.clear();
      _fetchError = null;
      _draftModel = provider.selectedModel;
      _draftEffort = provider.reasoningEffortFor(_draftModel);
      _showModels = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final selected = _selectedProvider;
    final models =
        selected?.availableModels
            .where((model) => model.toLowerCase().contains(_query))
            .toList() ??
        const <String>[];

    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: _showModels ? .92 : null,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: _showModels ? MainAxisSize.max : MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurfaceVariant.withValues(alpha: .7),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: colors.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.smart_toy_rounded,
                      color: colors.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.aiProviderPickerTitle,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          l10n.aiProviderPickerSubtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (selected != null && _showModels)
                    IconButton.filledTonal(
                      tooltip: l10n.aiSettingsFetchModels,
                      onPressed: _fetching ? null : _fetchModels,
                      icon: _fetching
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(
                      context,
                    ).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              if (_fetchError != null)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _fetchError!,
                    style: TextStyle(color: colors.onErrorContainer),
                  ),
                ),
              if (widget.notifier.settings.providers.length > 1) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.aiProviderPickerProviderLabel,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.notifier.settings.providers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, index) {
                      final provider =
                          widget.notifier.settings.providers[index];
                      return ChoiceChip(
                        avatar: provider.id == _selectedId
                            ? const Icon(Icons.check_rounded, size: 18)
                            : null,
                        label: Text(provider.name),
                        selected: provider.id == _selectedId,
                        onSelected: (_) => _selectProvider(provider),
                      );
                    },
                  ),
                ),
              ],
              if (selected != null) ...[
                const SizedBox(height: 16),
                Text(
                  l10n.aiProviderPickerEffortTitle,
                  style: theme.textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  _effortDescription(l10n, _draftEffort),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: AiReasoningEffort.values.map((effort) {
                    return ChoiceChip(
                      label: Text(_effortLabel(l10n, effort)),
                      selected: _draftEffort == effort,
                      onSelected: (_) => setState(() => _draftEffort = effort),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                _SelectionCard(
                  providerName: selected.name,
                  model: _draftModel,
                  emptyModelLabel: l10n.aiProviderPickerNoModelSelected,
                  changeModelLabel: l10n.aiProviderPickerChangeModel,
                  expanded: _showModels,
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    setState(() => _showModels = !_showModels);
                  },
                ),
                if (_showModels) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _search,
                    autofocus: true,
                    decoration: InputDecoration(
                      hintText: l10n.aiProviderPickerSearch,
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: MaterialLocalizations.of(
                                context,
                              ).deleteButtonTooltip,
                              icon: const Icon(Icons.close_rounded),
                              onPressed: _search.clear,
                            ),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      l10n.aiProviderPickerModelCount(models.length),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Expanded(
                    child: models.isEmpty
                        ? Center(
                            child: Text(
                              l10n.aiSettingsNoModelsEmpty,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            itemCount: models.length,
                            itemBuilder: (_, index) {
                              final model = models[index];
                              final active = model == _draftModel;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Material(
                                  color: active
                                      ? colors.primaryContainer.withValues(
                                          alpha: .65,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    title: Text(
                                      model,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing: Icon(
                                      active
                                          ? Icons.check_circle_rounded
                                          : Icons.circle_outlined,
                                      color: active
                                          ? colors.primary
                                          : colors.outline,
                                    ),
                                    onTap: () {
                                      FocusScope.of(context).unfocus();
                                      setState(() {
                                        _draftModel = model;
                                        _draftEffort = selected
                                            .reasoningEffortFor(model);
                                        _showModels = false;
                                        _query = '';
                                        _search.clear();
                                      });
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _draftModel.isEmpty || _saving
                        ? null
                        : _applySelection,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(l10n.aiProviderPickerApply),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 32),
                Center(child: Text(l10n.aiSettingsNoProviders)),
                const SizedBox(height: 32),
              ],
            ],
          ),
        ),
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

  String _effortDescription(AppLocalizations l10n, AiReasoningEffort effort) {
    return switch (effort) {
      AiReasoningEffort.automatic =>
        l10n.aiProviderPickerEffortAutomaticDescription,
      AiReasoningEffort.low => l10n.aiProviderPickerEffortLowDescription,
      AiReasoningEffort.medium => l10n.aiProviderPickerEffortMediumDescription,
      AiReasoningEffort.high => l10n.aiProviderPickerEffortHighDescription,
    };
  }

  Future<void> _applySelection() async {
    final provider = _selectedProvider;
    if (provider == null || _draftModel.isEmpty) return;
    setState(() => _saving = true);
    await widget.notifier.setSelectedModel(provider.id, _draftModel);
    await widget.notifier.setReasoningEffort(
      provider.id,
      _draftModel,
      _draftEffort,
    );
    await widget.notifier.setActiveProvider(provider.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _fetchModels() async {
    final provider = _selectedProvider;
    if (provider == null) return;
    setState(() {
      _fetching = true;
      _fetchError = null;
    });
    try {
      await widget.notifier.fetchModels(provider.id);
    } catch (error) {
      if (mounted) {
        setState(
          () => _fetchError = localizeAiError(
            error,
            AppLocalizations.of(context)!,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }
}

class _SelectionCard extends StatelessWidget {
  final String providerName;
  final String model;
  final String emptyModelLabel;
  final String changeModelLabel;
  final bool expanded;
  final VoidCallback onTap;

  const _SelectionCard({
    required this.providerName,
    required this.model,
    required this.emptyModelLabel,
    required this.changeModelLabel,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Material(
      color: colors.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.memory_rounded, color: colors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      model.isEmpty ? emptyModelLabel : model,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      providerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Tooltip(
                message: changeModelLabel,
                child: Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
