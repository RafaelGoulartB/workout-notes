import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/ai_chat_timeline.dart';
import 'package:workout_notes/widgets/ai/ai_tool_presentation.dart';

/// Largest raw tool payload shown inline (developer mode). "Copy" always
/// copies everything.
const int kAiRawPreviewChars = 8 * 1024;

/// Localized text for the code of a failed tool result.
String aiToolErrorText(String? code, AppLocalizations l10n) {
  switch (code) {
    case 'invalid_args':
    case 'invalid_arguments_json':
      return l10n.aiChatToolErrorInvalidArgs;
    case 'not_found':
      return l10n.aiChatToolErrorNotFound;
    case 'unknown_tool':
    case 'domain_disabled':
      return l10n.aiChatToolErrorUnavailable;
    case 'interrupted':
      return l10n.aiChatToolErrorInterrupted;
    case 'limit_reached':
      return l10n.aiChatToolErrorLimit;
    default:
      return l10n.aiChatToolErrorGeneric;
  }
}

/// The compact "Consulted: Sleep summary, Nutrition (+2)" row of one agent
/// step, expandable to the list of its tool calls.
class AiToolStepsRow extends StatefulWidget {
  final List<AiToolStep> steps;

  /// Developer mode: each step can show its raw JSON (built only when asked).
  final bool developerMode;

  const AiToolStepsRow({
    super.key,
    required this.steps,
    this.developerMode = false,
  });

  @override
  State<AiToolStepsRow> createState() => _AiToolStepsRowState();
}

class _AiToolStepsRowState extends State<AiToolStepsRow> {
  bool _expanded = false;

  static const int _visibleNames = 2;
  static const int _visibleChips = 3;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final labels = <String>[];
    for (final step in widget.steps) {
      final label = AiToolPresentation.label(step.call.name, l10n);
      if (!labels.contains(label)) labels.add(label);
    }
    final shown = labels.take(_visibleNames).join(', ');
    final extra = labels.length - _visibleNames;
    // A step that only prepared proposals did not read anything.
    final onlyProposals = widget.steps.every(
      (step) => step.call.name.startsWith('propose_'),
    );
    final title = onlyProposals
        ? (extra > 0
              ? l10n.aiChatStepsPreparedMore(shown, extra)
              : l10n.aiChatStepsPrepared(shown))
        : (extra > 0
              ? l10n.aiChatStepsConsultedMore(shown, extra)
              : l10n.aiChatStepsConsulted(shown));

    final summaries = <String>[];
    for (final step in widget.steps) {
      final summary = AiToolPresentation.argsSummary(
        step.call.name,
        step.call.arguments,
        l10n,
      );
      if (summary != null &&
          summary.isNotEmpty &&
          !summaries.contains(summary)) {
        summaries.add(summary);
      }
    }
    final anyFailed = widget.steps.any((step) => step.failed);

    return Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant.withAlpha(150)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: title,
            excludeSemantics: true,
            onTap: () => setState(() => _expanded = !_expanded),
            child: InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        AiToolPresentation.icon(widget.steps.first.call.name),
                        size: 18,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (!_expanded && summaries.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  for (final s in summaries.take(_visibleChips))
                                    _SummaryChip(text: s),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (anyFailed)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Tooltip(
                            message: l10n.aiChatStepsFailedSome,
                            child: Icon(
                              Icons.warning_amber_rounded,
                              size: 18,
                              color: colors.tertiary,
                            ),
                          ),
                        ),
                      Icon(
                        _expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final step in widget.steps)
                    _StepDetail(
                      step: step,
                      developerMode: widget.developerMode,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String text;
  const _SummaryChip({required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: colors.onSurfaceVariant),
      ),
    );
  }
}

class _StepDetail extends StatelessWidget {
  final AiToolStep step;
  final bool developerMode;

  const _StepDetail({required this.step, required this.developerMode});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final summary = AiToolPresentation.argsSummary(
      step.call.name,
      step.call.arguments,
      l10n,
    );
    final failed = step.failed;
    final (IconData icon, Color color) = !step.hasResult
        ? (Icons.pending_outlined, colors.outline)
        : failed
        ? (Icons.warning_amber_rounded, colors.tertiary)
        : (Icons.check_circle_outline_rounded, colors.primary);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(icon, size: 16, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: AiToolPresentation.label(step.call.name, l10n),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (summary != null && summary.isNotEmpty)
                        TextSpan(
                          text: '  $summary',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                    ],
                  ),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          if (!step.hasResult)
            _note(theme, l10n.aiChatStepNoResult, colors.onSurfaceVariant)
          else if (failed)
            _note(
              theme,
              aiToolErrorText(step.outcome?.code, l10n),
              colors.onSurfaceVariant,
            ),
          if (developerMode && step.hasResult)
            AiRawJsonView(
              call: step.call.arguments,
              content: step.result!.content ?? '',
            ),
        ],
      ),
    );
  }

  Widget _note(ThemeData theme, String text, Color color) => Padding(
    padding: const EdgeInsets.only(left: 24, top: 2),
    child: Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(color: color),
    ),
  );
}

/// Developer view of a tool payload: a collapsed "Raw data" toggle that
/// builds (decodes and pretty-prints) the JSON only when opened, shows at most
/// [kAiRawPreviewChars] characters and copies the complete text.
class AiRawJsonView extends StatefulWidget {
  final Map<String, dynamic> call;
  final String content;

  const AiRawJsonView({super.key, required this.call, required this.content});

  @override
  State<AiRawJsonView> createState() => _AiRawJsonViewState();
}

class _AiRawJsonViewState extends State<AiRawJsonView> {
  bool _open = false;
  String? _pretty;

  String get _full => _pretty ??= _prettyPrint(widget.call, widget.content);

  static String _prettyPrint(Map<String, dynamic> call, String raw) {
    Object? result = raw;
    try {
      result = jsonDecode(raw);
    } on FormatException {
      // Not JSON: show the text as it is.
    }
    return const JsonEncoder.withIndent(
      '  ',
    ).convert({'arguments': call, 'result': result});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.data_object_rounded,
                    size: 15,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    l10n.aiChatStepsRawData,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_open) _buildBody(l10n, theme),
        ],
      ),
    );
  }

  Widget _buildBody(AppLocalizations l10n, ThemeData theme) {
    final full = _full;
    final truncated = full.length > kAiRawPreviewChars;
    final preview = truncated ? full.substring(0, kAiRawPreviewChars) : full;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: SelectableText(
                preview,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontFamily: 'monospace',
                  height: 1.35,
                ),
              ),
            ),
          ),
          if (truncated)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                l10n.aiChatStepsRawTruncated(kAiRawPreviewChars ~/ 1024),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await Clipboard.setData(ClipboardData(text: full));
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(l10n.aiChatStepsRawCopied),
                    duration: const Duration(seconds: 1),
                  ),
                );
              },
              icon: const Icon(Icons.content_copy_rounded, size: 16),
              label: Text(l10n.aiChatStepsCopyRaw),
            ),
          ),
        ],
      ),
    );
  }
}
