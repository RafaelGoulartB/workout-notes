import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_chat_thread.dart';
import '../../state/ai_chat_service.dart';
import '../../widgets/empty_state_placeholder.dart';

enum _HistoryAction { rename, pin, unpin, delete }

class AiChatHistoryScreen extends StatefulWidget {
  const AiChatHistoryScreen({super.key});

  @override
  State<AiChatHistoryScreen> createState() => _AiChatHistoryScreenState();
}

class _AiChatHistoryScreenState extends State<AiChatHistoryScreen> {
  @override
  void initState() {
    super.initState();
    AiChatService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    AiChatService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final threads = AiChatService.instance.state.threads;
    final pinned = threads.where((thread) => thread.isPinned).toList();
    final recent = threads.where((thread) => !thread.isPinned).toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiHistoryTitle)),
      body: threads.isEmpty
          ? EmptyStatePlaceholder(
              icon: Icons.history_rounded,
              title: l10n.aiHistoryEmpty,
              subtitle: l10n.aiHistoryEmptySubtitle,
            )
          : ListView(
              children: [
                if (pinned.isNotEmpty) ...[
                  _SectionHeader(label: l10n.aiHistoryPinned),
                  for (final thread in pinned) _buildThreadTile(thread, l10n),
                ],
                if (recent.isNotEmpty) ...[
                  if (pinned.isNotEmpty)
                    _SectionHeader(label: l10n.aiHistoryRecent),
                  for (final thread in recent) _buildThreadTile(thread, l10n),
                ],
              ],
            ),
    );
  }

  Widget _buildThreadTile(AiChatThread thread, AppLocalizations l10n) {
    final theme = Theme.of(context);
    return Dismissible(
      key: ValueKey(thread.id),
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Icon(
          Icons.delete_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(thread, l10n),
      onDismissed: (_) => AiChatService.instance.deleteThread(thread.id),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              thread.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.chat_bubble_outline_rounded,
            ),
            title: Text(
              thread.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: thread.lastMessagePreview != null
                ? Text(
                    thread.lastMessagePreview!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatTimestamp(thread.updatedAt, l10n)),
                PopupMenuButton<_HistoryAction>(
                  tooltip: l10n.aiHistoryActions,
                  onSelected: (action) => _handleAction(action, thread, l10n),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: _HistoryAction.rename,
                      child: Text(l10n.aiHistoryRename),
                    ),
                    PopupMenuItem(
                      value: thread.isPinned
                          ? _HistoryAction.unpin
                          : _HistoryAction.pin,
                      child: Text(
                        thread.isPinned
                            ? l10n.aiHistoryUnpin
                            : l10n.aiHistoryPin,
                      ),
                    ),
                    PopupMenuItem(
                      value: _HistoryAction.delete,
                      child: Text(l10n.commonDelete),
                    ),
                  ],
                ),
              ],
            ),
            onTap: () async {
              final navigator = Navigator.of(context);
              await AiChatService.instance.openThread(thread.id);
              if (mounted) navigator.pop();
            },
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }

  Future<void> _handleAction(
    _HistoryAction action,
    AiChatThread thread,
    AppLocalizations l10n,
  ) async {
    switch (action) {
      case _HistoryAction.rename:
        await _renameThread(thread, l10n);
        break;
      case _HistoryAction.pin:
        await _setPinned(thread, true, l10n);
        break;
      case _HistoryAction.unpin:
        await _setPinned(thread, false, l10n);
        break;
      case _HistoryAction.delete:
        if (await _confirmDelete(thread, l10n)) {
          await AiChatService.instance.deleteThread(thread.id);
        }
        break;
    }
  }

  Future<void> _renameThread(AiChatThread thread, AppLocalizations l10n) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(initialTitle: thread.title),
    );
    if (title == null) return;
    final success = await AiChatService.instance.renameThread(thread.id, title);
    if (!success && mounted) _showOperationError(l10n);
  }

  Future<void> _setPinned(
    AiChatThread thread,
    bool isPinned,
    AppLocalizations l10n,
  ) async {
    final success = await AiChatService.instance.setThreadPinned(
      thread.id,
      isPinned,
    );
    if (!success && mounted) _showOperationError(l10n);
  }

  Future<bool> _confirmDelete(
    AiChatThread thread,
    AppLocalizations l10n,
  ) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(l10n.aiHistoryDeleteTitle),
            content: Text(l10n.aiHistoryDeleteBody(thread.title)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton.tonal(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.commonDelete),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showOperationError(AppLocalizations l10n) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.aiHistoryActionError)));
  }

  String _formatTimestamp(DateTime t, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tsDay = DateTime(t.year, t.month, t.day);
    final diff = today.difference(tsDay).inDays;
    if (diff == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return l10n.aiHistoryYesterday;
    if (diff < 7) return '${diff}d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }
}

class _RenameDialog extends StatefulWidget {
  final String initialTitle;

  const _RenameDialog({required this.initialTitle});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialTitle);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(AppLocalizations l10n) {
    final title = _controller.text.trim();
    if (title.isEmpty) {
      setState(() => _validationError = l10n.aiHistoryRenameRequired);
      return;
    }
    Navigator.of(context).pop(title);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.aiHistoryRenameTitle),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLength: 80,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: l10n.aiHistoryRenameLabel,
          hintText: l10n.aiHistoryRenameHint,
          errorText: _validationError,
        ),
        onSubmitted: (_) => _submit(l10n),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => _submit(l10n),
          child: Text(l10n.commonSave),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;

  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
