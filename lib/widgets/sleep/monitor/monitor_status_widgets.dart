import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class MissionStatusBanner extends StatelessWidget {
  const MissionStatusBanner({
    super.key,
    required this.label,
    required this.body,
  });
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.qr_code_2_rounded, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(color: scheme.onTertiaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class MonitorNightBackground extends StatelessWidget {
  final Widget child;

  const MonitorNightBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withAlpha(145),
            scheme.surface,
            scheme.surface,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: child,
    );
  }
}

class MonitorNightHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const MonitorNightHero({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Column(
          children: [
            Container(
              width: compact ? 48 : 72,
              height: compact ? 48 : 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withAlpha(26),
              ),
              child: Icon(
                icon,
                size: compact ? 26 : 38,
                color: theme.colorScheme.primary,
              ),
            ),
            SizedBox(height: compact ? 6 : 12),
            Text(
              title,
              style:
                  (compact
                          ? theme.textTheme.titleMedium
                          : theme.textTheme.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style:
                  (compact
                          ? theme.textTheme.bodySmall
                          : theme.textTheme.bodyLarge)
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        );
      },
    );
  }
}

class PermissionNotice extends StatelessWidget {
  final String text;
  final String action;
  final Future<bool> Function() onPressed;

  const PermissionNotice({
    super.key,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      color: scheme.errorContainer.withAlpha(70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconBadge(Icons.alarm_off_rounded, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onPressed,
              child: Text(action),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact list of bedtime tips (icon, title and one short paragraph each).
class TipsCard extends StatelessWidget {
  final String title;
  final List<(IconData, String, String)> tips;

  const TipsCard({super.key, required this.title, required this.tips});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.primary,
            ),
          ),
          for (final tip in tips) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIconBadge(tip.$1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tip.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tip.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class PermissionRow extends StatelessWidget {
  final bool granted;
  final String label;

  const PermissionRow({super.key, required this.granted, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green : Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(granted ? Icons.check_circle : Icons.warning_amber, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: ${granted ? AppLocalizations.of(context)!.commonOk : '—'}',
        ),
      ],
    );
  }
}

class LiveSignal extends StatelessWidget {
  final SleepMonitorSegment? segment;
  final double? noiseScore;
  final AppLocalizations loc;

  const LiveSignal({
    super.key,
    required this.segment,
    required this.noiseScore,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final classification = segment?.classification;
    final isNoise = classification == 'noise';
    final isInvalid = classification == 'invalid';
    final color = classification == null
        ? Theme.of(context).colorScheme.outline
        : isInvalid
        ? Theme.of(context).colorScheme.error
        : isNoise
        ? Colors.orange
        : Colors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isInvalid
                ? Icons.signal_wifi_bad
                : isNoise
                ? Icons.volume_up
                : Icons.volume_off,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              classification == null
                  ? loc.sleepMonitorWaitingSignal
                  : isInvalid
                  ? loc.sleepMonitorInvalidSignal
                  : isNoise
                  ? loc.sleepMonitorNoiseNow
                  : loc.sleepMonitorQuietNow,
            ),
          ),
          if (noiseScore != null)
            Text(
              noiseScore!.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}
