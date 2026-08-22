/// How a running plan's weeks line up with a periodization phase's weeks.
///
/// A phase is a run of 7-day weeks starting on the Monday of its start date.
/// A running plan is a list of weeks with no dates of its own. The link
/// between the two is a single number: [PeriodizationTarget.runPlanStartWeek],
/// the zero-based plan week that the phase's FIRST week maps to.
///
/// * `0` — phase and plan start together (the default, and what phases saved
///   before this existed behave like).
/// * `4` — the phase begins already on week 5 of the plan, for a plan you
///   joined in progress.
///
/// Weeks past the end of the plan wrap, so a 1-week maintenance plan applies
/// to every week of a 12-week phase, and a 4-week block repeats three times.
///
/// This is pure so the suggestion engine, the phase editor preview and the
/// bulk scheduler all derive the same mapping from the same rule.
class RunPlanWeekResolver {
  const RunPlanWeekResolver();

  /// Monday of the week containing [date].
  DateTime weekStart(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  /// Zero-based phase week of [date]. Negative before the phase starts.
  int phaseWeekOf({required DateTime phaseStart, required DateTime date}) =>
      weekStart(date).difference(weekStart(phaseStart)).inDays ~/ 7;

  /// Zero-based plan week that phase week [phaseWeek] maps to, or null when
  /// the plan has no weeks. Wraps in both directions so negative offsets and
  /// phase weeks beyond the plan length still resolve.
  int? planWeekFor({
    required int phaseWeek,
    required int planWeeks,
    int startWeek = 0,
  }) {
    if (planWeeks < 1) return null;
    final raw = startWeek + phaseWeek;
    return ((raw % planWeeks) + planWeeks) % planWeeks;
  }

  /// The offset that makes the plan's LAST week fall on the phase's last week
  /// — the alignment you want when the plan builds up to a race.
  int startWeekForFinish({required int phaseWeeks, required int planWeeks}) {
    if (planWeeks < 1) return 0;
    final raw = planWeeks - phaseWeeks;
    return ((raw % planWeeks) + planWeeks) % planWeeks;
  }

  /// How the plan covers the phase, for the editor's warning line.
  RunPlanCoverage coverage({
    required int phaseWeeks,
    required int planWeeks,
    int startWeek = 0,
  }) {
    if (planWeeks < 1 || phaseWeeks < 1) return RunPlanCoverage.empty;
    final available = planWeeks - startWeek;
    if (available == phaseWeeks) return RunPlanCoverage.exact;
    if (available > phaseWeeks) return RunPlanCoverage.planLonger;
    return RunPlanCoverage.planRepeats;
  }

  /// Plan weeks left unused after the phase ends, given [startWeek].
  /// Zero when the plan repeats or fits exactly.
  int leftoverPlanWeeks({
    required int phaseWeeks,
    required int planWeeks,
    int startWeek = 0,
  }) {
    final available = planWeeks - startWeek;
    return available > phaseWeeks ? available - phaseWeeks : 0;
  }

  /// How many times the plan restarts inside the phase. 0 when it never wraps.
  int repeatsWithin({
    required int phaseWeeks,
    required int planWeeks,
    int startWeek = 0,
  }) {
    if (planWeeks < 1) return 0;
    final lastRaw = startWeek + phaseWeeks - 1;
    return lastRaw < planWeeks ? 0 : lastRaw ~/ planWeeks;
  }
}

enum RunPlanCoverage {
  /// No plan, or a plan with no weeks.
  empty,

  /// The remaining plan weeks match the phase exactly.
  exact,

  /// The plan has more weeks left than the phase — its tail is never reached.
  planLonger,

  /// The plan is shorter than the phase and wraps around.
  planRepeats,
}
