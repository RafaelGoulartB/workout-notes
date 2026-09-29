import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_session_context.dart';
import 'package:workout_notes/models/run_session_goal.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/utils/run_goal_input.dart';

void main() {
  group('RunGoalInput.distanceMeters', () {
    test('accepts comma and dot decimals', () {
      expect(RunGoalInput.distanceMeters('5'), 5000);
      expect(RunGoalInput.distanceMeters('5,5'), 5500);
      expect(RunGoalInput.distanceMeters('21.1'), 21100);
      expect(RunGoalInput.distanceMeters(' 0,4 '), 400);
    });

    test('rejects empty, zero, negative and absurd values', () {
      for (final raw in ['', ' ', 'abc', '0', '-3', '0,01', '900', '5,5,5']) {
        expect(RunGoalInput.distanceMeters(raw), isNull, reason: raw);
      }
    });
  });

  group('RunGoalInput.timeSeconds', () {
    test('minutes (decimals allowed) and h:mm', () {
      expect(RunGoalInput.timeSeconds('45'), 2700);
      expect(RunGoalInput.timeSeconds('37,5'), 2250);
      expect(RunGoalInput.timeSeconds('1:15'), 4500);
    });

    test('rejects invalid input', () {
      for (final raw in ['', '0', '0,5', '1:75', 'x', '2000', '1:2:3']) {
        expect(RunGoalInput.timeSeconds(raw), isNull, reason: raw);
      }
    });
  });

  group('RunGoalInput.paceSecPerKm', () {
    test('only the m:ss form is a pace', () {
      expect(RunGoalInput.paceSecPerKm('5:30'), 330);
      expect(RunGoalInput.paceSecPerKm('4:05'), 245);
      expect(RunGoalInput.paceSecPerKm('5.5'), isNull);
      expect(RunGoalInput.paceSecPerKm('530'), isNull);
      expect(RunGoalInput.paceSecPerKm('5:75'), isNull);
      expect(RunGoalInput.paceSecPerKm('1:00'), isNull, reason: 'too fast');
      expect(RunGoalInput.paceSecPerKm('30:00'), isNull, reason: 'too slow');
    });

    test('paceText is the editable form', () {
      expect(RunGoalInput.paceText(330), '5:30');
      expect(RunGoalInput.paceText(245), '4:05');
    });
  });

  group('RunSessionGoal', () {
    test('pace goal survives the wire/spool map round trip', () {
      const goal = RunSessionGoal(
        enabled: true,
        metric: RunIntervalMetric.time,
        value: 2700,
        paceTargetSecPerKm: 330,
        paceTolerancePercent: 10,
      );
      final restored = RunSessionGoal.fromMap(goal.toMap());
      expect(restored.enabled, isTrue);
      expect(restored.metric, RunIntervalMetric.time);
      expect(restored.value, 2700);
      expect(restored.paceTargetSecPerKm, 330);
      expect(restored.paceTolerancePercent, 10);
      expect(restored.hasPaceGoal, isTrue);
    });

    test('a pace-only goal is a goal but not a distance/time target', () {
      final goal = const RunSessionGoal.defaults().copyWith(
        paceTargetSecPerKm: 300,
      );
      expect(goal.enabled, isFalse);
      expect(goal.hasPaceGoal, isTrue);
      expect(goal.hasAnyGoal, isTrue);
      expect(
        goal.isComplete(distanceMeters: 99999, movingTimeSeconds: 99999),
        isFalse,
      );
    });

    test('legacy goal maps (no pace keys) still load', () {
      final goal = RunSessionGoal.fromMap({
        'enabled': true,
        'metric': 'distance',
        'value': 10000,
      });
      expect(goal.hasPaceGoal, isFalse);
      expect(
        goal.paceTolerancePercent,
        RunSessionGoal.defaultPaceTolerancePercent,
      );
    });

    test('clearing the pace target', () {
      final goal = const RunSessionGoal.defaults()
          .copyWith(paceTargetSecPerKm: 300)
          .copyWith(clearPaceTarget: true);
      expect(goal.hasPaceGoal, isFalse);
    });

    test('the session context carries the pace goal to the native spool', () {
      const context = RunSessionContext(
        goal: RunSessionGoal(
          enabled: false,
          metric: RunIntervalMetric.distance,
          value: 5000,
          paceTargetSecPerKm: 320,
          paceTolerancePercent: 3,
        ),
      );
      final wire = context.toMap();
      expect((wire['goal'] as Map)['pace_target_sec_per_km'], 320);
      final restored = RunSessionContext.fromMap(wire);
      expect(restored.goal.paceTargetSecPerKm, 320);
      expect(restored.goal.paceTolerancePercent, 3);
    });
  });

  group('RunVoiceSettings run options', () {
    test('defaults: auto-pause on, 3 s countdown', () {
      const settings = RunVoiceSettings.defaults();
      expect(settings.autoPause, isTrue);
      expect(settings.countdownSeconds, 3);
      expect(settings.announceAutoPause, isTrue);
      expect(settings.announceLaps, isTrue);
    });

    test('round-trips and validates the countdown', () {
      final custom = const RunVoiceSettings.defaults().copyWith(
        autoPause: false,
        countdownSeconds: 10,
        announceLaps: false,
      );
      final restored = RunVoiceSettings.fromJson(custom.toJson());
      expect(restored.autoPause, isFalse);
      expect(restored.countdownSeconds, 10);
      expect(restored.announceLaps, isFalse);
      expect(
        RunVoiceSettings.fromJson({'countdownSeconds': 7}).countdownSeconds,
        3,
      );
      expect(
        RunVoiceSettings.fromJson({'countdownSeconds': 0}).countdownSeconds,
        0,
      );
    });

    test('settings saved before these options existed keep the defaults', () {
      final restored = RunVoiceSettings.fromJson({'enabled': true});
      expect(restored.autoPause, isTrue);
      expect(restored.countdownSeconds, 3);
    });
  });
}
