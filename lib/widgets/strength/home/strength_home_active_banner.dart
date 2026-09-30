import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// Banner for an unfinished workout of today: a live timer and a one-tap way
/// back into it. Owns its one-second ticker so the hub does not rebuild.
class StrengthActiveBanner extends StatefulWidget {
  final Map<String, dynamic> workout;
  final VoidCallback onTap;

  const StrengthActiveBanner({
    super.key,
    required this.workout,
    required this.onTap,
  });

  @override
  State<StrengthActiveBanner> createState() => _StrengthActiveBannerState();
}

class _StrengthActiveBannerState extends State<StrengthActiveBanner> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String? _elapsed() {
    final start = DateTime.tryParse(
      widget.workout['start_time'] as String? ?? '',
    );
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    if (elapsed.isNegative) return '--:--';
    return RunFormatters.duration(elapsed.inSeconds);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Material(
      color: colors.primary,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const Key('strength-active-banner'),
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Row(
            children: [
              Icon(Icons.timer_outlined, color: colors.onPrimary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.strengthHomeContinue,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: colors.onPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _elapsed() == null
                          ? loc.workoutHomeActiveNotStarted
                          : loc.strengthHomeContinueSubtitle(_elapsed()!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onPrimary.withAlpha(220),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.play_arrow_rounded, color: colors.onPrimary),
            ],
          ),
        ),
      ),
    );
  }
}
