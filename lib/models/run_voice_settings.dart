enum RunIntervalMetric { distance, time }

class RunIntervalPreset {
  final RunIntervalMetric workMetric;
  final int workValue;
  final RunIntervalMetric restMetric;
  final int restValue;
  final int repeats;

  const RunIntervalPreset({
    required this.workMetric,
    required this.workValue,
    required this.restMetric,
    required this.restValue,
    required this.repeats,
  });

  /// Default: 400 m work / 90 s rest × 8.
  const RunIntervalPreset.defaults()
      : this(
          workMetric: RunIntervalMetric.distance,
          workValue: 400,
          restMetric: RunIntervalMetric.time,
          restValue: 90,
          repeats: 8,
        );

  RunIntervalPreset copyWith({
    RunIntervalMetric? workMetric,
    int? workValue,
    RunIntervalMetric? restMetric,
    int? restValue,
    int? repeats,
  }) {
    return RunIntervalPreset(
      workMetric: workMetric ?? this.workMetric,
      workValue: workValue ?? this.workValue,
      restMetric: restMetric ?? this.restMetric,
      restValue: restValue ?? this.restValue,
      repeats: repeats ?? this.repeats,
    );
  }

  Map<String, dynamic> toJson() => {
        'workMetric': workMetric.name,
        'workValue': workValue,
        'restMetric': restMetric.name,
        'restValue': restValue,
        'repeats': repeats,
      };

  factory RunIntervalPreset.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RunIntervalPreset.defaults();
    return RunIntervalPreset(
      workMetric: _metric(json['workMetric']),
      workValue: _positiveInt(json['workValue'], 400),
      restMetric: _metric(json['restMetric']),
      restValue: _nonNegativeInt(json['restValue'], 90),
      repeats: _positiveInt(json['repeats'], 8).clamp(1, 99),
    );
  }

  static RunIntervalMetric _metric(Object? raw) {
    if (raw == 'time') return RunIntervalMetric.time;
    return RunIntervalMetric.distance;
  }

  static int _positiveInt(Object? raw, int fallback) {
    final n = (raw as num?)?.toInt();
    if (n == null || n <= 0) return fallback;
    return n;
  }

  static int _nonNegativeInt(Object? raw, int fallback) {
    final n = (raw as num?)?.toInt();
    if (n == null || n < 0) return fallback;
    return n;
  }
}

class RunVoiceSettings {
  static const storageKey = 'run_voice_settings_v1';

  final bool enabled;
  final bool headphonesOnly;
  final bool muteDuringCall;
  final bool announceDistance;
  final int distanceEveryKm;
  final bool announceSplit;
  final bool announcePaceWarning;
  final int? targetPaceSecPerKm;
  final int paceTolerancePercent;
  final bool announceGpsStatus;
  final bool announceIntervals;
  final bool intervalsEnabledByDefault;
  final RunIntervalPreset interval;

  const RunVoiceSettings({
    required this.enabled,
    required this.headphonesOnly,
    required this.muteDuringCall,
    required this.announceDistance,
    required this.distanceEveryKm,
    required this.announceSplit,
    required this.announcePaceWarning,
    required this.targetPaceSecPerKm,
    required this.paceTolerancePercent,
    required this.announceGpsStatus,
    required this.announceIntervals,
    required this.intervalsEnabledByDefault,
    required this.interval,
  });

  const RunVoiceSettings.defaults()
      : this(
          enabled: true,
          headphonesOnly: true,
          muteDuringCall: true,
          announceDistance: true,
          distanceEveryKm: 1,
          announceSplit: true,
          announcePaceWarning: false,
          targetPaceSecPerKm: null,
          paceTolerancePercent: 10,
          announceGpsStatus: true,
          announceIntervals: true,
          intervalsEnabledByDefault: false,
          interval: const RunIntervalPreset.defaults(),
        );

  RunVoiceSettings copyWith({
    bool? enabled,
    bool? headphonesOnly,
    bool? muteDuringCall,
    bool? announceDistance,
    int? distanceEveryKm,
    bool? announceSplit,
    bool? announcePaceWarning,
    int? targetPaceSecPerKm,
    bool clearTargetPace = false,
    int? paceTolerancePercent,
    bool? announceGpsStatus,
    bool? announceIntervals,
    bool? intervalsEnabledByDefault,
    RunIntervalPreset? interval,
  }) {
    return RunVoiceSettings(
      enabled: enabled ?? this.enabled,
      headphonesOnly: headphonesOnly ?? this.headphonesOnly,
      muteDuringCall: muteDuringCall ?? this.muteDuringCall,
      announceDistance: announceDistance ?? this.announceDistance,
      distanceEveryKm: distanceEveryKm ?? this.distanceEveryKm,
      announceSplit: announceSplit ?? this.announceSplit,
      announcePaceWarning: announcePaceWarning ?? this.announcePaceWarning,
      targetPaceSecPerKm: clearTargetPace
          ? null
          : (targetPaceSecPerKm ?? this.targetPaceSecPerKm),
      paceTolerancePercent: paceTolerancePercent ?? this.paceTolerancePercent,
      announceGpsStatus: announceGpsStatus ?? this.announceGpsStatus,
      announceIntervals: announceIntervals ?? this.announceIntervals,
      intervalsEnabledByDefault:
          intervalsEnabledByDefault ?? this.intervalsEnabledByDefault,
      interval: interval ?? this.interval,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'headphonesOnly': headphonesOnly,
        'muteDuringCall': muteDuringCall,
        'announceDistance': announceDistance,
        'distanceEveryKm': distanceEveryKm,
        'announceSplit': announceSplit,
        'announcePaceWarning': announcePaceWarning,
        'targetPaceSecPerKm': targetPaceSecPerKm,
        'paceTolerancePercent': paceTolerancePercent,
        'announceGpsStatus': announceGpsStatus,
        'announceIntervals': announceIntervals,
        'intervalsEnabledByDefault': intervalsEnabledByDefault,
        'interval': interval.toJson(),
      };

  factory RunVoiceSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RunVoiceSettings.defaults();
    final every = (json['distanceEveryKm'] as num?)?.toInt() ?? 1;
    final tolerance = (json['paceTolerancePercent'] as num?)?.toInt() ?? 10;
    final target = (json['targetPaceSecPerKm'] as num?)?.toInt();
    final intervalRaw = json['interval'];
    return RunVoiceSettings(
      enabled: json['enabled'] as bool? ?? true,
      headphonesOnly: json['headphonesOnly'] as bool? ?? true,
      muteDuringCall: json['muteDuringCall'] as bool? ?? true,
      announceDistance: json['announceDistance'] as bool? ?? true,
      distanceEveryKm: every == 2 || every == 5 ? every : 1,
      announceSplit: json['announceSplit'] as bool? ?? true,
      announcePaceWarning: json['announcePaceWarning'] as bool? ?? false,
      targetPaceSecPerKm: target != null && target > 0 ? target : null,
      paceTolerancePercent: tolerance.clamp(5, 50),
      announceGpsStatus: json['announceGpsStatus'] as bool? ?? true,
      announceIntervals: json['announceIntervals'] as bool? ?? true,
      intervalsEnabledByDefault:
          json['intervalsEnabledByDefault'] as bool? ?? false,
      interval: RunIntervalPreset.fromJson(
        intervalRaw is Map
            ? Map<String, dynamic>.from(intervalRaw)
            : null,
      ),
    );
  }
}
