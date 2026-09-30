import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_tracking_state.dart';

/// Primary actions of the record sheet: Start before the run; Pause/Resume,
/// Lap and Finish while it is recording.
class RunRecordControls extends StatelessWidget {
  final RunTrackingState state;
  final bool busy;
  final bool showLap;
  final bool showDebugSimulate;
  final VoidCallback onStart;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onLap;
  final VoidCallback onFinish;
  final VoidCallback onDebugSimulate;

  const RunRecordControls({
    super.key,
    required this.state,
    required this.busy,
    required this.showLap,
    required this.showDebugSimulate,
    required this.onStart,
    required this.onPause,
    required this.onResume,
    required this.onLap,
    required this.onFinish,
    required this.onDebugSimulate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final filled = FilledButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      textStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
    final outlined = OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(52),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      side: BorderSide(
        color: theme.colorScheme.outline.withValues(alpha: 0.7),
        width: 1.5,
      ),
    );

    if (busy) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!state.isActive) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton.icon(
            key: const ValueKey('run-start'),
            onPressed: onStart,
            style: filled,
            icon: const Icon(Icons.play_arrow_rounded, size: 26),
            label: Text(loc.runRecordStart),
          ),
          if (showDebugSimulate) ...[
            const SizedBox(height: 2),
            TextButton.icon(
              onPressed: onDebugSimulate,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                minimumSize: const Size.fromHeight(36),
                textStyle: theme.textTheme.labelMedium,
              ),
              icon: const Icon(Icons.bug_report_outlined, size: 16),
              label: Text(loc.runRecordDebugSimulate),
            ),
          ],
        ],
      );
    }

    // Auto-paused reads as paused: the button lets the runner carry on early.
    final resumable = state.isPaused || state.isAutoPaused;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('run-pause-resume'),
            onPressed: resumable ? onResume : onPause,
            style: outlined,
            icon: Icon(
              resumable ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 22,
            ),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(resumable ? loc.runRecordResume : loc.runRecordPause),
            ),
          ),
        ),
        if (showLap) ...[
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              key: const ValueKey('run-lap'),
              onPressed: state.isPaused ? null : onLap,
              style: outlined,
              icon: const Icon(Icons.flag_outlined, size: 20),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(loc.runLapButton),
              ),
            ),
          ),
        ],
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            key: const ValueKey('run-finish'),
            onPressed: onFinish,
            style: filled.copyWith(
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8),
              ),
            ),
            icon: const Icon(Icons.stop_rounded, size: 22),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(loc.runRecordFinish),
            ),
          ),
        ),
      ],
    );
  }
}
