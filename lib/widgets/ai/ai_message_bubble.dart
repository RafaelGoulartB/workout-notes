import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/widgets/ai/ai_markdown.dart';
import 'package:workout_notes/widgets/ai/ai_thumbnail.dart';

/// Lays out one assistant-side row: the coach avatar (only on the first row
/// of an answer, otherwise an equal gap) and the content.
class AiAssistantFrame extends StatelessWidget {
  final bool showAvatar;
  final Widget child;
  final EdgeInsetsGeometry padding;

  const AiAssistantFrame({
    super.key,
    required this.child,
    this.showAvatar = true,
    this.padding = const EdgeInsets.fromLTRB(8, 4, 12, 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 28,
            child: showAvatar
                ? _CoachAvatar(colors: Theme.of(context).colorScheme)
                : null,
          ),
          const SizedBox(width: 8),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class AiMessageBubble extends StatelessWidget {
  final AiChatMessage message;
  final VoidCallback? onRetry;
  final VoidCallback? onCopy;
  final bool showTimestamp;

  /// Assistant: show the avatar and the coach name (the first row of an
  /// answer). Later text of the same answer sets it to false.
  final bool showHeader;

  /// Assistant: text written before a tool step. It has no copy/time row.
  final bool intermediate;

  /// User: restarts the turn this message started. Shown with the "Stopped" /
  /// "Interrupted" label of a turn that did not finish.
  final VoidCallback? onRetryTurn;

  const AiMessageBubble({
    super.key,
    required this.message,
    this.onRetry,
    this.onCopy,
    this.showTimestamp = true,
    this.showHeader = true,
    this.intermediate = false,
    this.onRetryTurn,
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (message.attachments.isNotEmpty)
                    _MessageImageGrid(message: message),
                  if (message.attachments.isNotEmpty &&
                      message.content?.trim().isNotEmpty == true)
                    const SizedBox(height: 10),
                  if (message.content?.trim().isNotEmpty == true)
                    SelectableText(
                      message.content!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colors.onPrimaryContainer,
                        height: 1.4,
                      ),
                    ),
                ],
              ),
            ),
            _TurnStatusLine(status: message.turnStatus, onRetry: onRetryTurn),
            if (showTimestamp || onCopy != null)
              _MessageMeta(
                timestamp: showTimestamp
                    ? _formatTime(context, message.createdAt)
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
    final showMeta =
        !intermediate && (showTimestamp || onCopy != null || onRetry != null);
    return AiAssistantFrame(
      showAvatar: showHeader,
      padding: EdgeInsets.fromLTRB(8, showHeader ? 12 : 4, 12, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader)
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
            AiMarkdown(text: message.content!, textColor: colors.onSurface),
          if (message.isCutOff)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: colors.outline,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      l10n.aiChatAnswerCutOff,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (showMeta)
            _MessageMeta(
              timestamp: showTimestamp
                  ? _formatTime(context, message.createdAt)
                  : null,
              onCopy: onCopy,
              onRetry: onRetry,
              alignEnd: false,
            ),
        ],
      ),
    );
  }
}

/// "Stopped" / "Interrupted" / "Not answered" under a user message whose turn
/// did not finish, with the retry action.
class _TurnStatusLine extends StatelessWidget {
  final AiTurnStatus? status;
  final VoidCallback? onRetry;

  const _TurnStatusLine({required this.status, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      AiTurnStatus.cancelled => AppLocalizations.of(context)!.aiChatTurnStopped,
      AiTurnStatus.interrupted => AppLocalizations.of(
        context,
      )!.aiChatTurnInterrupted,
      AiTurnStatus.failed => AppLocalizations.of(context)!.aiChatTurnFailed,
      _ => null,
    };
    if (label == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.info_outline_rounded, size: 15, color: colors.outline),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: Text(AppLocalizations.of(context)!.aiChatRetry),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageImageGrid extends StatelessWidget {
  final AiChatMessage message;

  const _MessageImageGrid({required this.message});

  @override
  Widget build(BuildContext context) {
    final attachments = message.attachments;
    final single = attachments.length == 1;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final attachment in attachments)
          Semantics(
            button: true,
            label: attachment.fileName,
            child: GestureDetector(
              onTap: () => showDialog<void>(
                context: context,
                barrierColor: Colors.black87,
                builder: (_) => Dialog.fullscreen(
                  backgroundColor: Colors.black,
                  child: Stack(
                    children: [
                      Center(
                        child: InteractiveViewer(
                          minScale: .8,
                          maxScale: 5,
                          child: Image.file(
                            File(attachment.path),
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white70,
                              size: 48,
                            ),
                          ),
                        ),
                      ),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: IconButton(
                            tooltip: MaterialLocalizations.of(
                              context,
                            ).closeButtonTooltip,
                            color: Colors.white,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image(
                  image: aiThumbnailProvider(
                    context,
                    FileImage(File(attachment.path)),
                    width: single ? 260 : 104,
                    height: single ? 176 : 104,
                  ),
                  width: single ? 260 : 104,
                  height: single ? 176 : 104,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: single ? 260 : 104,
                    height: single ? 176 : 104,
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
          ),
      ],
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

String _formatTime(BuildContext context, DateTime t) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );

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
