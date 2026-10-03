import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/ai_chat_error_details.dart';
import 'package:workout_notes/utils/ai_error_localizer.dart';

/// The technical lines of an error (stage, code, provider, endpoint…), for the
/// "Details" section and the copy action.
List<String> aiErrorDetailLines(
  String error,
  AiChatErrorDetails? details,
  AppLocalizations l10n,
) {
  final code = aiErrorCode(error) ?? 'generic';
  if (details == null) return ['${l10n.aiChatErrorTechnicalCode}: $code'];
  return [
    '${l10n.aiChatErrorTechnicalStage}: ${details.stage}',
    [
      '${l10n.aiChatErrorTechnicalCode}: ${details.code}',
      if (details.httpStatus != null) 'HTTP ${details.httpStatus}',
      if (details.round != null)
        '${l10n.aiChatErrorTechnicalRound}: ${details.round}',
    ].join(' · '),
    if (details.provider != null || details.model != null)
      '${l10n.aiChatErrorTechnicalProvider}: '
          '${details.provider ?? '—'} / ${details.model ?? '—'}',
    if (details.endpoint != null)
      '${l10n.aiChatErrorTechnicalEndpoint}: ${details.endpoint}',
    if (details.requestCharacters != null)
      '${l10n.aiChatErrorTechnicalRequest}: '
          '${l10n.aiDevTurnChars(details.requestCharacters!)}',
    if (details.providerAttempts != null)
      '${l10n.aiChatErrorTechnicalAttempts}: ${details.providerAttempts}',
    if (details.compatibilityAdjustments.isNotEmpty)
      '${l10n.aiChatErrorTechnicalAdjustments}: '
          '${details.compatibilityAdjustments.join(', ')}',
    if (details.message?.isNotEmpty ?? false)
      '${l10n.aiChatErrorTechnicalDetail}: ${details.message}',
  ];
}

/// One localized line about what went wrong, an optional "Details" section
/// (open by default in developer mode, height-capped, with Copy), a Retry
/// button only when retrying makes sense, and a close button.
class AiErrorBanner extends StatefulWidget {
  final String error;
  final AiChatErrorDetails? details;
  final bool developerMode;

  /// Null hides the Retry button (the error has nothing to retry, or a turn
  /// is already running).
  final VoidCallback? onRetry;
  final VoidCallback onDismiss;

  const AiErrorBanner({
    super.key,
    required this.error,
    required this.onDismiss,
    this.details,
    this.developerMode = false,
    this.onRetry,
  });

  @override
  State<AiErrorBanner> createState() => _AiErrorBannerState();
}

class _AiErrorBannerState extends State<AiErrorBanner> {
  late bool _showDetails = widget.developerMode;

  @override
  void didUpdateWidget(covariant AiErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A different error starts collapsed again (open in developer mode).
    if (oldWidget.error != widget.error ||
        oldWidget.details != widget.details) {
      _showDetails = widget.developerMode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final onColor = colors.onErrorContainer;
    final lines = aiErrorDetailLines(widget.error, widget.details, l10n);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Semantics(
        liveRegion: true,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(13, 6, 2, 6),
          decoration: BoxDecoration(
            color: colors.errorContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 20, color: onColor),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                        localizeAiError(widget.error, l10n),
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.35,
                          fontWeight: FontWeight.w700,
                          color: onColor,
                        ),
                      ),
                    ),
                  ),
                  if (widget.onRetry != null)
                    IconButton(
                      tooltip: l10n.aiChatRetry,
                      color: onColor,
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                    ),
                  IconButton(
                    tooltip: l10n.aiChatErrorDismiss,
                    color: onColor,
                    onPressed: widget.onDismiss,
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 29, right: 11, bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => _showDetails = !_showDetails),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _showDetails
                                  ? l10n.aiChatErrorHideDetails
                                  : l10n.aiChatErrorShowDetails,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: onColor,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Icon(
                              _showDetails
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 18,
                              color: onColor,
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_showDetails) ...[
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 150),
                        child: SingleChildScrollView(
                          child: SelectableText(
                            lines.join('\n'),
                            style: theme.textTheme.labelSmall?.copyWith(
                              height: 1.35,
                              color: onColor.withValues(alpha: 0.9),
                            ),
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () async {
                            final messenger = ScaffoldMessenger.of(context);
                            await Clipboard.setData(
                              ClipboardData(text: lines.join('\n')),
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(l10n.aiChatErrorDetailsCopied),
                                duration: const Duration(seconds: 1),
                              ),
                            );
                          },
                          style: TextButton.styleFrom(foregroundColor: onColor),
                          icon: const Icon(
                            Icons.content_copy_rounded,
                            size: 16,
                          ),
                          label: Text(l10n.aiChatErrorCopyDetails),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
