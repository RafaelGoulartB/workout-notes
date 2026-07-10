import 'package:flutter/material.dart';

import '../../models/ai_provider.dart';
import '../../state/ai_settings_notifier.dart';

class AiProviderPickerSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;

  const AiProviderPickerSheet({
    super.key,
    required this.notifier,
  });

  @override
  State<AiProviderPickerSheet> createState() => _AiProviderPickerSheetState();
}

class _AiProviderPickerSheetState extends State<AiProviderPickerSheet> {
  String? _selectedId;
  String? _fetchError;
  bool _fetching = false;

  @override
  void initState() {
    super.initState();
    widget.notifier.addListener(_onChange);
    _selectedId = widget.notifier.settings.activeProvider?.id;
  }

  @override
  void dispose() {
    widget.notifier.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  AiProvider? get _selectedProvider {
    if (_selectedId == null) return null;
    for (final p in widget.notifier.settings.providers) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = widget.notifier.settings;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.cloud_outlined, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Provedor e modelo',
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
            if (settings.providers.length > 1) ...[
              SizedBox(
                height: 48,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  scrollDirection: Axis.horizontal,
                  itemCount: settings.providers.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final p = settings.providers[i];
                    final selected = p.id == _selectedId;
                    return ChoiceChip(
                      label: Text(p.name),
                      selected: selected,
                      onSelected: (_) => setState(() => _selectedId = p.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_selectedProvider != null)
              _buildModelSection(theme, _selectedProvider!),
            if (_fetchError != null) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _fetchError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Row(
                children: [
                  TextButton.icon(
                    onPressed: _selectedProvider == null || _fetching
                        ? null
                        : () async {
                            setState(() {
                              _fetching = true;
                              _fetchError = null;
                            });
                            try {
                              await widget.notifier
                                  .fetchModels(_selectedProvider!.id);
                            } catch (e) {
                              if (mounted) {
                                setState(() => _fetchError = e.toString());
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _fetching = false);
                              }
                            }
                          },
                    icon: _fetching
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Buscar modelos'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _selectedProvider == null ? null : _onConfirm,
                    child: const Text('Aplicar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModelSection(ThemeData theme, AiProvider provider) {
    if (provider.availableModels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Text(
          'Nenhum modelo carregado. Toque em "Buscar modelos" para listar os disponíveis em ${provider.baseUrl}.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        itemCount: provider.availableModels.length,
        itemBuilder: (_, i) {
          final m = provider.availableModels[i];
          return InkWell(
            onTap: () async {
              await widget.notifier.setSelectedModel(provider.id, m);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Radio<String>(
                    value: m,
                    groupValue: provider.selectedModel,
                    onChanged: (v) async {
                      if (v == null) return;
                      await widget.notifier.setSelectedModel(provider.id, v);
                    },
                  ),
                  Expanded(
                    child: Text(
                      m,
                      style: theme.textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (m == provider.selectedModel)
                    Icon(Icons.check_rounded,
                        size: 18, color: theme.colorScheme.primary),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _onConfirm() async {
    if (_selectedProvider == null) return;
    if (_selectedProvider!.id != widget.notifier.settings.activeProviderId) {
      await widget.notifier.setActiveProvider(_selectedProvider!.id);
    }
    if (mounted) Navigator.of(context).pop();
  }
}
