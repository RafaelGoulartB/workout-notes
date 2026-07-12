/// Values used to create a set before it is persisted as a workout record.
class WorkoutSetDraft {
  final double? weight;
  final int? reps;
  final double? distance;
  final int? timeSeconds;
  final bool isWarmup;
  final double? rpe;
  final String? comment;

  const WorkoutSetDraft({
    this.weight,
    this.reps,
    this.distance,
    this.timeSeconds,
    this.isWarmup = false,
    this.rpe,
    this.comment,
  });
}
