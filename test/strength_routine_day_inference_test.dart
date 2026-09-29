import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/strength_routine_day_inference.dart';

void main() {
  group('StrengthRoutineDayInference.bestDay', () {
    final days = {
      'push': {'bench', 'ohp', 'dips', 'triceps'},
      'pull': {'row', 'pulldown', 'curl', 'facepull'},
    };

    test('picks the day sharing most exercises', () {
      expect(
        StrengthRoutineDayInference.bestDay({'row', 'pulldown', 'curl'}, days),
        'pull',
      );
    });

    test('rejects weak overlaps', () {
      expect(
        StrengthRoutineDayInference.bestDay({'bench', 'squat', 'lunge'}, days),
        isNull,
      );
      expect(StrengthRoutineDayInference.bestDay({}, days), isNull);
    });
  });
}
