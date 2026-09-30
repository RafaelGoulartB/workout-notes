import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

/// Floating close / settings buttons plus the GPS and debug chips.
class RunRecordTopBar extends StatelessWidget {
  final RunTrackingState state;
  final bool usesGps;
  final bool debugSimulating;
  final String gpsLabel;
  final VoidCallback onClose;
  final VoidCallback onSettings;

  const RunRecordTopBar({
    super.key,
    required this.state,
    required this.usesGps,
    required this.debugSimulating,
    required this.gpsLabel,
    required this.onClose,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final surface = theme.colorScheme.surface.withValues(alpha: 0.92);
    final waiting =
        usesGps && state.isRecording && state.lat == null && !debugSimulating;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Material(
              color: surface,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close),
                onPressed: onClose,
              ),
            ),
            // The chips shrink (and ellipsize) instead of overflowing on
            // narrow phones.
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (usesGps) ...[
                    Material(
                      color: surface,
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(Icons.settings_outlined),
                        tooltip: loc.runRecordSettings,
                        onPressed: onSettings,
                      ),
                    ),
                    if (debugSimulating)
                      Flexible(
                        child: _Chip(
                          color: theme.colorScheme.tertiaryContainer,
                          child: Text(
                            loc.runRecordDebugSimulating,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onTertiaryContainer,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    if (!state.isActive && !debugSimulating)
                      Flexible(
                        child: _Chip(
                          color: surface,
                          child: Text(
                            gpsLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium,
                          ),
                        ),
                      ),
                    if (state.isActive && (state.hasWeakGps || waiting))
                      Flexible(
                        child: _Chip(
                          color: theme.colorScheme.errorContainer,
                          child: Text(
                            state.lat == null
                                ? loc.runRecordWaitingGps
                                : loc.runRecordWeakGps,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.colorScheme.onErrorContainer,
                            ),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final Color color;
  final Widget child;

  const _Chip({required this.color, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: child,
    );
  }
}
