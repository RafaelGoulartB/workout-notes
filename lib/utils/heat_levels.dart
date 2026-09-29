/// Quartile thresholds of the days that had activity (values <= 0 are
/// ignored), so a heatmap level is relative to the person's own days.
///
/// Shared by the run and strength heatmaps.
List<double> heatThresholds(Iterable<double> values) {
  final sorted = values.where((v) => v > 0).toList()..sort();
  if (sorted.isEmpty) return const [0, 0, 0];
  double q(double f) => sorted[((sorted.length - 1) * f).round()];
  return [q(0.25), q(0.5), q(0.75)];
}

/// Heatmap intensity 0..4 for [value] against [thresholds] from
/// [heatThresholds]: 0 for no activity, 4 above the third quartile.
int heatLevel(double value, List<double> thresholds) {
  if (value <= 0) return 0;
  if (value <= thresholds[0]) return 1;
  if (value <= thresholds[1]) return 2;
  if (value <= thresholds[2]) return 3;
  return 4;
}
