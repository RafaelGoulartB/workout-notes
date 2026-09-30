import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// How the night's alarm went: when it rang, whether the smart window caught
/// a restless moment, and the one-tap "how did you wake up?" answer.
class SleepWakeUpCard extends StatelessWidget {
  final SleepMonitorSession session;
  final ValueChanged<int> onFeeling;

  const SleepWakeUpCard({
    super.key,
    required this.session,
    required this.onFeeling,
  });

  /// Nights whose alarm rang (or that ended by it) get the card.
  static bool appliesTo(SleepMonitorSession session) =>
      session.alarmAt != null &&
      (session.alarmFiredAt != null || session.endReason == 'alarm');

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final offset = session.utcOffsetEndMinutes ?? session.utcOffsetStartMinutes;
    final fired = session.alarmFiredAt ?? session.endedAt ?? session.alarmAt!;
    final firedClock = SleepUi.wallTime(fired, offset);
    final lead = session.smartWakeLeadMinutes;
    final windowStart = session.smartWindowStart;
    final String headline;
    String? reason;
    if (lead != null) {
      headline = loc.sleepSmartWakeRangEarly(firedClock, lead);
      reason = session.alarmTrigger == SleepMonitorSession.triggerAwake
          ? loc.sleepSmartWakeReasonAwake
          : loc.sleepSmartWakeReasonStirring;
    } else if (windowStart != null) {
      headline = loc.sleepSmartWakeRangAtDeadline(firedClock);
    } else {
      headline = loc.sleepAlarmRangAt(firedClock);
    }
    return AppSoftCard(
      key: const Key('sleep-wake-up-card'),
      padding: SleepUi.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SleepCardHeader(
            icon: windowStart != null
                ? Icons.auto_awesome_rounded
                : Icons.alarm_rounded,
            title: windowStart != null
                ? loc.sleepSmartWakeTitle
                : loc.sleepSettingsWakeSection,
          ),
          const SizedBox(height: 12),
          Text(
            headline,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 4),
            Text(
              reason,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
          if (windowStart != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SleepBadge(
                icon: Icons.schedule_rounded,
                label: loc.sleepSmartWakeBetween(
                  SleepUi.wallTime(windowStart, offset),
                  SleepUi.wallTime(session.alarmAt!, offset),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(loc.sleepWakeFeelingQuestion, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              key: const Key('sleep-wake-feeling'),
              emptySelectionAllowed: true,
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: SleepMonitorSession.feelingTired,
                  label: Text(loc.sleepWakeFeelingTired),
                ),
                ButtonSegment(
                  value: SleepMonitorSession.feelingOkay,
                  label: Text(loc.sleepWakeFeelingOkay),
                ),
                ButtonSegment(
                  value: SleepMonitorSession.feelingRefreshed,
                  label: Text(loc.sleepWakeFeelingRefreshed),
                ),
              ],
              selected: {?session.wakeFeeling},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) onFeeling(selection.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}
