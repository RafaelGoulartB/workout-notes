/// SQL predicates that decide which strength data "really happened".
///
/// Analytics, goals and history all count only:
///  * completed sets (`is_complete = 1`), never planned or unchecked ones;
///  * working sets (not warm-ups);
///  * finished workouts (`end_time` set), so a planned or still-open session
///    never leaks into totals.
///
/// The fragments assume the usual aliases: `s` for `sets` and `w` for
/// `workouts`.
abstract final class WorkoutSql {
  /// A working set that was actually performed.
  static const workSet = 's.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0';

  /// A workout that was started and ended.
  static const finished = 'w.end_time IS NOT NULL';

  /// A performed working set of a finished workout.
  static const countedSet = '$workSet AND $finished';
}
