import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/alarm_wake_settings.dart';
import 'package:workout_notes/widgets/sleep/monitor/monitor_mode_widgets.dart';

/// Short label of a smart window choice: "Off" or "30 min".
String smartWindowLabel(AppLocalizations loc, int minutes) =>
    minutes <= 0
    ? loc.sleepSmartWakeWindowOff
    : loc.commonMinutesShort(minutes);

/// Short label of a volume rise choice: "Off", "30 s" or "2 min".
String alarmRampLabel(AppLocalizations loc, int seconds) {
  if (seconds <= 0) return loc.alarmRampOff;
  if (seconds < 60) return loc.commonSecondsShort(seconds);
  return loc.commonMinutesShort(seconds ~/ 60);
}

String smartWakeSensitivityTitle(
  AppLocalizations loc,
  SmartWakeSensitivity value,
) => switch (value) {
  SmartWakeSensitivity.sensitive => loc.sleepSmartWakeSensitive,
  SmartWakeSensitivity.balanced => loc.sleepSmartWakeBalanced,
  SmartWakeSensitivity.conservative => loc.sleepSmartWakeConservative,
};

String smartWakeSensitivityBody(
  AppLocalizations loc,
  SmartWakeSensitivity value,
) => switch (value) {
  SmartWakeSensitivity.sensitive => loc.sleepSmartWakeSensitiveBody,
  SmartWakeSensitivity.balanced => loc.sleepSmartWakeBalancedBody,
  SmartWakeSensitivity.conservative => loc.sleepSmartWakeConservativeBody,
};

IconData smartWakeSensitivityIcon(SmartWakeSensitivity value) =>
    switch (value) {
      SmartWakeSensitivity.sensitive => Icons.waves_rounded,
      SmartWakeSensitivity.balanced => Icons.balance_rounded,
      SmartWakeSensitivity.conservative => Icons.wb_twilight_rounded,
    };

/// Bottom sheet to choose the smart window and its sensitivity. Returns the
/// edited settings, or null when dismissed.
Future<AlarmWakeSettings?> showSmartWakeSheet(
  BuildContext context,
  AlarmWakeSettings initial,
) {
  return showModalBottomSheet<AlarmWakeSettings>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => _SmartWakeSheet(initial: initial),
  );
}

class _SmartWakeSheet extends StatefulWidget {
  const _SmartWakeSheet({required this.initial});

  final AlarmWakeSettings initial;

  @override
  State<_SmartWakeSheet> createState() => _SmartWakeSheetState();
}

class _SmartWakeSheetState extends State<_SmartWakeSheet> {
  late AlarmWakeSettings _value = widget.initial;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.86;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                loc.sleepSmartWakeTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                loc.sleepSmartWakeBody,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 18),
              Text(loc.sleepSmartWakeWindow, style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final minutes in AlarmWakeSettings.windowOptions)
                    ChoiceChip(
                      key: Key('smart-window-$minutes'),
                      label: Text(smartWindowLabel(loc, minutes)),
                      selected: _value.windowMinutes == minutes,
                      onSelected: (_) => setState(
                        () => _value = _value.copyWith(windowMinutes: minutes),
                      ),
                    ),
                ],
              ),
              if (_value.smartWindowEnabled) ...[
                const SizedBox(height: 20),
                Text(
                  loc.sleepSmartWakeSensitivity,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 8),
                for (final sensitivity in SmartWakeSensitivity.values)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ModeChoiceTile(
                      key: Key('smart-sensitivity-${sensitivity.wireValue}'),
                      icon: smartWakeSensitivityIcon(sensitivity),
                      title: smartWakeSensitivityTitle(loc, sensitivity),
                      body: smartWakeSensitivityBody(loc, sensitivity),
                      selected: _value.sensitivity == sensitivity,
                      locked: false,
                      onTap: () => setState(
                        () =>
                            _value = _value.copyWith(sensitivity: sensitivity),
                      ),
                    ),
                  ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        loc.sleepSmartWakeBedPartner,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              FilledButton(
                key: const Key('smart-wake-save'),
                onPressed: () => Navigator.pop(context, _value),
                child: Text(loc.commonSave),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
