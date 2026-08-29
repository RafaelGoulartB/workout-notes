import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';

/// Brief spoken phrases for runners, localized independently from the UI.
///
/// The Android foreground service mirrors these phrases so coaching continues
/// with the same language and wording while the screen is off.
class RunVoicePhrases {
  final RunVoiceLanguage language;

  const RunVoicePhrases(this.language)
    : assert(language != RunVoiceLanguage.app);

  bool get _pt => language.isPortuguese;

  String distanceMilestone({
    required int km,
    required int durationSeconds,
    required double? avgPaceSecPerKm,
  }) {
    final buf = StringBuffer('$km ${_kilometersWord(km)}.');
    if (_validPace(avgPaceSecPerKm)) {
      buf.write(
        _pt
            ? ' Pace médio ${_paceSpeech(avgPaceSecPerKm!)}.'
            : ' Average pace ${_paceSpeech(avgPaceSecPerKm!)}.',
      );
    }
    return buf.toString();
  }

  String splitComplete({required int km, required double? paceSecPerKm}) {
    final pace = _validPace(paceSecPerKm)
        ? ' Pace ${_paceSpeech(paceSecPerKm!)}.'
        : '';
    return '${_pt ? 'Quilômetro' : 'Kilometer'} $km.$pace';
  }

  String splitSummary({
    required int km,
    required double? splitPaceSecPerKm,
    required double? avgPaceSecPerKm,
  }) {
    final split = _validPace(splitPaceSecPerKm)
        ? ' Pace ${_paceSpeech(splitPaceSecPerKm!)}.'
        : '';
    final average = _validPace(avgPaceSecPerKm)
        ? _pt
              ? ' Pace médio ${_paceSpeech(avgPaceSecPerKm!)}.'
              : ' Average pace ${_paceSpeech(avgPaceSecPerKm!)}.'
        : '';
    return '${_pt ? 'Quilômetro' : 'Kilometer'} $km.$split$average';
  }

  String paceTooFast() => _pt ? 'Segura um pouco o ritmo.' : 'Ease off.';

  String paceTooSlow() => _pt ? 'Aumente um pouco o ritmo.' : 'Pick it up.';

  String paceOnTarget() => _pt ? 'Pace dentro da meta.' : 'Pace on target.';

  String weakGps() => _pt ? 'Sinal de GPS fraco.' : 'Weak GPS signal.';

  String gpsRestored() =>
      _pt ? 'Sinal de GPS recuperado.' : 'GPS signal restored.';

  String workIntervalStart({required int index, required int total}) =>
      _pt ? 'Tiro $index de $total. Vai!' : 'Rep $index of $total. Go.';

  String restIntervalStart({
    required RunIntervalMetric metric,
    required int value,
  }) {
    final amount = metric == RunIntervalMetric.time
        ? _durationSpeech(value)
        : _distanceSpeech(value);
    return _pt ? 'Recuperação. $amount.' : 'Recover. $amount.';
  }

  String intervalsComplete() =>
      _pt ? 'Intervalos concluídos.' : 'Intervals complete.';

  String timeRemaining(int seconds) => _pt
      ? 'Faltam ${_durationSpeech(seconds)}.'
      : '${_durationSpeech(seconds)} left.';

  String distanceRemaining(int meters) => _pt
      ? 'Faltam ${_distanceSpeech(meters)}.'
      : '${_distanceSpeech(meters)} left.';

  String stepStart({
    required RunStepRole role,
    required int repIndex,
    required int repTotal,
    required RunIntervalMetric metric,
    required int value,
    double? targetPaceSecPerKm,
  }) {
    final amount = metric == RunIntervalMetric.time
        ? _durationSpeech(value)
        : _distanceSpeech(value);
    final head = _pt
        ? switch (role) {
            RunStepRole.warmup => 'Aquecimento. $amount.',
            RunStepRole.cooldown => 'Desaquecimento. $amount.',
            RunStepRole.recovery => 'Recuperação. $amount.',
            RunStepRole.steady => 'Ritmo contínuo. $amount.',
            RunStepRole.work =>
              repTotal > 1
                  ? 'Tiro $repIndex de $repTotal. $amount.'
                  : 'Esforço. $amount.',
          }
        : switch (role) {
            RunStepRole.warmup => 'Warm up. $amount.',
            RunStepRole.cooldown => 'Cool down. $amount.',
            RunStepRole.recovery => 'Recover. $amount.',
            RunStepRole.steady => 'Steady. $amount.',
            RunStepRole.work =>
              repTotal > 1
                  ? 'Rep $repIndex of $repTotal. $amount.'
                  : 'Effort. $amount.',
          };
    if (role.isEffort && _validPace(targetPaceSecPerKm)) {
      return '$head ${_pt ? 'Pace alvo' : 'Target pace'} '
          '${_paceSpeech(targetPaceSecPerKm!)}.';
    }
    return head;
  }

  String stepPaceTooSlow(double? paceSecPerKm) {
    if (!_validPace(paceSecPerKm)) return paceTooSlow();
    return _pt
        ? 'Aumente o ritmo. Pace atual ${_paceSpeech(paceSecPerKm!)}.'
        : 'Pick it up. Current pace ${_paceSpeech(paceSecPerKm!)}.';
  }

  String stepPaceTooFast(double? paceSecPerKm) {
    if (!_validPace(paceSecPerKm)) return paceTooFast();
    return _pt
        ? 'Segura o ritmo. Pace atual ${_paceSpeech(paceSecPerKm!)}.'
        : 'Ease off. Current pace ${_paceSpeech(paceSecPerKm!)}.';
  }

  String workoutComplete() => _pt ? 'Treino concluído.' : 'Workout complete.';

  String goalComplete({required RunIntervalMetric metric, required int value}) {
    final amount = metric == RunIntervalMetric.time
        ? _durationSpeech(value)
        : _distanceSpeech(value);
    return _pt ? 'Meta concluída. $amount.' : 'Goal complete. $amount.';
  }

  String goalRemaining({
    required RunIntervalMetric metric,
    required int value,
  }) {
    final amount = metric == RunIntervalMetric.time
        ? _durationSpeech(value)
        : _distanceSpeech(value);
    return _pt ? 'Faltam $amount.' : '$amount left.';
  }

  String paused() => _pt ? 'Corrida pausada.' : 'Paused.';

  String resumed() => _pt ? 'Corrida retomada.' : 'Resumed.';

  String testAnnouncement() => _pt
      ? 'Áudio do treinador pronto. Pace de 5 minutos e 30 segundos por quilômetro.'
      : 'Voice coach ready. Pace 5 minutes 30 seconds per kilometer.';

  String _kilometersWord(int km) => _pt
      ? (km == 1 ? 'quilômetro' : 'quilômetros')
      : (km == 1 ? 'kilometer' : 'kilometers');

  String _durationSpeech(int totalSeconds) {
    final safe = totalSeconds.clamp(0, 24 * 3600);
    final hours = safe ~/ 3600;
    final minutes = (safe % 3600) ~/ 60;
    final seconds = safe % 60;
    final parts = <String>[];
    if (hours > 0) {
      parts.add(
        '$hours ${_pt ? (hours == 1 ? 'hora' : 'horas') : (hours == 1 ? 'hour' : 'hours')}',
      );
    }
    if (minutes > 0) {
      parts.add(
        '$minutes ${_pt ? (minutes == 1 ? 'minuto' : 'minutos') : (minutes == 1 ? 'minute' : 'minutes')}',
      );
    }
    if (seconds > 0 || parts.isEmpty) {
      parts.add(
        '$seconds ${_pt ? (seconds == 1 ? 'segundo' : 'segundos') : (seconds == 1 ? 'second' : 'seconds')}',
      );
    }
    return parts.join(_pt ? ' e ' : ' ');
  }

  String _paceSpeech(double secPerKm) {
    final total = secPerKm.round().clamp(0, 99 * 60 + 59);
    final minutes = total ~/ 60;
    final seconds = total % 60;
    final minutePart = _pt
        ? '$minutes ${minutes == 1 ? 'minuto' : 'minutos'}'
        : '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
    final secondsPart = seconds == 0
        ? ''
        : _pt
        ? ' e $seconds ${seconds == 1 ? 'segundo' : 'segundos'}'
        : ' $seconds ${seconds == 1 ? 'second' : 'seconds'}';
    return '$minutePart$secondsPart ${_pt ? 'por quilômetro' : 'per kilometer'}';
  }

  bool _validPace(double? pace) => pace != null && pace > 0 && pace.isFinite;

  String _distanceSpeech(int meters) {
    if (meters < 1000) {
      return '$meters ${_pt ? (meters == 1 ? 'metro' : 'metros') : (meters == 1 ? 'meter' : 'meters')}';
    }
    final kilometers = meters ~/ 1000;
    final remainder = meters % 1000;
    if (remainder == 0) return '$kilometers ${_kilometersWord(kilometers)}';
    final kilometerPart = '$kilometers ${_kilometersWord(kilometers)}';
    final meterPart = '$remainder ${_pt ? 'metros' : 'meters'}';
    return '$kilometerPart ${_pt ? 'e' : 'and'} $meterPart';
  }
}
