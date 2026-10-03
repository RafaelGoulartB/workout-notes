import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/utils/clock_format.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/widgets/ai/ai_history_thread_card.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class AiChatHistoryScreen extends StatefulWidget {
  const AiChatHistoryScreen({super.key});

  @override
  State<AiChatHistoryScreen> createState() => _AiChatHistoryScreenState();
}

class _AiChatHistoryScreenState extends State<AiChatHistoryScreen> {
  static const _searchDebounce = Duration(milliseconds: 300);
  static const _searchPageSize = 50;

  final _searchController = TextEditingController();
  Timer? _debounce;

  /// What the user typed (trimmed) and the query the shown results belong to.
  String _query = '';
  String _activeQuery = '';

  /// SQLite search results for [_activeQuery]; the loaded thread pages are
  /// only used while the search box is empty.
  List<AiChatThread> _results = const [];
  bool _resultsHaveMore = false;
  int? _resultsTotal;
  bool _searching = false;
  bool _loadingMoreResults = false;
  int _searchGeneration = 0;

  @override
  void initState() {
    super.initState();
    AiChatService.instance.addListener(_onChange);
    unawaited(AiChatService.instance.ensureReady());
  }

  @override
  void dispose() {
    _debounce?.cancel();
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
    final service = AiChatService.instance;
    final searchActive = _activeQuery.isNotEmpty;
    final threads = searchActive ? _results : service.state.threads;
    final count = searchActive
        ? (_resultsTotal ?? _results.length)
        : (service.state.totalThreadCount ?? threads.length);
    final hasMore = searchActive
        ? _resultsHaveMore
        : service.state.hasOlderThreads;
    final loadingMore = searchActive
        ? _loadingMoreResults
        : service.state.isLoadingOlderThreads;
    final rows = _buildRows(threads, l10n);

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
                    l10n.aiHistoryConversationCount(count),
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
              onChanged: _onQueryChanged,
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
            child: threads.isEmpty
                ? (_query.isNotEmpty && (_searching || _activeQuery != _query))
                      ? const Center(child: CircularProgressIndicator())
                      : _buildEmptyState(
                          theme,
                          l10n,
                          searchEmpty: _query.isNotEmpty,
                        )
                : ListView.builder(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    itemCount: rows.length + (hasMore || loadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == rows.length) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: loadingMore
                                ? null
                                : searchActive
                                ? _loadMoreResults
                                : service.loadOlderThreads,
                            icon: loadingMore
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.history, size: 18),
                            label: Text(l10n.aiChatLoadOlder),
                          ),
                        );
                      }
                      final row = rows[index];
                      return row.thread == null
                          ? _sectionHeader(theme, row.header!)
                          : _threadItem(row.thread!, l10n);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Flattens the pinned / today / previous 7 days / older groups into
  /// headers and threads so a lazy list can build only what is visible.
  List<_HistoryRow> _buildRows(
    List<AiChatThread> threads,
    AppLocalizations l10n,
  ) {
    final pinned = <AiChatThread>[];
    final today = <AiChatThread>[];
    final previous = <AiChatThread>[];
    final older = <AiChatThread>[];
    for (final thread in threads) {
      if (thread.isPinned) {
        pinned.add(thread);
        continue;
      }
      final age = _ageInDays(thread.updatedAt);
      (age == 0 ? today : (age < 7 ? previous : older)).add(thread);
    }
    return [
      for (final group in [
        (l10n.aiHistoryPinned, pinned),
        (l10n.aiHistoryToday, today),
        (l10n.aiHistoryPrevious7Days, previous),
        (l10n.aiHistoryOlder, older),
      ])
        if (group.$2.isNotEmpty) ...[
          _HistoryRow.header(group.$1),
          for (final thread in group.$2) _HistoryRow.thread(thread),
        ],
    ];
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
    final displayThread = thread.copyWith(title: _displayTitle(thread, l10n));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Dismissible(
        key: ValueKey(thread.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (_) => _confirmDelete(thread, l10n),
        onDismissed: (_) => _removeThread(thread),
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

  /// Untitled threads (empty marker or a legacy generic title) show their
  /// first message, or the localized "new conversation" label. Titles the user
  /// wrote are shown untouched.
  String _displayTitle(AiChatThread thread, AppLocalizations l10n) {
    if (!thread.hasGenericTitle) return thread.title.trim();
    final preview = _cleanPreview(thread.lastMessagePreview);
    if (preview == null || preview.isEmpty) return l10n.aiChatNewChat;
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
    final today = dayOf(now);
    final date = dayOf(value);
    return daysBetween(date, today).clamp(0, 999999);
  }

  void _onQueryChanged(String value) {
    final query = value.trim();
    if (query == _query) return;
    _debounce?.cancel();
    if (query.isEmpty) {
      _searchGeneration++;
      setState(() {
        _query = '';
        _activeQuery = '';
        _results = const [];
        _resultsHaveMore = false;
        _resultsTotal = null;
        _searching = false;
        _loadingMoreResults = false;
      });
      return;
    }
    setState(() => _query = query);
    _debounce = Timer(_searchDebounce, () => unawaited(_runSearch()));
  }

  void _clearSearch() {
    _searchController.clear();
    _onQueryChanged('');
  }

  /// Runs the SQLite search for the current query. [keepLoaded] reloads at
  /// least as many rows as are already shown, so a rename, pin or delete
  /// refreshes the list without collapsing pages the user already loaded.
  Future<void> _runSearch({bool keepLoaded = false}) async {
    final query = _query;
    if (query.isEmpty) return;
    final generation = ++_searchGeneration;
    setState(() {
      _searching = true;
      _activeQuery = query;
    });
    try {
      final page = await AiChatService.instance.searchThreads(
        query,
        limit: keepLoaded && _results.length > _searchPageSize
            ? _results.length
            : _searchPageSize,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = page.threads;
        _resultsHaveMore = page.hasMore;
        _resultsTotal = page.total;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = const [];
        _resultsHaveMore = false;
        _resultsTotal = 0;
        _searching = false;
      });
    }
  }

  Future<void> _loadMoreResults() async {
    if (_loadingMoreResults || !_resultsHaveMore) return;
    final generation = _searchGeneration;
    setState(() => _loadingMoreResults = true);
    try {
      final page = await AiChatService.instance.searchThreads(
        _activeQuery,
        offset: _results.length,
        limit: _searchPageSize,
      );
      if (!mounted || generation != _searchGeneration) return;
      final known = {for (final thread in _results) thread.id};
      setState(() {
        _results = [
          ..._results,
          ...page.threads.where((thread) => !known.contains(thread.id)),
        ];
        _resultsHaveMore = page.hasMore;
        _loadingMoreResults = false;
      });
    } catch (_) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loadingMoreResults = false);
      }
    }
  }

  /// Re-reads search results after a thread changed (no-op without a query).
  Future<void> _refreshResults() async {
    if (_activeQuery.isNotEmpty) await _runSearch(keepLoaded: true);
  }

  /// Swipe-to-delete: the tile must leave the tree synchronously.
  Future<void> _removeThread(AiChatThread thread) async {
    if (_activeQuery.isNotEmpty) {
      setState(() {
        _results = [
          for (final item in _results)
            if (item.id != thread.id) item,
        ];
        if (_resultsTotal != null) _resultsTotal = _resultsTotal! - 1;
      });
    }
    await AiChatService.instance.deleteThread(thread.id);
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
      await _removeThread(thread);
    }
  }

  Future<void> _renameThread(AiChatThread thread, AppLocalizations l10n) async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => _RenameDialog(
        initialTitle: thread.hasGenericTitle ? '' : thread.title,
      ),
    );
    if (title == null) return;
    final success = await AiChatService.instance.renameThread(thread.id, title);
    if (!mounted) return;
    if (!success) {
      _showOperationError(l10n);
      return;
    }
    await _refreshResults();
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
    if (!mounted) return;
    if (!success) {
      _showOperationError(l10n);
      return;
    }
    await _refreshResults();
  }

  Future<bool> _confirmDelete(
    AiChatThread thread,
    AppLocalizations l10n,
  ) async {
    final ok = await showConfirmDialog(
      context,
      title: l10n.aiHistoryDeleteTitle,
      message: l10n.aiHistoryDeleteBody(_displayTitle(thread, l10n)),
      confirmLabel: l10n.commonDelete,
      destructive: true,
      icon: Icons.warning_amber_rounded,
    );
    return ok;
  }

  void _showOperationError(AppLocalizations l10n) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.aiHistoryActionError)));
  }

  /// Time today, "yesterday", the weekday this week, otherwise day/month, all
  /// in the app language (`pt_BR` for Portuguese).
  String _formatTimestamp(DateTime value, AppLocalizations l10n) {
    final age = _ageInDays(value);
    if (age == 1) return l10n.aiHistoryYesterday;
    final locale = Localizations.localeOf(context).languageCode == 'pt'
        ? 'pt_BR'
        : 'en';
    try {
      if (age == 0) return ClockFormat.format(context, value);
      if (age < 7) return DateFormat.E(locale).format(value);
      return DateFormat.Md(locale).format(value);
    } on Object catch (error) {
      // Date symbols of this locale are not loaded: show a plain date.
      debugPrint('History date format failed: $error');
      return dateKey(value);
    }
  }
}

/// A group header or a thread in the flattened history list.
class _HistoryRow {
  final String? header;
  final AiChatThread? thread;

  const _HistoryRow.header(String this.header) : thread = null;
  const _HistoryRow.thread(AiChatThread this.thread) : header = null;
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
