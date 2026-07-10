import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    final theme = Theme.of(context);
    final isUser = message.isUser;

    final color = isUser
        ? theme.colorScheme.primaryContainer
        : theme.colorScheme.surfaceContainerHigh;
    final textColor = isUser
        ? theme.colorScheme.onPrimaryContainer
        : theme.colorScheme.onSurface;

    final align = isUser ? Alignment.centerRight : Alignment.centerLeft;
    final radius = isUser
        ? const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86,
          ),
          child: Container(
            decoration: BoxDecoration(color: color, borderRadius: radius),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.content != null && message.content!.isNotEmpty)
                  _BodyText(
                    text: message.content!,
                    isUser: isUser,
                    textColor: textColor,
                  ),
                if (message.toolCalls.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _ToolCallSummary(message: message),
                ],
                if (showTimestamp) ...[
                  const SizedBox(height: 4),
                  Text(
                    _formatTime(message.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: textColor.withAlpha(160),
                      fontSize: 10,
                    ),
                  ),
                ],
                if (!isUser && (onRetry != null || onCopy != null)) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (onCopy != null)
                        IconButton(
                          tooltip: 'Copiar',
                          icon: const Icon(Icons.copy_rounded, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: onCopy,
                        ),
                      if (onRetry != null)
                        IconButton(
                          tooltip: 'Tentar de novo',
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          visualDensity: VisualDensity.compact,
                          onPressed: onRetry,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BodyText extends StatelessWidget {
  final String text;
  final bool isUser;
  final Color textColor;

  const _BodyText({
    required this.text,
    required this.isUser,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    if (isUser) {
      return SelectableText(
        text,
        style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
      );
    }
    return _MarkdownBody(text: text, textColor: textColor);
  }
}

class _MarkdownBody extends StatelessWidget {
  final String text;
  final Color textColor;
  const _MarkdownBody({required this.text, required this.textColor});

  @override
  Widget build(BuildContext context) {
    return SelectionArea(
      child: Text(
        _stripMarkdown(text),
        style: TextStyle(color: textColor, fontSize: 15, height: 1.35),
      ),
    );
  }

  String _stripMarkdown(String s) {
    return s
        .replaceAll(RegExp(r'```[\s\S]*?```'), '')
        .replaceAllMapped(RegExp(r'`([^`]+)`'), (match) => match.group(1)!)
        .replaceAllMapped(
          RegExp(r'\*\*([^*]+)\*\*'),
          (match) => match.group(1)!,
        )
        .replaceAllMapped(RegExp(r'\*([^*]+)\*'), (match) => match.group(1)!)
        .replaceAll(RegExp(r'^#+\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-*]\s+', multiLine: true), '• ');
  }
}

class _ToolCallSummary extends StatelessWidget {
  final AiChatMessage message;
  const _ToolCallSummary({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: message.toolCalls
          .map(
            (c) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.build_circle_outlined,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
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
        const SnackBar(
          content: Text('Mensagem copiada'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}
