import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Mobile-first composer inspired by current conversational AI apps.
///
/// The field and its action live in one surface, avoiding the disconnected
/// input/button/provider rows of the previous layout. Provider selection is
/// intentionally kept in the screen header, where users expect model controls.
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
  bool get _canSend =>
      widget.enabled &&
      !widget.sending &&
      widget.controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(covariant AiChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  void _handleSend() {
    if (_canSend) widget.onSend();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return SafeArea(
      top: false,
      child: Container(
        color: colors.surface,
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: colors.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
                side: BorderSide(color: colors.outlineVariant),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      // Keep drafting available while the model is working;
                      // only sending is locked until the current turn ends.
                      enabled: widget.enabled,
                      minLines: 1,
                      maxLines: 6,
                      keyboardType: TextInputType.multiline,
                      textCapitalization: TextCapitalization.sentences,
                      textInputAction: TextInputAction.newline,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.35),
                      decoration: InputDecoration(
                        hintText: widget.enabled
                            ? l10n.aiChatInputHint
                            : l10n.aiChatInputHintDisabled,
                        hintStyle: TextStyle(color: colors.onSurfaceVariant),
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        disabledBorder: InputBorder.none,
                        filled: false,
                        isDense: true,
                        contentPadding: const EdgeInsets.fromLTRB(
                          16,
                          14,
                          8,
                          14,
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 6, bottom: 6),
                    child: Semantics(
                      button: true,
                      enabled: _canSend,
                      label: l10n.aiChatSend,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _canSend
                              ? colors.primary
                              : colors.surfaceContainerHighest,
                        ),
                        child: widget.sending
                            ? Padding(
                                padding: const EdgeInsets.all(11),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onSurfaceVariant,
                                ),
                              )
                            : IconButton(
                                tooltip: l10n.aiChatSend,
                                onPressed: _canSend ? _handleSend : null,
                                padding: EdgeInsets.zero,
                                icon: Icon(
                                  Icons.arrow_upward_rounded,
                                  size: 22,
                                  color: _canSend
                                      ? colors.onPrimary
                                      : colors.onSurfaceVariant,
                                ),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
