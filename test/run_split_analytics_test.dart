import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_split_analytics.dart';

RunSplit _split(int km, double? pace, {bool partial = false, double? meters}) {
  final distance = meters ?? (partial ? 400 : 1000);
  return RunSplit(
    km: km,
    distanceMeters: distance,
    durationSeconds: pace == null ? 0 : (pace * distance / 1000).round(),
    paceSecPerKm: pace,
    isPartial: partial,
  );
}

void main() {
  group('RunSplitAnalytics.build', () {
    test('colours splits by delta vs the run average', () {
      final rows = RunSplitAnalytics.build([
        _split(1, 330),
        _split(2, 360),
        _split(3, 390),
      ], averagePaceSecPerKm: 360);

      expect(rows[0].deltaSecPerKm, -30);
      expect(rows[0].tone, RunSplitTone.faster);
      expect(rows[1].tone, RunSplitTone.even);
      expect(rows[2].tone, RunSplitTone.slower);
      expect(RunFormatters.paceDelta(rows[0].deltaSecPerKm!), '-0:30');
      expect(RunFormatters.paceDelta(rows[2].deltaSecPerKm!), '+0:30');
    });

    test('marks only the fastest full split', () {
      final rows = RunSplitAnalytics.build([
        _split(1, 350),
        _split(2, 320),
        _split(3, 340),
        _split(4, 250, partial: true),
      ], averagePaceSecPerKm: 340);

      expect(rows.map((r) => r.isFastest), [false, true, false, false]);
    });

    test('a single full split has no fastest badge', () {
      final rows = RunSplitAnalytics.build([_split(1, 350)]);
      expect(rows.single.isFastest, isFalse);
    });

    test('bars are longer for faster splits and never vanish', () {
      final rows = RunSplitAnalytics.build([
        _split(1, 300),
        _split(2, 360),
        _split(3, 420),
      ]);
      expect(rows[0].barFraction, 1.0);
      expect(rows[1].barFraction, greaterThan(rows[2].barFraction));
      expect(rows[2].barFraction, RunSplitAnalytics.minBarFraction);
    });

    test('small pace differences keep nearly full bars', () {
      final rows = RunSplitAnalytics.build([
        _split(1, 368),
        _split(2, 368),
        _split(3, 375),
      ]);
      expect(rows[2].barFraction, greaterThan(0.85));
    });

    test('partial and pace-less splits get a stub or a delta', () {
      final rows = RunSplitAnalytics.build([
        _split(1, 360),
        _split(2, 360),
        _split(3, null, partial: true),
      ], averagePaceSecPerKm: 360);
      expect(rows[2].deltaSecPerKm, isNull);
      expect(rows[2].tone, RunSplitTone.unknown);
      expect(rows[2].barFraction, lessThan(0.2));
    });

    test('falls back to the mean of completed splits as reference', () {
      final reference = RunSplitAnalytics.referencePace([
        _split(1, 300),
        _split(2, 400),
        _split(3, 100, partial: true),
      ], null);
      expect(reference, closeTo(350, 0.5));
    });

    test('attaches per-km elevation gain when known', () {
      final rows = RunSplitAnalytics.build(
        [_split(1, 360), _split(2, 360)],
        averagePaceSecPerKm: 360,
        elevationGainByKm: const {2: 12.4},
      );
      expect(rows[0].elevationGainMeters, isNull);
      expect(rows[1].elevationGainMeters, 12.4);
    });
  });
}
