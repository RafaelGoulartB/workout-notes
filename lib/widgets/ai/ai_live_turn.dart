import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_state.dart';
import 'package:workout_notes/widgets/ai/ai_markdown.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';
import 'package:workout_notes/widgets/ai/ai_tool_presentation.dart';
import 'package:workout_notes/widgets/ui/second_ticker.dart';

/// Seconds after which the live turn also shows how long it has been running.
const int kAiElapsedAfterSeconds = 10;

/// Longest a streamed delta waits before the draft is redrawn.
const Duration kAiDraftRedrawInterval = Duration(milliseconds: 90);

/// Localized status of the running turn ("Thinking…", "Reading: Sleep
/// summary, Nutrition", "Writing…", …).
String aiTurnPhaseText(AiTurnProgress turn, AppLocalizations l10n) {
  if (turn.cancelling) return l10n.aiChatPhaseStopping;
  switch (turn.phase) {
    case AiTurnPhase.waiting:
    case AiTurnPhase.thinking:
      return l10n.aiChatPhaseThinking;
    case AiTurnPhase.writing:
      return l10n.aiChatPhaseWriting;
    case AiTurnPhase.compacting:
      return l10n.aiChatPhaseCompacting;
    case AiTurnPhase.usingTools:
      final labels = <String>[];
      for (final name in turn.toolNames) {
        final label = AiToolPresentation.label(name, l10n);
        if (!labels.contains(label)) labels.add(label);
      }
      if (labels.isEmpty) return l10n.aiChatPhaseThinking;
      final shown = labels.take(3).join(', ');
      return l10n.aiChatPhaseReading(labels.length > 3 ? '$shown…' : shown);
  }
}

/// The assistant bubble of the turn that is running in this conversation: a
/// phase line (announced to screen readers), the elapsed time once it is
/// long, and the answer streamed so far as markdown.
class AiLiveTurnBubble extends StatefulWidget {
  final AiTurnProgress turn;
  final bool showAvatar;

  const AiLiveTurnBubble({
    super.key,
    required this.turn,
    this.showAvatar = true,
  });

  @override
  State<AiLiveTurnBubble> createState() => _AiLiveTurnBubbleState();
}

class _AiLiveTurnBubbleState extends State<AiLiveTurnBubble> {
  late String _draft = widget.turn.draftText;
  DateTime _applied = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;

  @override
  void didUpdateWidget(covariant AiLiveTurnBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.turn.draftText;
    if (next == _draft) return;
    // A new round starts from an empty draft: show that at once.
    if (next.length < _draft.length) {
      _timer?.cancel();
      _timer = null;
      _apply();
      return;
    }
    final wait = kAiDraftRedrawInterval - DateTime.now().difference(_applied);
    if (wait <= Duration.zero) {
      _apply();
    } else {
      _timer ??= Timer(wait, () {
        _timer = null;
        if (mounted) setState(_applyValue);
      });
    }
  }

  void _applyValue() {
    _draft = widget.turn.draftText;
    _applied = DateTime.now();
  }

  void _apply() => _applyValue();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final phase = aiTurnPhaseText(widget.turn, l10n);

    return AiAssistantFrame(
      showAvatar: widget.showAvatar,
      padding: EdgeInsets.fromLTRB(8, widget.showAvatar ? 12 : 4, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showAvatar)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 7),
              child: Text(
                l10n.aiChatCoachName,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (_draft.isNotEmpty) ...[
            AiMarkdown(text: _draft, selectable: false),
            const SizedBox(height: 4),
          ],
          Semantics(
            liveRegion: true,
            label: phase,
            child: ExcludeSemantics(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Flexible(
                    child: Text(
                      phase,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SecondTicker(
                    builder: (context) {
                      final seconds = DateTime.now()
                          .difference(widget.turn.startedAt)
                          .inSeconds;
                      if (seconds < kAiElapsedAfterSeconds) {
                        return const SizedBox.shrink();
                      }
                      return Text(
                        ' · ${l10n.aiChatElapsedSeconds(seconds)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Developer-mode line under the last answer: rounds, characters sent,
/// tokens (when the provider reported them) and total duration.
class AiTurnInfoRow extends StatelessWidget {
  final List<AiRoundDiagnostics> rounds;

  const AiTurnInfoRow({super.key, required this.rounds});

  @override
  Widget build(BuildContext context) {
    if (rounds.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    var chars = 0;
    var ms = 0;
    int? prompt;
    int? cached;
    int? completion;
    for (final round in rounds) {
      chars += round.requestChars;
      ms += round.durationMs;
      if (round.promptTokens != null) {
        prompt = (prompt ?? 0) + round.promptTokens!;
      }
      if (round.cachedTokens != null) {
        cached = (cached ?? 0) + round.cachedTokens!;
      }
      if (round.completionTokens != null) {
        completion = (completion ?? 0) + round.completionTokens!;
      }
    }
    final parts = <String>[
      l10n.aiDevTurnRounds(rounds.length),
      l10n.aiDevTurnChars(chars),
      if (prompt != null || completion != null)
        cached != null
            ? l10n.aiDevTurnTokens(
                '${prompt ?? '–'}',
                '$cached',
                '${completion ?? '–'}',
              )
            : l10n.aiDevTurnTokensNoCache(
                '${prompt ?? '–'}',
                '${completion ?? '–'}',
              ),
      l10n.aiChatElapsedSeconds(math.max(1, (ms / 1000).round())),
    ];
    return AiAssistantFrame(
      showAvatar: false,
      padding: const EdgeInsets.fromLTRB(8, 0, 12, 8),
      child: Text(
        parts.join(' · '),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.outline,
          fontFamily: 'monospace',
        ),
      ),
    );
  }
}
