import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/sleep_live_level.dart';

void main() {
  test('is silent at or below the room baseline', () {
    expect(SleepLiveLevel.normalize(levelDbfs: -55, baselineDbfs: -55), 0);
    expect(SleepLiveLevel.normalize(levelDbfs: -70, baselineDbfs: -55), 0);
  });

  test('fills the waves at the top of the range without clipping past it', () {
    expect(SleepLiveLevel.normalize(levelDbfs: -25, baselineDbfs: -55), 1);
    expect(SleepLiveLevel.normalize(levelDbfs: 0, baselineDbfs: -55), 1);
  });

  test('keeps quiet sounds visible and grows with loudness', () {
    final breath = SleepLiveLevel.normalize(levelDbfs: -51, baselineDbfs: -55);
    final voice = SleepLiveLevel.normalize(levelDbfs: -35, baselineDbfs: -55);
    // 4 dB above the baseline is well above its linear share (4/30).
    expect(breath, greaterThan(4 / SleepLiveLevel.rangeDb));
    expect(voice, greaterThan(breath));
    expect(voice, lessThan(1));
  });

  test('ignores non-finite readings', () {
    expect(
      SleepLiveLevel.normalize(levelDbfs: double.nan, baselineDbfs: -55),
      0,
    );
    expect(
      SleepLiveLevel.normalize(
        levelDbfs: double.negativeInfinity,
        baselineDbfs: -55,
      ),
      0,
    );
  });
}
