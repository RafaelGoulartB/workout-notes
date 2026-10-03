import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_voice_settings.dart';

void main() {
  group('RunVoiceSettings JSON', () {
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

    test('round-trips every new field', () {
      final original = const RunVoiceSettings.defaults().copyWith(
        verbosity: RunVoiceVerbosity.detailed,
        mediaBehavior: RunVoiceMediaBehavior.pause,
        earcons: false,
        haptics: false,
        speechRate: 1.25,
        voiceVolume: 0.5,
        announceTimeEveryMin: 10,
        kmIncludeTime: false,
        kmIncludeAvgPace: true,
        autoPauseStyle: RunVoiceAutoPauseStyle.beep,
      );
      final json = original.toJson();
      expect(json['verbosity'], 'detailed');
      expect(json['mediaBehavior'], 'pause');
      expect(json['earcons'], false);
      expect(json['haptics'], false);
      expect(json['speechRate'], 1.25);
      expect(json['voiceVolume'], 0.5);
      expect(json['announceTimeEveryMin'], 10);
      expect(json['kmIncludeTime'], false);
      expect(json['kmIncludeAvgPace'], true);
      expect(json['autoPauseStyle'], 'beep');

      final restored = RunVoiceSettings.fromJson(json);
      expect(restored.verbosity, RunVoiceVerbosity.detailed);
      expect(restored.mediaBehavior, RunVoiceMediaBehavior.pause);
      expect(restored.earcons, false);
      expect(restored.haptics, false);
      expect(restored.speechRate, 1.25);
      expect(restored.voiceVolume, 0.5);
      expect(restored.announceTimeEveryMin, 10);
      expect(restored.kmIncludeTime, false);
      expect(restored.kmIncludeAvgPace, true);
      expect(restored.autoPauseStyle, RunVoiceAutoPauseStyle.beep);
      expect(restored.announceSplit, original.announceSplit);
    });

    test('legacy JSON without the new keys decodes to the defaults', () {
      final legacy = const RunVoiceSettings.defaults().toJson()
        ..removeWhere(
          (key, _) => const {
            'verbosity',
            'mediaBehavior',
            'earcons',
            'haptics',
            'speechRate',
            'voiceVolume',
            'announceTimeEveryMin',
            'kmIncludeTime',
            'kmIncludeAvgPace',
            'autoPauseStyle',
          }.contains(key),
        );
      legacy['announceSplit'] = false;
      final restored = RunVoiceSettings.fromJson(legacy);
      expect(restored.announceSplit, false);
      expect(restored.toJson(), {
        ...const RunVoiceSettings.defaults().toJson(),
        'announceSplit': false,
      });
    });

    test('invalid values fall back', () {
      final restored = RunVoiceSettings.fromJson({
        'verbosity': 'chatty',
        'mediaBehavior': 3,
        'autoPauseStyle': null,
        'earcons': 'yes',
        'haptics': 1,
        'speechRate': 'fast',
        'voiceVolume': double.nan,
        'announceTimeEveryMin': 7,
        'kmIncludeTime': 'no',
        'kmIncludeAvgPace': 'no',
      });
      expect(restored.verbosity, RunVoiceVerbosity.standard);
      expect(restored.mediaBehavior, RunVoiceMediaBehavior.duck);
      expect(restored.autoPauseStyle, RunVoiceAutoPauseStyle.voice);
      expect(restored.earcons, true);
      expect(restored.haptics, true);
      expect(restored.speechRate, 1.0);
      expect(restored.voiceVolume, 1.0);
      expect(restored.announceTimeEveryMin, 0);
      expect(restored.kmIncludeTime, true);
      expect(restored.kmIncludeAvgPace, false);
    });

    test('numbers snap to the nearest allowed option', () {
      final restored = RunVoiceSettings.fromJson({
        'speechRate': 1.2,
        'voiceVolume': 0.1,
      });
      expect(restored.speechRate, 1.25);
      expect(restored.voiceVolume, 0.5);
      expect(RunVoiceSettings.fromJson({'speechRate': 2}).speechRate, 1.25);
      expect(RunVoiceSettings.fromJson({'speechRate': 0}).speechRate, 0.9);
      expect(RunVoiceSettings.fromJson({'speechRate': 1}).speechRate, 1.0);
    });
  });
}
