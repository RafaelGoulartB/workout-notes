import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_chat_thread.dart';
import '../../state/ai_chat_service.dart';
import '../../widgets/ai/ai_history_thread_card.dart';
import '../../widgets/settings/settings.dart';

class AiChatHistoryScreen extends StatefulWidget {
  const AiChatHistoryScreen({super.key});

  @override
  State<AiChatHistoryScreen> createState() => _AiChatHistoryScreenState();
}

class _AiChatHistoryScreenState extends State<AiChatHistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    AiChatService.instance.addListener(_onChange);
    AiChatService.instance.refreshThreads();
  }

  @override
  void dispose() {
    AiChatService.instance.removeListener(_onChange);
    _searchController.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final allThreads = AiChatService.instance.state.threads;
    final threads = _filterThreads(allThreads);
    final pinned = threads.where((thread) => thread.isPinned).toList();
    final today = threads
        .where(
          (thread) => !thread.isPinned && _ageInDays(thread.updatedAt) == 0,
        )
        .toList();
    final previous = threads.where((thread) {
      final age = _ageInDays(thread.updatedAt);
      return !thread.isPinned && age >= 1 && age < 7;
    }).toList();
    final older = threads
        .where(
          (thread) => !thread.isPinned && _ageInDays(thread.updatedAt) >= 7,
        )
        .toList();

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        titleSpacing: 0,
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(
                Icons.forum_outlined,
                size: 19,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.aiHistoryTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    l10n.aiHistoryConversationCount(allThreads.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: l10n.aiChatNewChat,
            onPressed: _startNewChat,
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: theme.colorScheme.outlineVariant.withAlpha(120),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onChanged: (value) => setState(() => _query = value.trim()),
              decoration: InputDecoration(
                hintText: l10n.aiHistorySearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: l10n.aiHistoryClearSearch,
                        onPressed: _clearSearch,
                        icon: const Icon(Icons.close_rounded),
                      ),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLow,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: allThreads.isEmpty
                ? _buildEmptyState(theme, l10n, searchEmpty: false)
                : threads.isEmpty
                ? _buildEmptyState(theme, l10n, searchEmpty: true)
                : ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    children: [
                      if (pinned.isNotEmpty) ...[
                        _sectionHeader(theme, l10n.aiHistoryPinned),
                        for (final thread in pinned) _threadItem(thread, l10n),
                      ],
                      if (today.isNotEmpty) ...[
                        _sectionHeader(theme, l10n.aiHistoryToday),
                        for (final thread in today) _threadItem(thread, l10n),
                      ],
                      if (previous.isNotEmpty) ...[
                        _sectionHeader(theme, l10n.aiHistoryPrevious7Days),
                        for (final thread in previous)
                          _threadItem(thread, l10n),
                      ],
                      if (older.isNotEmpty) ...[
                        _sectionHeader(theme, l10n.aiHistoryOlder),
                        for (final thread in older) _threadItem(thread, l10n),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          letterSpacing: .8,
        ),
      ),
    );
  }

  Widget _threadItem(AiChatThread thread, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final displayThread = thread.copyWith(title: _displayTitle(thread));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(thread.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(thread, l10n),
        onDismissed: (_) => AiChatService.instance.deleteThread(thread.id),
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(horizontal: 22),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(
            Icons.delete_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
        ),
        child: AiHistoryThreadCard(
          thread: displayThread,
          timestamp: _formatTimestamp(thread.updatedAt, l10n),
          preview: _cleanPreview(thread.lastMessagePreview),
          onTap: () => _openThread(thread.id),
          onRename: () => _renameThread(thread, l10n),
          onTogglePinned: () => _setPinned(thread, !thread.isPinned, l10n),
          onDelete: () => _deleteThread(thread, l10n),
        ),
      ),
    );
  }

  Widget _buildEmptyState(
    ThemeData theme,
    AppLocalizations l10n, {
    required bool searchEmpty,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                searchEmpty ? Icons.search_off_rounded : Icons.forum_outlined,
                color: theme.colorScheme.primary,
                size: 27,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              searchEmpty ? l10n.aiHistoryNoResults : l10n.aiHistoryEmpty,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              searchEmpty
                  ? l10n.aiHistoryNoResultsSubtitle
                  : l10n.aiHistoryEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            if (searchEmpty) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: _clearSearch,
                child: Text(l10n.aiHistoryClearSearch),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<AiChatThread> _filterThreads(List<AiChatThread> threads) {
    if (_query.isEmpty) return threads;
    final query = _query.toLowerCase();
    return threads.where((thread) {
      return thread.title.toLowerCase().contains(query) ||
          (thread.lastMessagePreview?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  String _displayTitle(AiChatThread thread) {
    final title = thread.title.trim();
    final generic = {
      'conversa',
      'conversation',
      'nova conversa',
      'new conversation',
    }.contains(title.toLowerCase());
    if (!generic) return title;
    final preview = _cleanPreview(thread.lastMessagePreview);
    if (preview == null || preview.isEmpty) return title;
    return preview.length > 56 ? '${preview.substring(0, 53)}…' : preview;
  }

  String? _cleanPreview(String? value) {
    if (value == null) return null;
    final cleaned = value
        .replaceAll(RegExp(r'[*_`>#]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  int _ageInDays(DateTime value) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(value.year, value.month, value.day);
    return today.difference(date).inDays.clamp(0, 999999);
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  Future<void> _startNewChat() async {
    await AiChatService.instance.newChat();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _openThread(String id) async {
    final navigator = Navigator.of(context);
    await AiChatService.instance.openThread(id);
    if (mounted) navigator.pop();
  }

  Future<void> _deleteThread(AiChatThread thread, AppLocalizations l10n) async {
    if (await _confirmDelete(thread, l10n)) {
      await AiChatService.instance.deleteThread(thread.id);
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
    final ok = await SettingsConfirmDialog.show(
      context: context,
      title: l10n.aiHistoryDeleteTitle,
      message: l10n.aiHistoryDeleteBody(thread.title),
      confirmLabel: l10n.commonDelete,
      cancelLabel: l10n.commonCancel,
    );
    return ok ?? false;
  }

  void _showOperationError(AppLocalizations l10n) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.aiHistoryActionError)));
  }

  String _formatTimestamp(DateTime value, AppLocalizations l10n) {
    final age = _ageInDays(value);
    if (age == 0) {
      return '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
    }
    if (age == 1) return l10n.aiHistoryYesterday;
    if (age < 7) return '${age}d';
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
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
