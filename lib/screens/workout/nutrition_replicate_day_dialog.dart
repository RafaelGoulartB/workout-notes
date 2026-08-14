import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Calendar dialog used to choose multiple target dates for a diary day.
class NutritionReplicateDayDialog extends StatefulWidget {
  final DateTime sourceDate;

  const NutritionReplicateDayDialog({super.key, required this.sourceDate});

  @override
  State<NutritionReplicateDayDialog> createState() =>
      _NutritionReplicateDayDialogState();
}

class _NutritionReplicateDayDialogState
    extends State<NutritionReplicateDayDialog> {
  static final DateTime _firstDate = DateTime(2018, 1, 1);

  late final DateTime _sourceDate = _dateOnly(widget.sourceDate);
  late final DateTime _lastDate = _dateOnly(
    DateTime.now().add(const Duration(days: 365)),
  );
  late DateTime _focusedMonth = DateTime(_sourceDate.year, _sourceDate.month);
  final Set<DateTime> _selectedDates = <DateTime>{};

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final monthStart = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final gridStart = monthStart.subtract(
      Duration(days: monthStart.weekday % DateTime.daysPerWeek),
    );
    final canGoPrevious = _canFocusMonth(-1);
    final canGoNext = _canFocusMonth(1);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      contentPadding: EdgeInsets.zero,
      title: Text(loc.nutritionReplicateDayTitle),
      content: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    loc.nutritionReplicateDayHint,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  DateFormat.yMMMMEEEEd(locale).format(_sourceDate),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).previousMonthTooltip,
                      onPressed: canGoPrevious ? () => _changeMonth(-1) : null,
                      icon: const Icon(Icons.chevron_left_rounded),
                    ),
                    Expanded(
                      child: Text(
                        DateFormat.yMMMM(locale).format(_focusedMonth),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).nextMonthTooltip,
                      onPressed: canGoNext ? () => _changeMonth(1) : null,
                      icon: const Icon(Icons.chevron_right_rounded),
                    ),
                  ],
                ),
                _buildWeekdayHeader(locale, theme),
                const SizedBox(height: 4),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: DateTime.daysPerWeek,
                    mainAxisExtent: 40,
                  ),
                  itemCount: 42,
                  itemBuilder: (context, index) {
                    final date = _dateOnly(
                      gridStart.add(Duration(days: index)),
                    );
                    return _buildDay(
                      date,
                      locale,
                      theme,
                      isInCurrentMonth: date.month == _focusedMonth.month,
                    );
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  loc.nutritionReplicateDaySelectedCount(_selectedDates.length),
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.nutritionCancel),
        ),
        FilledButton(
          onPressed: _selectedDates.isEmpty
              ? null
              : () =>
                    Navigator.of(context).pop(Set<DateTime>.of(_selectedDates)),
          child: Text(loc.nutritionReplicateDayConfirm),
        ),
      ],
    );
  }

  Widget _buildWeekdayHeader(String locale, ThemeData theme) {
    return Row(
      children: [
        for (var index = 0; index < DateTime.daysPerWeek; index++)
          Expanded(
            child: Center(
              child: Text(
                DateFormat.E(locale)
                    .format(DateTime(2024, 1, 7 + index))
                    .characters
                    .first
                    .toUpperCase(),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDay(
    DateTime date,
    String locale,
    ThemeData theme, {
    required bool isInCurrentMonth,
  }) {
    final isSource = _isSameDay(date, _sourceDate);
    final isSelected = _selectedDates.contains(date);
    final isToday = _isSameDay(date, DateTime.now());
    final isInRange = !date.isBefore(_firstDate) && !date.isAfter(_lastDate);
    final enabled = isInCurrentMonth && isInRange && !isSource;
    final colors = theme.colorScheme;

    return Semantics(
      button: true,
      enabled: enabled,
      selected: isSelected,
      label: DateFormat.yMMMMEEEEd(locale).format(date),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Material(
          color: isSelected
              ? colors.primary
              : isSource
              ? colors.surfaceContainerHighest
              : Colors.transparent,
          shape: CircleBorder(
            side: isSource
                ? BorderSide(color: colors.outlineVariant)
                : isToday && !isSelected
                ? BorderSide(color: colors.primary, width: 1.5)
                : BorderSide.none,
          ),
          child: InkWell(
            onTap: enabled ? () => _toggleDate(date) : null,
            customBorder: const CircleBorder(),
            child: Center(
              child: Text(
                '${date.day}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: isSelected
                      ? colors.onPrimary
                      : enabled
                      ? isInCurrentMonth
                            ? colors.onSurface
                            : colors.onSurfaceVariant.withAlpha(120)
                      : colors.onSurfaceVariant.withAlpha(120),
                  fontWeight: isSelected || isToday
                      ? FontWeight.w800
                      : FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _toggleDate(DateTime date) {
    setState(() {
      if (_selectedDates.contains(date)) {
        _selectedDates.remove(date);
      } else {
        _selectedDates.add(date);
      }
    });
  }

  bool _canFocusMonth(int delta) {
    final candidate = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    final firstMonth = DateTime(_firstDate.year, _firstDate.month);
    final lastMonth = DateTime(_lastDate.year, _lastDate.month);
    return !candidate.isBefore(firstMonth) && !candidate.isAfter(lastMonth);
  }

  void _changeMonth(int delta) {
    if (!_canFocusMonth(delta)) return;
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + delta);
    });
  }

  static DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
