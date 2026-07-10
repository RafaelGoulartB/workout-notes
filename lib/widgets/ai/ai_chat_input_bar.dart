import 'package:flutter/material.dart';

class AiChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final VoidCallback onSend;

  const AiChatInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
  });

  @override
  State<AiChatInputBar> createState() => _AiChatInputBarState();
}

class _AiChatInputBarState extends State<AiChatInputBar> {
  void _handleSend() {
    final text = widget.controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: widget.controller,
              enabled: widget.enabled && !widget.sending,
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: widget.enabled
                    ? 'Pergunte algo ao seu treinador…'
                    : 'Configure um provedor para começar',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Material(
            color: widget.sending
                ? theme.colorScheme.surfaceContainerHigh
                : theme.colorScheme.primary,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: widget.enabled && !widget.sending ? _handleSend : null,
              child: SizedBox(
                width: 44,
                height: 44,
                child: widget.sending
                    ? Padding(
                        padding: const EdgeInsets.all(12),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: theme.colorScheme.onPrimary,
                        size: 20,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
