import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ai/ai_chat_timeline.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';

/// One line for a `save_memory` / `delete_memory` result: "Memory saved: …",
/// "Memory updated: …" or "Memory removed: …", with Undo until it is used.
class AiMemoryLine extends StatelessWidget {
  final AiToolStep step;
  final VoidCallback? onUndo;

  const AiMemoryLine({super.key, required this.step, this.onUndo});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final outcome = step.fullOutcome;

    String text;
    IconData icon = Icons.psychology_alt_outlined;
    var undone = false;
    var canUndo = false;
    if (outcome == null) {
      text = l10n.aiChatStepNoResult;
    } else if (!outcome.ok) {
      text = l10n.aiChatMemoryFailed;
      icon = Icons.warning_amber_rounded;
    } else {
      final data = outcome.data ?? const <String, dynamic>{};
      final content = '${data['content'] ?? ''}'.trim();
      undone = data['undone'] == true;
      switch (data['status']) {
        case 'saved':
          text = l10n.aiChatMemorySaved(content);
          canUndo = true;
        case 'updated':
          text = l10n.aiChatMemoryUpdated(content);
          canUndo = true;
        case 'deleted':
          text = l10n.aiChatMemoryRemoved(content);
          canUndo = true;
        default:
          text = l10n.aiChatMemoryAlreadySaved;
      }
    }

    return AiAssistantFrame(
      showAvatar: false,
      padding: const EdgeInsets.fromLTRB(8, 2, 12, 2),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                decoration: undone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          if (undone)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                l10n.aiChatMemoryUndone,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            )
          else if (canUndo && onUndo != null)
            TextButton(
              onPressed: onUndo,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              child: Text(l10n.commonUndo),
            ),
        ],
      ),
    );
  }
}

/// A small centered status line for something the app did in the
/// conversation (a proposal was applied / rejected, a memory change undone).
/// Unknown event types render nothing.
class AiEventLine extends StatelessWidget {
  final Map<String, dynamic>? payload;

  const AiEventLine({super.key, required this.payload});

  /// Localized text of the event, or null when it has none to show.
  static String? textFor(Map<String, dynamic>? payload, AppLocalizations l10n) {
    if (payload == null) return null;
    switch (payload['type']) {
      case 'proposal_outcome':
        return switch (payload['status']) {
          'applied' => l10n.aiChatEventApplied,
          'rejected' => l10n.aiChatEventRejected,
          'stale' => l10n.aiChatEventStale,
          'failed' => l10n.aiChatEventFailed,
          'expired' => l10n.aiChatEventExpired,
          _ => null,
        };
      case 'memory_change_undone':
        return l10n.aiChatEventMemoryUndone;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = textFor(payload, l10n);
    if (text == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final applied =
        payload?['type'] == 'proposal_outcome' &&
        payload?['status'] == 'applied';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              applied ? Icons.check_circle_outline_rounded : Icons.circle,
              size: applied ? 14 : 5,
              color: applied ? colors.primary : colors.outline,
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
