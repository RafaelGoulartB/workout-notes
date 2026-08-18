import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';

/// Bottom sheet that resolves *which* weeks should receive the selected
/// week's targets.
///
/// Pops with the chosen week indexes (already excluding the selected week
/// itself; locked weeks are not selectable), or `null` when dismissed.
/// Quick actions cover the common cases ("following weeks", "all weeks")
/// and the checkbox list allows arbitrary multi-week picks.
class WeekCopySheet extends StatefulWidget {
  final int weekCount;
  final int selected;
  final DateTime firstWeekStart;
  final DateTime phaseEnd;
  final Set<int> customizedWeeks;
  final Set<int> lockedWeeks;
  final int? currentWeek;

  const WeekCopySheet({
    super.key,
    required this.weekCount,
    required this.selected,
    required this.firstWeekStart,
    required this.phaseEnd,
    required this.customizedWeeks,
    required this.lockedWeeks,
    required this.currentWeek,
  });

  static Future<Set<int>?> show(
    BuildContext context, {
    required int weekCount,
    required int selected,
    required DateTime firstWeekStart,
    required DateTime phaseEnd,
    required Set<int> customizedWeeks,
    required Set<int> lockedWeeks,
    required int? currentWeek,
  }) => showModalBottomSheet<Set<int>?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => WeekCopySheet(
      weekCount: weekCount,
      selected: selected,
      firstWeekStart: firstWeekStart,
      phaseEnd: phaseEnd,
      customizedWeeks: customizedWeeks,
      lockedWeeks: lockedWeeks,
      currentWeek: currentWeek,
    ),
  );

  @override
  State<WeekCopySheet> createState() => _WeekCopySheetState();
}

class _WeekCopySheetState extends State<WeekCopySheet> {
  final Set<int> _picked = {};

  DateTime _weekStart(int index) =>
      widget.firstWeekStart.add(Duration(days: 7 * index));

  DateTime _weekEnd(int index) {
    final nominal = _weekStart(index).add(const Duration(days: 6));
    return index == widget.weekCount - 1 && nominal.isAfter(widget.phaseEnd)
        ? widget.phaseEnd
        : nominal;
  }

  bool _pickable(int index) =>
      index != widget.selected && !widget.lockedWeeks.contains(index);

  Set<int> get _followingWeeks => {
    for (var i = widget.selected + 1; i < widget.weekCount; i++)
      if (!widget.lockedWeeks.contains(i)) i,
  };

  Set<int> get _allWeeks => {
    for (var i = 0; i < widget.weekCount; i++)
      if (_pickable(i)) i,
  };

  void _toggleAll() {
    final all = _allWeeks;
    setState(() {
      if (all.isNotEmpty && all.every(_picked.contains)) {
        _picked.clear();
      } else {
        _picked
          ..clear()
          ..addAll(all);
      }
    });
  }

  String? _statusLabel(AppLocalizations loc, int index) {
    if (widget.lockedWeeks.contains(index)) return loc.periodizationWeekLocked;
    if (index == 0) return loc.periodizationWeekBase;
    if (index == widget.currentWeek) return loc.periodizationWeekCurrent;
    if (widget.customizedWeeks.contains(index)) {
      return loc.periodizationWeekCustomized;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final formatter = DateFormat.MMMd(Intl.defaultLocale);
    final following = _followingWeeks;
    final all = _allWeeks;
    final allPicked = all.isNotEmpty && all.every(_picked.contains);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
              child: Text(
                loc.periodizationWeekCopyTitle(widget.selected + 1),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                loc.periodizationWeekCopyHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (following.isNotEmpty)
              _quickAction(
                context,
                icon: Icons.fast_forward_rounded,
                label: loc.periodizationApplyToFollowing,
                onTap: () => Navigator.pop(context, following),
              ),
            if (all.length > following.length)
              _quickAction(
                context,
                icon: Icons.select_all_rounded,
                label: loc.periodizationApplyToAll,
                onTap: () => Navigator.pop(context, all),
              ),
            const Divider(height: 20),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      loc.periodizationWeekCopyChoose,
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: all.isEmpty ? null : _toggleAll,
                    child: Text(
                      allPicked
                          ? loc.periodizationWeekCopyClear
                          : loc.periodizationWeekCopySelectAll,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                children: [
                  for (var i = 0; i < widget.weekCount; i++)
                    if (i != widget.selected)
                      CheckboxListTile(
                        value: _picked.contains(i),
                        onChanged: _pickable(i)
                            ? (checked) => setState(() {
                                checked ?? false
                                    ? _picked.add(i)
                                    : _picked.remove(i);
                              })
                            : null,
                        title: Text(
                          'S${i + 1} · ${formatter.format(_weekStart(i))}'
                          ' – ${formatter.format(_weekEnd(i))}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: _statusLabel(loc, i) == null
                            ? null
                            : Text(_statusLabel(loc, i)!),
                        controlAffinity: ListTileControlAffinity.leading,
                        dense: true,
                      ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _picked.isEmpty
                      ? null
                      : () => Navigator.pop(context, Set<int>.from(_picked)),
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                  label: Text(loc.periodizationWeekCopyApply(_picked.length)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _quickAction(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Material(
        color: theme.colorScheme.primaryContainer.withAlpha(70),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
