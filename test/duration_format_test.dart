import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/utils/run_formatters.dart';

void main() {
  test('clock-style formats', () {
    expect(DurationFormat.minSec(342), '5:42');
    expect(DurationFormat.minSec(5705), '95:05');
    expect(DurationFormat.mmss(342), '05:42');
    expect(DurationFormat.hms(3909), '1:05:09');
    expect(
      DurationFormat.clock(const Duration(hours: 1, minutes: 5)),
      '01:05:00',
    );
    expect(DurationFormat.minSecOrSeconds(90), '1:30');
    expect(DurationFormat.minSecOrSeconds(45), '45s');
  });

  test('elapsed workout time', () {
    expect(DurationFormat.elapsed(342), '05:42');
    expect(DurationFormat.elapsed(3909), '1h05min');
  });

  test('RunFormatters delegates to the same output', () {
    expect(RunFormatters.minSec(342), DurationFormat.minSec(342));
    expect(RunFormatters.mmss(342), DurationFormat.mmss(342));
    expect(RunFormatters.hms(3909), DurationFormat.hms(3909));
  });
}
