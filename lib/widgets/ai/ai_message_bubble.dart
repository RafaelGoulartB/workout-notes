import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_chat_message.dart';

class AiMessageBubble extends StatelessWidget {
  final AiChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final bool showTimestamp;

  const AiMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onCopy,
    this.showTimestamp = true,
  });

  @override
  Widget build(BuildContext context) {
    return message.isUser ? _buildUser(context) : _buildAssistant(context);
  }

  Widget _buildUser(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 8, 16, 8),
      child: Align(
        alignment: Alignment.centerRight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 340),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(6),
                ),
              ),
              child: SelectableText(
                message.content ?? '',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onPrimaryContainer,
                  height: 1.4,
                ),
              ),
            ),
            if (showTimestamp || onCopy != null)
              _MessageMeta(
                timestamp: showTimestamp
                    ? _formatTime(message.createdAt)
                    : null,
                onCopy: onCopy,
                onRetry: null,
                alignEnd: true,
                compact: true,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistant(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CoachAvatar(colors: colors),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, bottom: 7),
                  child: Text(
                    l10n.aiChatCoachName,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                ),
                if (message.content?.isNotEmpty == true)
                  _MarkdownBody(
                    text: message.content!,
                    textColor: colors.onSurface,
                  ),
                if (showTimestamp || onCopy != null || onRetry != null)
                  _MessageMeta(
                    timestamp: showTimestamp
                        ? _formatTime(message.createdAt)
                        : null,
                    onCopy: onCopy,
                    onRetry: onRetry,
                    alignEnd: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoachAvatar extends StatelessWidget {
  final ColorScheme colors;
  const _CoachAvatar({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 16,
        color: colors.onPrimaryContainer,
      ),
    );
  }
}

class _MessageMeta extends StatelessWidget {
  final String? timestamp;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final bool alignEnd;
  final bool compact;

  const _MessageMeta({
    required this.timestamp,
    required this.onCopy,
    required this.onRetry,
    required this.alignEnd,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Transform.translate(
      offset: Offset(0, compact ? -4 : 0),
      child: Padding(
        padding: EdgeInsets.only(top: compact ? 0 : 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: alignEnd
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            if (timestamp != null)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: compact ? 5 : 6),
                child: Text(
                  timestamp!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            if (onCopy != null)
              _ActionButton(
                tooltip: l10n.aiChatCopy,
                icon: Icons.content_copy_rounded,
                onPressed: onCopy!,
                compact: compact,
              ),
            if (onRetry != null)
              _ActionButton(
                tooltip: l10n.aiChatRetry,
                icon: Icons.refresh_rounded,
                onPressed: onRetry!,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool compact;

  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(
        width: compact ? 30 : 36,
        height: compact ? 30 : 36,
      ),
      padding: EdgeInsets.zero,
      icon: Icon(
        icon,
        size: compact ? 15 : 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  final String text;
  final Color textColor;
  const _MarkdownBody({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(
      color: textColor,
      height: 1.45,
    );
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body?.copyWith(fontWeight: FontWeight.w700),
        em: body?.copyWith(fontStyle: FontStyle.italic),
        h1: theme.textTheme.headlineSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        h2: theme.textTheme.titleLarge?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        h3: theme.textTheme.titleMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        listBullet: body?.copyWith(fontWeight: FontWeight.w700),
        blockquote: body?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        code: body?.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        pPadding: const EdgeInsets.only(bottom: 7),
        listIndent: 22,
        blockSpacing: 9,
      ),
    );
  }
}

String _formatTime(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

class MessageCopyAction {
  static Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.aiChatCopied),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }
}
