import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Renders the coach's markdown.
///
/// Nothing is fetched or opened by itself: images show their alt text instead
/// of loading from the network, and a tapped link only shows its address (with
/// a copy action). The parsed tree and the style sheet are kept by the state
/// object, so a rebuild with the same text and theme costs nothing; only a new
/// text (a streaming delta) is parsed again.
class AiMarkdown extends StatefulWidget {
  final String text;
  final Color? textColor;

  /// Long-press selection. Streaming drafts turn it off: the text changes
  /// many times a second and a selection could not survive that.
  final bool selectable;

  const AiMarkdown({
    super.key,
    required this.text,
    this.textColor,
    this.selectable = true,
  });

  @override
  State<AiMarkdown> createState() => _AiMarkdownState();
}

class _AiMarkdownState extends State<AiMarkdown> {
  MarkdownStyleSheet? _sheet;
  ThemeData? _sheetTheme;
  Color? _sheetColor;

  MarkdownStyleSheet _styleSheet(ThemeData theme, Color color) {
    final cached = _sheet;
    if (cached != null &&
        identical(_sheetTheme, theme) &&
        _sheetColor == color) {
      return cached;
    }
    final body = theme.textTheme.bodyLarge?.copyWith(
      color: color,
      height: 1.45,
    );
    final colors = theme.colorScheme;
    _sheetTheme = theme;
    _sheetColor = color;
    return _sheet = MarkdownStyleSheet(
      p: body,
      strong: body?.copyWith(fontWeight: FontWeight.w700),
      em: body?.copyWith(fontStyle: FontStyle.italic),
      a: body?.copyWith(
        color: colors.primary,
        decoration: TextDecoration.underline,
      ),
      h1: theme.textTheme.headlineSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      h2: theme.textTheme.titleLarge?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      h3: theme.textTheme.titleMedium?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
      ),
      listBullet: body?.copyWith(fontWeight: FontWeight.w700),
      blockquote: body?.copyWith(color: colors.onSurfaceVariant),
      blockquoteDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: colors.primary, width: 3)),
      ),
      code: body?.copyWith(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: colors.surfaceContainerHighest,
      ),
      codeblockPadding: const EdgeInsets.all(12),
      codeblockDecoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outlineVariant),
      ),
      tableBorder: TableBorder.all(color: colors.outlineVariant),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      pPadding: const EdgeInsets.only(bottom: 7),
      listIndent: 22,
      blockSpacing: 9,
    );
  }

  void _onTapLink(String text, String? href, String title) {
    if (href == null || href.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(href, maxLines: 3, overflow: TextOverflow.ellipsis),
          action: SnackBarAction(
            label: l10n.aiChatCopy,
            onPressed: () => Clipboard.setData(ClipboardData(text: href)),
          ),
        ),
      );
  }

  Widget _image(Uri uri, String? title, String? alt) {
    final text = (alt != null && alt.trim().isNotEmpty)
        ? alt.trim()
        : (title ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.image_outlined, size: 16, color: colors.onSurfaceVariant),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              color: colors.onSurfaceVariant,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = widget.textColor ?? theme.colorScheme.onSurface;
    return MarkdownBody(
      data: widget.text,
      selectable: widget.selectable,
      softLineBreak: true,
      shrinkWrap: true,
      onTapLink: _onTapLink,
      imageBuilder: _image,
      styleSheet: _styleSheet(theme, color),
    );
  }
}
