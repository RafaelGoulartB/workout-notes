import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

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
        ? (theme.brightness == Brightness.dark
              ? const Color(0xFF304C86)
              : theme.colorScheme.primaryContainer)
        : (theme.brightness == Brightness.dark
              ? const Color(0xFF27282E)
              : theme.colorScheme.surfaceContainerHigh);
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
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 5),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86,
          ),
          child: Column(
            crossAxisAlignment: isUser
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(color: color, borderRadius: radius),
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 13,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.content != null && message.content!.isNotEmpty)
                      _BodyText(
                        text: message.content!,
                        isUser: isUser,
                        textColor: textColor,
                      ),
                    // Tool calls are represented by the separate result bar below.
                    // Do not duplicate the tool name inside the message bubble.
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
                  ],
                ),
              ),
              if (!isUser && (onRetry != null || onCopy != null))
                Padding(
                  padding: EdgeInsets.zero,
                  child: Transform.translate(
                    offset: const Offset(0, -4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (onCopy != null)
                          IconButton(
                            tooltip: 'Copiar',
                            icon: const Icon(Icons.copy_rounded, size: 16),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                            width: 22,
                              height: 24,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: onCopy,
                          ),
                        if (onRetry != null)
                          IconButton(
                            tooltip: 'Tentar de novo',
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints.tightFor(
                            width: 22,
                              height: 24,
                            ),
                            padding: EdgeInsets.zero,
                            onPressed: onRetry,
                          ),
                      ],
                    ),
                  ),
                ),
              if (isUser && onCopy != null)
                Padding(
                  padding: EdgeInsets.zero,
                  child: Transform.translate(
                    offset: const Offset(0, -4),
                    child: IconButton(
                      tooltip: 'Copiar',
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints.tightFor(
                        width: 22,
                        height: 24,
                      ),
                      padding: EdgeInsets.zero,
                      onPressed: onCopy,
                    ),
                  ),
                ),
            ],
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
    final theme = Theme.of(context);
    final body = TextStyle(color: textColor, fontSize: 15, height: 1.35);
    return MarkdownBody(
      data: text,
      selectable: true,
      softLineBreak: true,
      shrinkWrap: true,
      styleSheet: MarkdownStyleSheet(
        p: body,
        strong: body.copyWith(fontWeight: FontWeight.w700),
        em: body.copyWith(fontStyle: FontStyle.italic),
        h1: theme.textTheme.titleLarge?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        h2: theme.textTheme.titleMedium?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        h3: theme.textTheme.titleSmall?.copyWith(
          color: textColor,
          fontWeight: FontWeight.w700,
        ),
        listBullet: body.copyWith(fontWeight: FontWeight.w700),
        blockquote: body.copyWith(color: theme.colorScheme.onSurfaceVariant),
        blockquoteDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          border: Border(
            left: BorderSide(color: theme.colorScheme.primary, width: 3),
          ),
        ),
        code: body.copyWith(
          fontFamily: 'monospace',
          fontSize: 13,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
        ),
        codeblockDecoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        horizontalRuleDecoration: BoxDecoration(
          border: Border(
            top: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        pPadding: const EdgeInsets.only(bottom: 6),
        listIndent: 20,
        blockSpacing: 8,
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
        const SnackBar(
          content: Text('Mensagem copiada'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }
}
