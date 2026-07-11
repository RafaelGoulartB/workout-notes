import 'dart:convert';

import 'package:flutter/material.dart';

import '../../models/ai_chat_message.dart';

class AiToolResultBubble extends StatefulWidget {
  final AiChatMessage message;
  final String toolLabel;

  const AiToolResultBubble({
    super.key,
    required this.message,
    required this.toolLabel,
  });

  @override
  State<AiToolResultBubble> createState() => _AiToolResultBubbleState();
}

class _AiToolResultBubbleState extends State<AiToolResultBubble> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isOk = widget.message.toolResult?.ok ?? true;
    final color = isOk
        ? (theme.brightness == Brightness.dark
              ? const Color(0xFF27282E)
              : theme.colorScheme.tertiaryContainer)
        : theme.colorScheme.errorContainer;
    final fg = isOk
        ? theme.colorScheme.onTertiaryContainer
        : theme.colorScheme.onErrorContainer;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.86,
          ),
          child: Material(
            color: color,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: theme.colorScheme.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isOk
                              ? Icons.check_circle_outline_rounded
                              : Icons.error_outline_rounded,
                          size: 16,
                          color: fg,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isOk ? 'Ferramenta aplicada' : widget.toolLabel,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: fg,
                            ),
                          ),
                        ),
                        Icon(
                          _expanded
                              ? Icons.expand_less_rounded
                              : Icons.expand_more_rounded,
                          size: 18,
                          color: fg,
                        ),
                      ],
                    ),
                    if (_expanded) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withAlpha(180),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          _previewJson(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFamily: 'monospace',
                            fontSize: 11,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _previewJson() {
    final raw = widget.message.content;
    if (raw == null || raw.isEmpty) return '(sem conteúdo)';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['ok'] == false) {
        return 'Erro: ${decoded['code'] ?? 'desconhecido'}\n${decoded['message'] ?? ''}';
      }
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      return pretty.length > 1200 ? '${pretty.substring(0, 1200)}…' : pretty;
    } catch (_) {
      return raw.length > 600 ? '${raw.substring(0, 600)}…' : raw;
    }
  }
}
