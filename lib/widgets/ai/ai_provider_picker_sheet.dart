import 'package:flutter/material.dart';

import '../../models/ai_provider.dart';
import '../../state/ai_settings_notifier.dart';

class AiProviderPickerSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;
  const AiProviderPickerSheet({super.key, required this.notifier});

  @override
  State<AiProviderPickerSheet> createState() => _AiProviderPickerSheetState();
}

class _AiProviderPickerSheetState extends State<AiProviderPickerSheet> {
  final _search = TextEditingController();
  String? _selectedId;
  String _query = '';
  bool _fetching = false;
  String? _fetchError;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.notifier.settings.activeProvider?.id;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = _selectedProvider;
    final models =
        selected?.availableModels
            .where((m) => m.toLowerCase().contains(_query))
            .toList() ??
        const <String>[];
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .86,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  Icon(
                    Icons.smart_toy_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Provedor e modelo',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (selected != null)
                    IconButton(
                      tooltip: 'Atualizar modelos',
                      onPressed: _fetching ? null : _fetchModels,
                      icon: _fetching
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_rounded),
                    ),
                ],
              ),
              if (_fetchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _fetchError!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 20),
              if (widget.notifier.settings.providers.length > 1)
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: widget.notifier.settings.providers.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (_, i) {
                      final p = widget.notifier.settings.providers[i];
                      return ChoiceChip(
                        label: Text(p.name),
                        selected: p.id == _selectedId,
                        onSelected: (_) => setState(() => _selectedId = p.id),
                      );
                    },
                  ),
                ),
              if (selected != null) ...[
                const SizedBox(height: 18),
                TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    hintText: 'Buscar modelo',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: _search.clear,
                          ),
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: models.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum modelo disponível',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: models.length,
                          separatorBuilder: (_, _) =>
                              Divider(color: theme.colorScheme.outlineVariant),
                          itemBuilder: (_, i) {
                            final model = models[i];
                            final active = model == selected.selectedModel;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 0,
                              ),
                              title: Text(model),
                              trailing: active
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: theme.colorScheme.primary,
                                    )
                                  : null,
                              onTap: () async {
                                await widget.notifier.setSelectedModel(
                                  selected.id,
                                  model,
                                );
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                            );
                          },
                        ),
                ),
              ] else
                const Expanded(
                  child: Center(child: Text('Nenhum provedor configurado')),
                ),
            ],
          ),
        ),
      ),
    );
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
    } catch (e) {
      if (mounted) setState(() => _fetchError = e.toString());
    } finally {
      if (mounted) setState(() => _fetching = false);
    }
  }
}
