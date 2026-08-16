import 'package:workout_notes/models/periodization_target.dart';

/// Pure helpers for the weekly-override model used by the phase editor and
/// the plan wizard.
///
/// A phase is split into 7-day weeks. `overrides[i]` holds week `i`'s own
/// target, or `null` when the week inherits from the nearest previous
/// override (week 0 is the base). Stored targets form a full weekly
/// history; the sparse override list is the editable, diffed view.
class WeekOverrideResolver {
  const WeekOverrideResolver();

  /// Week start dates covering [start]..[end] (7-day chunks, last chunk may
  /// be shorter). Capped at [maxWeeks] to keep the editor usable.
  List<DateTime> computeWeekStarts(
    DateTime start,
    DateTime end, {
    int maxWeeks = 200,
  }) {
    final days = end.difference(start).inDays + 1;
    final count = (days / 7).ceil().clamp(1, maxWeeks);
    return [
      for (var i = 0; i < count; i++)
        dayOnly(start).add(Duration(days: 7 * i)),
    ];
  }

  /// End date of week [index]: the nominal 7-day end, trimmed to [endDate]
  /// for the last week.
  DateTime weekEnd(
    List<DateTime> weekStarts,
    int index,
    DateTime endDate,
  ) {
    final nominal = weekStarts[index].add(const Duration(days: 6));
    final last = index == weekStarts.length - 1;
    return last && nominal.isAfter(endDate) ? endDate : nominal;
  }

  /// The override at or before [index]; null when no week defines one.
  PeriodizationTarget? effectiveTarget(
    List<PeriodizationTarget?> overrides,
    int index,
  ) {
    for (var i = index; i >= 0; i--) {
      final target = overrides[i];
      if (target != null) return target;
    }
    return null;
  }

  /// Target in effect on [date]: the newest `validFrom` not after [date];
  /// ties broken by version. Before the phase start, falls back to the
  /// oldest stored target so history is readable.
  PeriodizationTarget? targetForDate(
    List<PeriodizationTarget> targets,
    DateTime date,
  ) {
    final eligible =
        targets.where((target) => !target.validFrom.isAfter(date)).toList()
          ..sort((a, b) {
            final byDate = b.validFrom.compareTo(a.validFrom);
            return byDate == 0 ? b.version.compareTo(a.version) : byDate;
          });
    if (eligible.isNotEmpty) return eligible.first;
    if (targets.isEmpty) return null;
    final oldest = [...targets]..sort((a, b) => a.version.compareTo(b.version));
    return oldest.first;
  }

  /// A copy of [source] pinned to [validFrom] as an unsaved editor draft
  /// (`id: ''`, `version: 0`).
  PeriodizationTarget copyOf(
    PeriodizationTarget source,
    DateTime validFrom,
  ) => source.copyWith(id: '', version: 0, validFrom: validFrom);

  /// True when both targets carry the same weekly values (empty targets are
  /// equivalent to null).
  bool targetsEquivalent(PeriodizationTarget? a, PeriodizationTarget? b) {
    final emptyA = a == null || a.isEmpty;
    final emptyB = b == null || b.isEmpty;
    if (emptyA && emptyB) return true;
    if (a == null || b == null) return false;
    return a.nutritionJson.toString() == b.nutritionJson.toString() &&
        a.trainingJson.toString() == b.trainingJson.toString() &&
        a.bodyJson.toString() == b.bodyJson.toString() &&
        a.sleepJson.toString() == b.sleepJson.toString();
  }

  /// Rebuilds the sparse override list from a full stored weekly history:
  /// week `i` gets its own override when its effective target differs from
  /// the previous week's effective target.
  List<PeriodizationTarget?> reconstructOverrides({
    required List<DateTime> weekStarts,
    required List<PeriodizationTarget> history,
  }) {
    return [
      for (var i = 0; i < weekStarts.length; i++)
        _overrideForWeek(weekStarts, history, i),
    ];
  }

  /// Same as [reconstructOverrides] but from the wizard's full weekly list
  /// (`weekly[i]` is already the effective target for week `i`).
  List<PeriodizationTarget?> prefillOverridesFromDraft({
    required List<DateTime> weekStarts,
    required List<PeriodizationTarget> weeklyTargets,
  }) {
    final overrides = List<PeriodizationTarget?>.filled(
      weekStarts.length,
      null,
    );
    for (var i = 0; i < weekStarts.length && i < weeklyTargets.length; i++) {
      final effective = weeklyTargets[i];
      final previous = i == 0 ? null : weeklyTargets[i - 1];
      if (!targetsEquivalent(effective, previous)) {
        overrides[i] = copyOf(effective, weekStarts[i]);
      }
    }
    return overrides;
  }

  PeriodizationTarget? _overrideForWeek(
    List<DateTime> weekStarts,
    List<PeriodizationTarget> history,
    int index,
  ) {
    final effective = targetForDate(history, weekStarts[index]);
    final previous = index == 0
        ? null
        : targetForDate(history, weekStarts[index - 1]);
    if (effective != null && !targetsEquivalent(effective, previous)) {
      return copyOf(effective, weekStarts[index]);
    }
    return null;
  }

  DateTime dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);
}
