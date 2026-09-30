import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// Full-screen countdown before recording starts. Tapping anywhere skips it.
class RunRecordCountdown extends StatelessWidget {
  final int value;
  final VoidCallback onSkip;

  const RunRecordCountdown({
    super.key,
    required this.value,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return GestureDetector(
      key: const ValueKey('run-countdown'),
      behavior: HitTestBehavior.opaque,
      onTap: onSkip,
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.52),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$value',
                semanticsLabel: loc.runRecordCountdown('$value'),
                style: theme.textTheme.displayLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 104,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                loc.runRecordCountdownSkip,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
