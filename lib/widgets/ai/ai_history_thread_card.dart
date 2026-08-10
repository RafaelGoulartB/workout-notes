import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_chat_thread.dart';

enum _ThreadMenuAction { rename, togglePin, delete }

class AiHistoryThreadCard extends StatelessWidget {
  final AiChatThread thread;
  final String timestamp;
  final String? preview;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onTogglePinned;
  final VoidCallback onDelete;

  const AiHistoryThreadCard({
    super.key,
    required this.thread,
    required this.timestamp,
    required this.preview,
    required this.onTap,
    required this.onRename,
    required this.onTogglePinned,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(13, 13, 6, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: thread.isPinned
                      ? colors.primaryContainer
                      : colors.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  thread.isPinned
                      ? Icons.push_pin_rounded
                      : Icons.chat_bubble_outline_rounded,
                  size: 19,
                  color: thread.isPinned
                      ? colors.onPrimaryContainer
                      : colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            thread.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timestamp,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    if (preview?.isNotEmpty == true) ...[
                      const SizedBox(height: 5),
                      Text(
                        preview!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<_ThreadMenuAction>(
                tooltip: l10n.aiHistoryActions,
                icon: Icon(
                  Icons.more_vert_rounded,
                  color: colors.onSurfaceVariant,
                ),
                onSelected: (action) {
                  switch (action) {
                    case _ThreadMenuAction.rename:
                      onRename();
                      break;
                    case _ThreadMenuAction.togglePin:
                      onTogglePinned();
                      break;
                    case _ThreadMenuAction.delete:
                      onDelete();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: _ThreadMenuAction.rename,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.edit_outlined),
                      title: Text(l10n.aiHistoryRename),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ThreadMenuAction.togglePin,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        thread.isPinned
                            ? Icons.push_pin_outlined
                            : Icons.push_pin_rounded,
                      ),
                      title: Text(
                        thread.isPinned
                            ? l10n.aiHistoryUnpin
                            : l10n.aiHistoryPin,
                      ),
                    ),
                  ),
                  PopupMenuItem(
                    value: _ThreadMenuAction.delete,
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.delete_outline, color: colors.error),
                      title: Text(
                        l10n.commonDelete,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
