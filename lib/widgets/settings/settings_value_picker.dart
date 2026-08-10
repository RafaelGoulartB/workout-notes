import 'package:flutter/material.dart';

import 'settings_sheet_helpers.dart';

/// Tappable row showing the current [displayValue] and a chevron. Tapping
/// opens a bottom sheet that lets the user pick from [choices]. The
/// chosen value is forwarded to [onChanged].
///
/// Use for "single value from a small set" settings like rest time,
/// where chips or inline rows would either wrap to multiple lines or
/// take too much vertical space.
class SettingsValuePickerTile<T> extends StatelessWidget {
  final IconData icon;
  final String title;
  final T currentValue;
  final String displayValue;
  final List<T> choices;
  final String Function(T) formatChoice;
  final String sheetTitle;
  final ValueChanged<T> onChanged;

  const SettingsValuePickerTile({
    super.key,
    required this.icon,
    required this.title,
    required this.currentValue,
    required this.displayValue,
    required this.choices,
    required this.formatChoice,
    required this.sheetTitle,
    required this.onChanged,
  });

  Future<void> _openSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<T>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _ChoiceSheet<T>(
        icon: icon,
        sheetTitle: sheetTitle,
        choices: choices,
        currentValue: currentValue,
        formatChoice: formatChoice,
      ),
    );
    if (selected != null) onChanged(selected);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openSheet(context),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              displayValue,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceSheet<T> extends StatelessWidget {
  final IconData icon;
  final String sheetTitle;
  final List<T> choices;
  final T currentValue;
  final String Function(T) formatChoice;

  const _ChoiceSheet({
    required this.icon,
    required this.sheetTitle,
    required this.choices,
    required this.currentValue,
    required this.formatChoice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SettingsSheetTitle(icon: icon, title: sheetTitle),
          const Divider(height: 1, thickness: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: choices.length,
              itemBuilder: (ctx, i) {
                final v = choices[i];
                final selected = v == currentValue;
                return InkWell(
                  onTap: () => Navigator.pop(ctx, v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            formatChoice(v),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          color: selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.outlineVariant,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}