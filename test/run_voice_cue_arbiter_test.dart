import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/run_voice_cue_arbiter.dart';

void main() {
  test('selects one highest-priority cue', () {
    final arbiter = RunVoiceCueArbiter();
    final cue = arbiter.choose(const [
      RunVoiceCue(
        text: 'Kilometer 1.',
        priority: RunVoiceCuePriority.progress,
        key: 'split-1',
      ),
      RunVoiceCue(
        text: 'Recover.',
        priority: RunVoiceCuePriority.transition,
        key: 'recovery-1',
      ),
    ]);
    expect(cue?.text, 'Recover.');
  });

  test('suppresses the same cue briefly', () {
    final arbiter = RunVoiceCueArbiter();
    final now = DateTime(2026, 1, 1);
    const cue = RunVoiceCue(
      text: 'Weak GPS signal.',
      priority: RunVoiceCuePriority.safety,
      key: 'gps-weak',
    );
    expect(arbiter.choose(const [cue], now: now), isNotNull);
    expect(
      arbiter.choose(const [cue], now: now.add(const Duration(seconds: 2))),
      isNull,
    );
  });
}
