import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final colors = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isOk = _isSuccessful;
    final statusColor = isOk ? colors.primary : colors.error;

    return Padding(
      padding: const EdgeInsets.fromLTRB(56, 3, 16, 7),
      child: Material(
        color: colors.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(24),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        _toolIcon(widget.message.toolName),
                        size: 17,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.toolLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                isOk ? l10n.aiToolCompleted : l10n.aiToolFailed,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? .5 : 0,
                      duration: const Duration(milliseconds: 180),
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                AnimatedCrossFade(
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: SelectableText(
                        _preview(l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  crossFadeState: _expanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  duration: const Duration(milliseconds: 180),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _isSuccessful {
    if (widget.message.toolResult != null) return widget.message.toolResult!.ok;
    try {
      final value = jsonDecode(widget.message.content ?? '');
      return value is! Map || value['ok'] != false;
    } catch (_) {
      return true;
    }
  }

  String _preview(AppLocalizations l10n) {
    final raw = widget.message.content;
    if (raw == null || raw.isEmpty) return l10n.aiToolNoContent;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map && decoded['ok'] == false) {
        return '${l10n.aiToolError}: ${decoded['message'] ?? decoded['code'] ?? l10n.aiToolUnknown}';
      }
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return raw;
    }
  }

  IconData _toolIcon(String? name) {
    switch (name) {
      case 'get_sleep_summary':
      case 'analyze_sleep_performance':
        return Icons.bedtime_outlined;
      case 'get_nutrition_summary':
      case 'analyze_nutrition_body_trend':
        return Icons.restaurant_outlined;
      case 'get_weekly_recovery_trend':
        return Icons.battery_charging_full_rounded;
      case 'list_body_measurements':
        return Icons.monitor_weight_outlined;
      case 'list_goals':
      case 'get_goal_progress_history':
        return Icons.flag_outlined;
      case 'list_routines':
      case 'get_routine_detail':
        return Icons.event_note_outlined;
      default:
        return Icons.storage_rounded;
    }
  }
}
