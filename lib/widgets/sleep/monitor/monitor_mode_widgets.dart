import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/widgets/sleep/monitor/sleep_monitor_texts.dart';

IconData modeIcon(SleepMonitoringMode mode) {
  return switch (mode) {
    SleepMonitoringMode.alarmWithoutMission => Icons.alarm_rounded,
    SleepMonitoringMode.alarmWithMission => Icons.qr_code_2_rounded,
    SleepMonitoringMode.monitoringOnly => Icons.graphic_eq_rounded,
  };
}

/// Compact pill with the selected monitoring mode; opens the mode picker.
class ModePill extends StatelessWidget {
  const ModePill({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.tapKey = const Key('sleep-monitor-mode'),
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Key tapKey;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainerHigh.withAlpha(170),
      shape: StadiumBorder(
        side: BorderSide(color: scheme.outlineVariant.withAlpha(120)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: tapKey,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.unfold_more_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ModeChoiceTile extends StatelessWidget {
  const ModeChoiceTile({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerLow;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final stateIcon = Icon(
          locked
              ? Icons.settings_outlined
              : selected
              ? Icons.check_circle_rounded
              : Icons.circle_outlined,
          color: selected ? scheme.primary : scheme.onSurfaceVariant,
          size: 22,
        );
        final titleText = Text(
          title,
          maxLines: compact ? 2 : null,
          overflow: compact ? TextOverflow.ellipsis : null,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        );
        final bodyText = Text(
          body,
          style: theme.textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        );
        return Material(
          color: background,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: EdgeInsets.all(compact ? 12 : 16),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              icon,
                              color: selected ? scheme.primary : null,
                              size: 22,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: titleText),
                            const SizedBox(width: 6),
                            stateIcon,
                          ],
                        ),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsetsDirectional.only(start: 32),
                          child: bodyText,
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(icon, color: selected ? scheme.primary : null),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              titleText,
                              const SizedBox(height: 4),
                              bodyText,
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        stateIcon,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// Bottom sheet listing the monitoring modes in [modeOrder]. Resolves with the
/// chosen mode, or `null` when dismissed or when a locked mode was tapped (in
/// which case [onLockedTap] runs after the sheet closes).
Future<SleepMonitoringMode?> showSleepModePicker(
  BuildContext context, {
  required List<SleepMonitoringMode> modeOrder,
  required SleepMonitoringMode selected,
  required bool Function(SleepMonitoringMode mode) isLocked,
  required VoidCallback onLockedTap,
}) {
  final loc = AppLocalizations.of(context)!;
  return showModalBottomSheet<SleepMonitoringMode>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.82;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetHeight),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  child: Text(
                    loc.sleepMonitorModeSection,
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final mode in modeOrder)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ModeChoiceTile(
                              icon: modeIcon(mode),
                              title: sleepMonitorModeTitle(loc, mode),
                              body: isLocked(mode)
                                  ? loc.sleepMonitorModeMissionUnavailable
                                  : sleepMonitorModeBody(loc, mode),
                              selected: mode == selected,
                              locked: isLocked(mode),
                              onTap: () {
                                if (isLocked(mode)) {
                                  Navigator.pop(sheetContext);
                                  onLockedTap();
                                  return;
                                }
                                Navigator.pop(sheetContext, mode);
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}
