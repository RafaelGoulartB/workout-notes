import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/widgets/settings/settings.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Localized name of a memory category.
String aiMemoryCategoryLabel(AiMemoryCategory category, AppLocalizations l10n) {
  switch (category) {
    case AiMemoryCategory.health:
      return l10n.aiMemoryCategoryHealth;
    case AiMemoryCategory.equipment:
      return l10n.aiMemoryCategoryEquipment;
    case AiMemoryCategory.schedule:
      return l10n.aiMemoryCategorySchedule;
    case AiMemoryCategory.preference:
      return l10n.aiMemoryCategoryPreference;
    case AiMemoryCategory.goal:
      return l10n.aiMemoryCategoryGoal;
    case AiMemoryCategory.other:
      return l10n.aiMemoryCategoryOther;
  }
}

IconData _categoryIcon(AiMemoryCategory category) {
  switch (category) {
    case AiMemoryCategory.health:
      return Icons.healing_outlined;
    case AiMemoryCategory.equipment:
      return Icons.fitness_center_rounded;
    case AiMemoryCategory.schedule:
      return Icons.event_outlined;
    case AiMemoryCategory.preference:
      return Icons.tune_rounded;
    case AiMemoryCategory.goal:
      return Icons.flag_outlined;
    case AiMemoryCategory.other:
      return Icons.sticky_note_2_outlined;
  }
}

/// "What the coach remembers": every note the coach keeps across
/// conversations, grouped by category. The user can add, edit, delete one or
/// clear them all.
class AiMemoryScreen extends StatefulWidget {
  final AiMemoryService? service;

  const AiMemoryScreen({super.key, this.service});

  @override
  State<AiMemoryScreen> createState() => _AiMemoryScreenState();
}

class _AiMemoryScreenState extends State<AiMemoryScreen> {
  late final AiMemoryService _service =
      widget.service ?? AiMemoryService.instance;
  List<AiMemory>? _memories;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_reload);
    unawaited(_reload());
  }

  @override
  void dispose() {
    _service.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final memories = await _service.all();
      if (!mounted) return;
      setState(() {
        _memories = memories;
        _loadFailed = false;
      });
    } catch (error) {
      debugPrint('Loading the AI memories failed: $error');
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _edit(AiMemory? existing) async {
    final l10n = AppLocalizations.of(context)!;
    if (existing == null &&
        (_memories?.length ?? 0) >= AiMemoryService.maxEntries) {
      showAppSnack(context, l10n.aiMemoryFull);
      return;
    }
    final result = await showModalBottomSheet<_MemoryDraft>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _MemoryEditorSheet(existing: existing),
      ),
    );
    if (result == null || !mounted) return;
    try {
      if (existing == null) {
        await _service.add(result.content, result.category);
      } else {
        await _service.update(
          existing.copyWith(content: result.content, category: result.category),
        );
      }
    } catch (error) {
      debugPrint('Saving an AI memory failed: $error');
      if (mounted) showAppSnack(context, l10n.aiMemorySaveError);
    }
  }

  Future<void> _delete(AiMemory memory) async {
    final l10n = AppLocalizations.of(context)!;
    try {
      await _service.remove(memory.id);
    } catch (error) {
      debugPrint('Deleting an AI memory failed: $error');
      if (mounted) showAppSnack(context, l10n.aiMemorySaveError);
      return;
    }
    if (!mounted) return;
    showAppSnack(
      context,
      l10n.aiMemoryDeleted,
      action: SnackBarAction(
        label: l10n.commonUndo,
        onPressed: () => unawaited(_service.restore(memory)),
      ),
    );
  }

  Future<void> _clearAll() async {
    final l10n = AppLocalizations.of(context)!;
    final count = _memories?.length ?? 0;
    if (count == 0) return;
    final ok = await showConfirmDialog(
      context,
      title: l10n.aiMemoryClearTitle,
      message: l10n.aiMemoryClearBody(count),
      confirmLabel: l10n.aiMemoryClearAll,
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await _service.clear();
    } catch (error) {
      debugPrint('Clearing the AI memories failed: $error');
      if (mounted) showAppSnack(context, l10n.aiMemorySaveError);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final memories = _memories;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          l10n.aiMemoryTitle,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        actions: [
          if (memories != null && memories.isNotEmpty)
            TextButton(
              onPressed: _clearAll,
              child: Text(l10n.aiMemoryClearAll),
            ),
        ],
      ),
      floatingActionButton: memories == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded),
              label: Text(l10n.aiMemoryAdd),
            ),
      body: _body(l10n, theme, memories),
    );
  }

  Widget _body(
    AppLocalizations l10n,
    ThemeData theme,
    List<AiMemory>? memories,
  ) {
    if (_loadFailed && memories == null) {
      return AppEmptyState(
        icon: Icons.error_outline_rounded,
        title: l10n.aiMemoryLoadError,
        subtitle: '',
        actionLabel: l10n.commonRetry,
        onAction: () => unawaited(_reload()),
        compact: true,
      );
    }
    if (memories == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (memories.isEmpty) {
      return AppEmptyState(
        icon: Icons.psychology_alt_outlined,
        title: l10n.aiMemoryEmptyTitle,
        subtitle: l10n.aiMemoryEmptyBody,
        actionLabel: l10n.aiMemoryAdd,
        onAction: () => unawaited(_edit(null)),
        compact: true,
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Text(
            l10n.aiMemoryIntro,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 0),
          child: Text(
            l10n.aiMemoryCount(memories.length, AiMemoryService.maxEntries),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        for (final category in AiMemoryCategory.values)
          ..._group(l10n, category, [
            for (final memory in memories)
              if (memory.category == category) memory,
          ]),
      ],
    );
  }

  List<Widget> _group(
    AppLocalizations l10n,
    AiMemoryCategory category,
    List<AiMemory> entries,
  ) {
    if (entries.isEmpty) return const [];
    return [
      AppSectionHeader(
        aiMemoryCategoryLabel(category, l10n),
        padding: AppSectionHeader.compactPadding,
      ),
      SettingsCard(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            _MemoryTile(
              memory: entries[i],
              icon: _categoryIcon(category),
              onTap: () => unawaited(_edit(entries[i])),
              onDelete: () => unawaited(_delete(entries[i])),
            ),
            if (i < entries.length - 1) const SettingsCardDivider(),
          ],
        ],
      ),
    ];
  }
}

class _MemoryTile extends StatelessWidget {
  final AiMemory memory;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MemoryTile({
    required this.memory,
    required this.icon,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colors.onSurfaceVariant),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(memory.content),
              ),
            ),
            IconButton(
              tooltip: l10n.commonDelete,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline_rounded, color: colors.error),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemoryDraft {
  final String content;
  final AiMemoryCategory category;
  const _MemoryDraft(this.content, this.category);
}

class _MemoryEditorSheet extends StatefulWidget {
  final AiMemory? existing;
  const _MemoryEditorSheet({this.existing});

  @override
  State<_MemoryEditorSheet> createState() => _MemoryEditorSheetState();
}

class _MemoryEditorSheetState extends State<_MemoryEditorSheet> {
  late final TextEditingController _content = TextEditingController(
    text: widget.existing?.content ?? '',
  );
  late AiMemoryCategory _category =
      widget.existing?.category ?? AiMemoryCategory.other;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  void _save() {
    final text = _content.text.trim();
    if (text.isEmpty) {
      setState(
        () => _error = AppLocalizations.of(context)!.aiMemoryContentRequired,
      );
      return;
    }
    Navigator.of(context).pop(_MemoryDraft(text, _category));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
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
                ? l10n.aiMemoryNewTitle
                : l10n.aiMemoryEditTitle,
            style: theme.textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _content,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            maxLength: AiMemoryService.maxChars,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l10n.aiMemoryContentLabel,
              hintText: l10n.aiMemoryContentHint,
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
          ),
          const SizedBox(height: 8),
          Text(l10n.aiMemoryCategoryLabel, style: theme.textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final category in AiMemoryCategory.values)
                ChoiceChip(
                  label: Text(aiMemoryCategoryLabel(category, l10n)),
                  selected: _category == category,
                  onSelected: (_) => setState(() => _category = category),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(l10n.commonCancel),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _save, child: Text(l10n.commonSave)),
            ],
          ),
        ],
      ),
    );
  }
}
