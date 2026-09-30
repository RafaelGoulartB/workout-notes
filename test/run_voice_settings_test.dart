import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

void main() {
  group('RunVoiceSettings JSON', () {
    test('round-trips defaults', () {
      const original = RunVoiceSettings.defaults();
      final restored = RunVoiceSettings.fromJson(original.toJson());
      expect(restored.enabled, original.enabled);
      expect(restored.language, RunVoiceLanguage.app);
      expect(restored.headphonesOnly, true);
      expect(restored.distanceEveryKm, 1);
      expect(restored.interval.workValue, 400);
      expect(restored.interval.repeats, 8);
    });

    test('round-trips an explicit Portuguese voice language', () {
      final original = const RunVoiceSettings.defaults().copyWith(
        language: RunVoiceLanguage.portuguese,
      );
      final restored = RunVoiceSettings.fromJson(original.toJson());
      expect(restored.language, RunVoiceLanguage.portuguese);
    });

    test(
      'app default follows locale while an explicit language overrides it',
      () {
        expect(
          RunVoiceLanguage.app.resolve('pt_BR'),
          RunVoiceLanguage.portuguese,
        );
        expect(
          RunVoiceLanguage.english.resolve('pt_BR'),
          RunVoiceLanguage.english,
        );
        expect(
          RunVoiceLanguage.portuguese.resolve('en_US'),
          RunVoiceLanguage.portuguese,
        );
      },
    );

    test('clamps distance frequency', () {
      final restored = RunVoiceSettings.fromJson({'distanceEveryKm': 7});
      expect(restored.distanceEveryKm, 1);
    });
  });
}
