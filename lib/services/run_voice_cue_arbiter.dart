/// Importance of a spoken cue. Higher values win when several run events land
/// in the same tracking update.
enum RunVoiceCuePriority { progress, coaching, achievement, safety, transition }

class RunVoiceCue {
  final String text;
  final RunVoiceCuePriority priority;
  final String key;

  const RunVoiceCue({
    required this.text,
    required this.priority,
    required this.key,
  });
}

/// Selects at most one short announcement per tracking update.
///
/// Transition cues are operational and must not be hidden by a split or pace
/// report. Duplicate keys are suppressed briefly so noisy GPS updates cannot
/// make the coach chatter.
class RunVoiceCueArbiter {
  final Map<String, DateTime> _spokenAt = {};

  RunVoiceCue? choose(Iterable<RunVoiceCue> candidates, {DateTime? now}) {
    final clock = now ?? DateTime.now();
    final fresh = candidates.where((cue) {
      final previous = _spokenAt[cue.key];
      return previous == null ||
          clock.difference(previous) >= const Duration(seconds: 8);
    }).toList();
    if (fresh.isEmpty) return null;
    fresh.sort((a, b) => b.priority.index.compareTo(a.priority.index));
    final chosen = fresh.first;
    _spokenAt[chosen.key] = clock;
    _spokenAt.removeWhere(
      (_, timestamp) =>
          clock.difference(timestamp) > const Duration(minutes: 5),
    );
    return chosen;
  }

  void reset() => _spokenAt.clear();
}
