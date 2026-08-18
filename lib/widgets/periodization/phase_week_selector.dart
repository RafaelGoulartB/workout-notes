import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Week context header for the phase form target section.
///
/// This is the *parent* of every target card below it: the stepper picks
/// which week the cards edit. Weeks are 0-indexed: index 0 is the base
/// week (always shown as such), indexes in [customizedWeeks] carry their
/// own override and the remaining ones inherit from the nearest previous
/// customized week. Weeks in [lockedWeeks] already ended and are
/// view-only.
class PhaseWeekSelector extends StatelessWidget {
  final int weekCount;
  final int selected;
  final DateTime firstWeekStart;
  final DateTime phaseEnd;
  final Set<int> customizedWeeks;
  final Set<int> lockedWeeks;
  final int? currentWeek;
  final ValueChanged<int> onSelect;
  final VoidCallback? onCustomize;
  final VoidCallback? onUseInheritance;
  final VoidCallback? onCopy;

  const PhaseWeekSelector({
    super.key,
    required this.weekCount,
    required this.selected,
    required this.firstWeekStart,
    required this.phaseEnd,
    required this.customizedWeeks,
    required this.lockedWeeks,
    required this.currentWeek,
    required this.onSelect,
    this.onCustomize,
    this.onUseInheritance,
    this.onCopy,
  });

  DateTime weekStart(int index) =>
      firstWeekStart.add(Duration(days: 7 * index));

  DateTime weekEnd(int index) {
    final nominal = weekStart(index).add(const Duration(days: 6));
    return index == weekCount - 1 && nominal.isAfter(phaseEnd)
        ? phaseEnd
        : nominal;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final locked = lockedWeeks.contains(selected);
    final formatter = DateFormat.MMMd(Intl.defaultLocale);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _stepperButton(
              context,
              icon: Icons.chevron_left_rounded,
              onPressed: selected > 0 ? () => onSelect(selected - 1) : null,
              semanticLabel: loc.periodizationWeekPrevious,
              buttonKey: const Key('weekStepperPrev'),
            ),
            Expanded(
              child: Column(
                children: [
                  Text(
                    loc.periodizationWeekOf(selected + 1, weekCount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${formatter.format(weekStart(selected))}'
                    ' – ${formatter.format(weekEnd(selected))}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            _stepperButton(
              context,
              icon: Icons.chevron_right_rounded,
              onPressed: selected < weekCount - 1
                  ? () => onSelect(selected + 1)
                  : null,
              semanticLabel: loc.periodizationWeekNext,
              buttonKey: const Key('weekStepperNext'),
            ),
            if (_hasMenuActions()) ...[
              const SizedBox(width: 2),
              _weekMenu(context),
            ],
          ],
        ),
        if (locked) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 15,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.periodizationWeekLockedHelp,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _stepperButton(
    BuildContext context, {
    required IconData icon,
    required VoidCallback? onPressed,
    String? semanticLabel,
    Key? buttonKey,
  }) {
    final theme = Theme.of(context);
    return IconButton(
      key: buttonKey,
      onPressed: onPressed,
      icon: Icon(icon),
      tooltip: semanticLabel,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withAlpha(
          90,
        ),
        disabledBackgroundColor: Colors.transparent,
      ),
    );
  }

  bool _hasMenuActions() {
    final locked = lockedWeeks.contains(selected);
    final customized = customizedWeeks.contains(selected);
    final canCopy = onCopy != null && !locked && weekCount > 1 &&
        (selected == 0 || customized);
    final canCustomize =
        onCustomize != null && !locked && selected > 0 && !customized;
    final canUseInheritance =
        onUseInheritance != null && !locked && selected > 0 && customized;
    return canCopy || canCustomize || canUseInheritance;
  }

  Widget _weekMenu(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Builder(
      builder: (builderContext) => IconButton(
        key: const Key('weekMenu'),
        onPressed: () => _showMenu(builderContext),
        icon: const Icon(Icons.more_vert_rounded),
        tooltip: loc.periodizationWeekMenu,
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
        style: IconButton.styleFrom(
          backgroundColor:
              theme.colorScheme.surfaceContainerHighest.withAlpha(90),
        ),
      ),
    );
  }

  Future<void> _showMenu(BuildContext anchorContext) async {
    final loc = AppLocalizations.of(anchorContext)!;
    final theme = Theme.of(anchorContext);
    final locked = lockedWeeks.contains(selected);
    final customized = customizedWeeks.contains(selected);
    final canCopy = onCopy != null && !locked && weekCount > 1 &&
        (selected == 0 || customized);
    final canCustomize =
        onCustomize != null && !locked && selected > 0 && !customized;
    final canUseInheritance =
        onUseInheritance != null && !locked && selected > 0 && customized;

    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(anchorContext).context.findRenderObject()
        as RenderBox?;
    if (box == null || overlay == null) return;
    final topLeft = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      topLeft.dx,
      topLeft.dy + box.size.height + 4,
      overlay.size.width - topLeft.dx - box.size.width,
      overlay.size.height - topLeft.dy,
    );

    final picked = await showMenu<_WeekMenuAction>(
      context: anchorContext,
      position: position,
      items: [
        if (canCustomize)
          PopupMenuItem<_WeekMenuAction>(
            value: _WeekMenuAction.customize,
            child: Row(
              children: [
                Icon(
                  Icons.edit_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(loc.periodizationWeekCustomize),
              ],
            ),
          ),
        if (canUseInheritance)
          PopupMenuItem<_WeekMenuAction>(
            value: _WeekMenuAction.useInheritance,
            child: Row(
              children: [
                Icon(
                  Icons.undo_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(loc.periodizationWeekUseInheritance),
              ],
            ),
          ),
        if (canCopy)
          PopupMenuItem<_WeekMenuAction>(
            value: _WeekMenuAction.copy,
            child: Row(
              children: [
                Icon(
                  Icons.copy_all_rounded,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 10),
                Text(loc.periodizationWeekCopyTo),
              ],
            ),
          ),
      ],
    );

    if (picked == null) return;
    switch (picked) {
      case _WeekMenuAction.copy:
        onCopy?.call();
      case _WeekMenuAction.customize:
        onCustomize?.call();
      case _WeekMenuAction.useInheritance:
        onUseInheritance?.call();
    }
  }
}

enum _WeekMenuAction { customize, useInheritance, copy }
