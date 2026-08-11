import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/ai_image_attachment.dart';

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
  final List<AiPendingImage> images;
  final VoidCallback? onAddImages;
  final ValueChanged<int>? onRemoveImage;
  final bool pickingImages;

  const AiChatInputBar({
    super.key,
    required this.controller,
    required this.enabled,
    required this.sending,
    required this.onSend,
    this.images = const [],
    this.onAddImages,
    this.onRemoveImage,
    this.pickingImages = false,
  });

  @override
  State<AiChatInputBar> createState() => _AiChatInputBarState();
}

class _AiChatInputBarState extends State<AiChatInputBar> {
  bool get _canSend =>
      widget.enabled &&
      !widget.sending &&
      (widget.controller.text.trim().isNotEmpty || widget.images.isNotEmpty);

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.images.isNotEmpty)
                    SizedBox(
                      height: 82,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                        itemCount: widget.images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _PendingImagePreview(
                          image: widget.images[index],
                          removeTooltip: l10n.aiChatRemoveImage,
                          onRemove: widget.sending
                              ? null
                              : () => widget.onRemoveImage?.call(index),
                        ),
                      ),
                    ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 5, bottom: 6),
                        child: widget.pickingImages
                            ? const SizedBox(
                                width: 40,
                                height: 40,
                                child: Padding(
                                  padding: EdgeInsets.all(11),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: l10n.aiChatAddImages,
                                onPressed:
                                    widget.enabled &&
                                        !widget.sending &&
                                        widget.images.length < kMaxAiChatImages
                                    ? widget.onAddImages
                                    : null,
                                icon: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                              ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: widget.controller,
                          enabled: widget.enabled,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.newline,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.35,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.enabled
                                ? l10n.aiChatInputHint
                                : l10n.aiChatInputHintDisabled,
                            hintStyle: TextStyle(
                              color: colors.onSurfaceVariant,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            filled: false,
                            isDense: true,
                            contentPadding: const EdgeInsets.fromLTRB(
                              4,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PendingImagePreview extends StatelessWidget {
  final AiPendingImage image;
  final String removeTooltip;
  final VoidCallback? onRemove;

  const _PendingImagePreview({
    required this.image,
    required this.removeTooltip,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(
            image.bytes,
            width: 64,
            height: 64,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 64,
              height: 64,
              color: colors.surfaceContainerHighest,
              child: const Icon(Icons.broken_image_outlined),
            ),
          ),
        ),
        Positioned(
          top: -5,
          right: -5,
          child: Tooltip(
            message: removeTooltip,
            child: Material(
              color: colors.inverseSurface,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onRemove,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colors.onInverseSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
