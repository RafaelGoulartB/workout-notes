import 'package:flutter/material.dart';

class AiChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool sending;
  final String? providerName;
  final String? modelName;
  final VoidCallback? onChooseProvider;
  final VoidCallback onSend;

  const AiChatInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sending,
    this.providerName,
    this.modelName,
    this.onChooseProvider,
    required this.onSend,
  });

  @override
  State<AiChatInputBar> createState() => _AiChatInputBarState();
}

class _AiChatInputBarState extends State<AiChatInputBar> {
  void _handleSend() {
    if (widget.controller.text.trim().isEmpty) return;
    widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        12,
        14,
        10 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF15161C) : theme.colorScheme.surface,
      ),
      child: Column(
        children: [
          Row(
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
                        ? 'Pergunte sobre seu treino'
                        : 'Configure um provedor para começar',
                    filled: true,
                    fillColor: dark
                        ? const Color(0xFF1B1C22)
                        : theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
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
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            Icons.arrow_upward_rounded,
                            color: theme.colorScheme.onPrimary,
                            size: 22,
                          ),
                  ),
                ),
              ),
            ],
          ),
          if (widget.providerName != null) ...[
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: widget.onChooseProvider,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.smart_toy_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${widget.providerName}  ·  ${widget.modelName?.isNotEmpty == true ? widget.modelName : 'sem modelo'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
