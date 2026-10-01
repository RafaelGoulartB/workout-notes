import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/widgets/ai/ai_thumbnail.dart';

/// Mobile-first composer inspired by current conversational AI apps.
///
/// The field and its action live in one surface, avoiding the disconnected
/// input/button/provider rows of the previous layout. Provider selection is
/// intentionally kept in the screen header, where users expect model controls.
class AiChatInputBar extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;

  /// A turn is running: the field is locked and the send button becomes Stop.
  final bool sending;
  final VoidCallback onSend;

  /// Stops the running turn (the Stop button shows while [sending]).
  final VoidCallback? onStop;

  /// The Stop request was sent and the turn is winding down.
  final bool stopping;

  /// A turn runs in another conversation: the composer waits and offers a
  /// way to open it.
  final bool busyElsewhere;
  final VoidCallback? onOpenBusyConversation;
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
    this.onStop,
    this.stopping = false,
    this.busyElsewhere = false,
    this.onOpenBusyConversation,
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
      !widget.busyElsewhere &&
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
                  if (widget.busyElsewhere)
                    _BusyElsewhereStrip(
                      label: l10n.aiChatBusyElsewhere,
                      actionLabel: l10n.aiChatBusyOpen,
                      onOpen: widget.onOpenBusyConversation,
                    ),
                  if (widget.images.isNotEmpty)
                    SizedBox(
                      height: 92,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
                        itemCount: widget.images.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) => _PendingImagePreview(
                          image: widget.images[index],
                          removeTooltip: l10n.aiChatRemoveImage,
                          onRemove: widget.sending || widget.busyElsewhere
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
                                        !widget.busyElsewhere &&
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
                          enabled:
                              widget.enabled &&
                              !widget.sending &&
                              !widget.busyElsewhere,
                          minLines: 1,
                          maxLines: 6,
                          keyboardType: TextInputType.multiline,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.newline,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            height: 1.35,
                          ),
                          decoration: InputDecoration(
                            hintText: !widget.enabled
                                ? l10n.aiChatInputHintDisabled
                                : widget.busyElsewhere
                                ? l10n.aiChatBusyElsewhere
                                : l10n.aiChatInputHint,
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
                        child: widget.sending && widget.onStop != null
                            ? _StopButton(
                                stopping: widget.stopping,
                                onStop: widget.onStop!,
                              )
                            : Semantics(
                                button: true,
                                enabled: _canSend,
                                label: l10n.aiChatSend,
                                excludeSemantics: true,
                                onTap: _canSend ? _handleSend : null,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _canSend
                                        ? colors.primary
                                        : colors.surfaceContainerHighest,
                                  ),
                                  child: IconButton(
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

class _StopButton extends StatelessWidget {
  final bool stopping;
  final VoidCallback onStop;

  const _StopButton({required this.stopping, required this.onStop});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    return Semantics(
      button: true,
      enabled: !stopping,
      label: l10n.aiChatStopSemantics,
      excludeSemantics: true,
      onTap: stopping ? null : onStop,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: stopping ? colors.surfaceContainerHighest : colors.onSurface,
        ),
        child: stopping
            ? Padding(
                padding: const EdgeInsets.all(13),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colors.onSurfaceVariant,
                ),
              )
            : IconButton(
                tooltip: l10n.aiChatStop,
                onPressed: onStop,
                padding: EdgeInsets.zero,
                icon: Icon(Icons.stop_rounded, size: 24, color: colors.surface),
              ),
      ),
    );
  }
}

class _BusyElsewhereStrip extends StatelessWidget {
  final String label;
  final String actionLabel;
  final VoidCallback? onOpen;

  const _BusyElsewhereStrip({
    required this.label,
    required this.actionLabel,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 6, 0),
      child: Row(
        children: [
          SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
          if (onOpen != null)
            TextButton(
              onPressed: onOpen,
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              child: Text(actionLabel),
            ),
        ],
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

  /// The remove target is 48 dp (the visible badge is smaller), so the preview
  /// box is larger than the 64 dp image it frames.
  static const double _box = 80;
  static const double _image = 64;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: _box,
      height: _box,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image(
                image: aiThumbnailProvider(
                  context,
                  MemoryImage(image.bytes),
                  width: _image,
                  height: _image,
                ),
                width: _image,
                height: _image,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: _image,
                  height: _image,
                  color: colors.surfaceContainerHighest,
                  child: const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            width: 48,
            height: 48,
            child: Tooltip(
              message: removeTooltip,
              child: Semantics(
                button: true,
                enabled: onRemove != null,
                label: removeTooltip,
                excludeSemantics: true,
                onTap: onRemove,
                child: InkResponse(
                  onTap: onRemove,
                  radius: 24,
                  child: Align(
                    alignment: const Alignment(0.45, -0.45),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: colors.inverseSurface,
                        shape: BoxShape.circle,
                      ),
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
          ),
        ],
      ),
    );
  }
}
