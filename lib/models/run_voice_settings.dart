enum RunIntervalMetric { distance, time }

enum RunVoiceLanguage {
  app,
  portuguese,
  english;

  String get storageValue => switch (this) {
    RunVoiceLanguage.app => 'app',
    RunVoiceLanguage.portuguese => 'pt',
    RunVoiceLanguage.english => 'en',
  };

  RunVoiceLanguage resolve(String? appLocale) {
    if (this != RunVoiceLanguage.app) return this;
    return appLocale?.toLowerCase().startsWith('pt') == true
        ? RunVoiceLanguage.portuguese
        : RunVoiceLanguage.english;
  }

  static RunVoiceLanguage fromJson(Object? raw) => switch (raw) {
    'pt' || 'portuguese' => RunVoiceLanguage.portuguese,
    'en' || 'english' => RunVoiceLanguage.english,
    _ => RunVoiceLanguage.app,
  };
}

/// How much the voice coach talks.
enum RunVoiceVerbosity {
  minimal,
  standard,
  detailed;

  String get storageValue => name;

  static RunVoiceVerbosity fromJson(Object? raw) => switch (raw) {
    'minimal' => RunVoiceVerbosity.minimal,
    'detailed' => RunVoiceVerbosity.detailed,
    _ => RunVoiceVerbosity.standard,
  };
}

/// What happens to the user's media while the coach speaks.
enum RunVoiceMediaBehavior {
  duck,
  pause;

  String get storageValue => name;

  static RunVoiceMediaBehavior fromJson(Object? raw) => switch (raw) {
    'pause' => RunVoiceMediaBehavior.pause,
    _ => RunVoiceMediaBehavior.duck,
  };
}

/// How an auto-pause is announced.
enum RunVoiceAutoPauseStyle {
  voice,
  beep;

  String get storageValue => name;

  static RunVoiceAutoPauseStyle fromJson(Object? raw) => switch (raw) {
    'beep' => RunVoiceAutoPauseStyle.beep,
    _ => RunVoiceAutoPauseStyle.voice,
  };
}

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
  final RunVoiceLanguage language;
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

  /// Stops the moving clock while standing still (traffic lights, stretching).
  final bool autoPause;
  final bool announceAutoPause;
  final bool announceLaps;

  /// Seconds counted down before recording starts: 0, 3, 5 or 10.
  final int countdownSeconds;

  static const countdownOptions = [0, 3, 5, 10];

  /// How much the coach talks.
  final RunVoiceVerbosity verbosity;

  /// Lower (duck) or pause the user's media while the coach speaks.
  final RunVoiceMediaBehavior mediaBehavior;

  /// Short beeps for step changes and a 3-2-1 countdown before each change.
  final bool earcons;

  /// Vibrate on step changes.
  final bool haptics;

  /// Voice speed: one of [speechRateOptions].
  final double speechRate;

  /// Voice volume relative to media: one of [voiceVolumeOptions].
  final double voiceVolume;

  /// Time-based cue every N minutes (0 = off): one of [announceTimeOptions].
  final int announceTimeEveryMin;

  /// The distance cue includes the total elapsed time.
  final bool kmIncludeTime;

  /// The distance cue includes the average pace.
  final bool kmIncludeAvgPace;

  /// Auto-pause announced by voice or by a short beep.
  final RunVoiceAutoPauseStyle autoPauseStyle;

  static const speechRateOptions = [0.9, 1.0, 1.1, 1.25];
  static const voiceVolumeOptions = [0.5, 0.75, 1.0];
  static const announceTimeOptions = [0, 5, 10, 15];

  const RunVoiceSettings({
    required this.enabled,
    required this.language,
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
    this.autoPause = true,
    this.announceAutoPause = true,
    this.announceLaps = true,
    this.countdownSeconds = 3,
    this.verbosity = RunVoiceVerbosity.standard,
    this.mediaBehavior = RunVoiceMediaBehavior.duck,
    this.earcons = true,
    this.haptics = true,
    this.speechRate = 1.0,
    this.voiceVolume = 1.0,
    this.announceTimeEveryMin = 0,
    this.kmIncludeTime = true,
    this.kmIncludeAvgPace = false,
    this.autoPauseStyle = RunVoiceAutoPauseStyle.voice,
  });

  const RunVoiceSettings.defaults()
    : this(
        enabled: true,
        language: RunVoiceLanguage.app,
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
    RunVoiceLanguage? language,
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
    bool? autoPause,
    bool? announceAutoPause,
    bool? announceLaps,
    int? countdownSeconds,
    RunVoiceVerbosity? verbosity,
    RunVoiceMediaBehavior? mediaBehavior,
    bool? earcons,
    bool? haptics,
    double? speechRate,
    double? voiceVolume,
    int? announceTimeEveryMin,
    bool? kmIncludeTime,
    bool? kmIncludeAvgPace,
    RunVoiceAutoPauseStyle? autoPauseStyle,
  }) {
    return RunVoiceSettings(
      enabled: enabled ?? this.enabled,
      language: language ?? this.language,
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
      autoPause: autoPause ?? this.autoPause,
      announceAutoPause: announceAutoPause ?? this.announceAutoPause,
      announceLaps: announceLaps ?? this.announceLaps,
      countdownSeconds: countdownSeconds ?? this.countdownSeconds,
      verbosity: verbosity ?? this.verbosity,
      mediaBehavior: mediaBehavior ?? this.mediaBehavior,
      earcons: earcons ?? this.earcons,
      haptics: haptics ?? this.haptics,
      speechRate: speechRate ?? this.speechRate,
      voiceVolume: voiceVolume ?? this.voiceVolume,
      announceTimeEveryMin: announceTimeEveryMin ?? this.announceTimeEveryMin,
      kmIncludeTime: kmIncludeTime ?? this.kmIncludeTime,
      kmIncludeAvgPace: kmIncludeAvgPace ?? this.kmIncludeAvgPace,
      autoPauseStyle: autoPauseStyle ?? this.autoPauseStyle,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'language': language.storageValue,
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
    'autoPause': autoPause,
    'announceAutoPause': announceAutoPause,
    'announceLaps': announceLaps,
    'countdownSeconds': countdownSeconds,
    'verbosity': verbosity.storageValue,
    'mediaBehavior': mediaBehavior.storageValue,
    'earcons': earcons,
    'haptics': haptics,
    'speechRate': speechRate,
    'voiceVolume': voiceVolume,
    'announceTimeEveryMin': announceTimeEveryMin,
    'kmIncludeTime': kmIncludeTime,
    'kmIncludeAvgPace': kmIncludeAvgPace,
    'autoPauseStyle': autoPauseStyle.storageValue,
  };

  factory RunVoiceSettings.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const RunVoiceSettings.defaults();
    final every = (json['distanceEveryKm'] as num?)?.toInt() ?? 1;
    final tolerance = (json['paceTolerancePercent'] as num?)?.toInt() ?? 10;
    final target = (json['targetPaceSecPerKm'] as num?)?.toInt();
    final intervalRaw = json['interval'];
    return RunVoiceSettings(
      enabled: json['enabled'] as bool? ?? true,
      language: RunVoiceLanguage.fromJson(json['language']),
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
        intervalRaw is Map ? Map<String, dynamic>.from(intervalRaw) : null,
      ),
      autoPause: json['autoPause'] as bool? ?? true,
      announceAutoPause: json['announceAutoPause'] as bool? ?? true,
      announceLaps: json['announceLaps'] as bool? ?? true,
      countdownSeconds: _countdown(json['countdownSeconds']),
      verbosity: RunVoiceVerbosity.fromJson(json['verbosity']),
      mediaBehavior: RunVoiceMediaBehavior.fromJson(json['mediaBehavior']),
      earcons: _bool(json['earcons'], true),
      haptics: _bool(json['haptics'], true),
      speechRate: _nearest(json['speechRate'], speechRateOptions, 1.0),
      voiceVolume: _nearest(json['voiceVolume'], voiceVolumeOptions, 1.0),
      announceTimeEveryMin: _announceTime(json['announceTimeEveryMin']),
      kmIncludeTime: _bool(json['kmIncludeTime'], true),
      kmIncludeAvgPace: _bool(json['kmIncludeAvgPace'], false),
      autoPauseStyle: RunVoiceAutoPauseStyle.fromJson(json['autoPauseStyle']),
    );
  }

  static int _countdown(Object? raw) {
    final value = (raw as num?)?.toInt();
    return countdownOptions.contains(value) ? value! : 3;
  }

  static bool _bool(Object? raw, bool fallback) => raw is bool ? raw : fallback;

  static int _announceTime(Object? raw) {
    final value = (raw as num?)?.toInt();
    return announceTimeOptions.contains(value) ? value! : 0;
  }

  /// The allowed option closest to [raw]; [fallback] when it is not a finite
  /// number.
  static double _nearest(Object? raw, List<double> options, double fallback) {
    if (raw is! num || !raw.isFinite) return fallback;
    final value = raw.toDouble();
    return options.reduce(
      (a, b) => (a - value).abs() <= (b - value).abs() ? a : b,
    );
  }
}
