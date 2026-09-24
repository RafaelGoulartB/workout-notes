/// A 30-second aggregate produced by the Android sleep monitor.
class SleepMonitorSegment {
  final String id;
  final String sessionId;
  final DateTime startedAt;
  final int durationSeconds;
  final double? audioRmsDbfs;
  final double? audioPeakDbfs;
  final double? noiseScore;
  final String classification;
  final double validFraction;
  final int noiseBurstCount;
  // v3: duration-based audio activity and capture diagnostics. Null on legacy data.
  final double? noiseActiveSeconds;
  final int? audioSampleRate;
  final int? audioSampleCount;
  final double? audioBaselineDbfs;
  final bool? audioCalibrated;
  final double? digitalSilenceFraction;
  final double? audioLevelStddevDb;

  // v28 spectral features (audio-features-v2). Null on older recordings.
  final double? spectralBandEnergy0;
  final double? spectralBandEnergy1;
  final double? spectralBandEnergy2;
  final double? spectralBandEnergy3;
  final double? spectralBandEnergy4;
  final double? spectralFlatness;
  final double? spectralCentroidHz;
  final double? breathingRegularity;
  final double? breathingRateHz;

  // v28 actigraphy aggregates. Null when no accelerometer was available.
  final double? motionActiveSeconds;
  final double? motionMeanDeviationG;
  final double? motionMaxDeviationG;

  const SleepMonitorSegment({
    required this.id,
    required this.sessionId,
    required this.startedAt,
    required this.durationSeconds,
    required this.audioRmsDbfs,
    required this.audioPeakDbfs,
    required this.noiseScore,
    required this.classification,
    required this.validFraction,
    required this.noiseBurstCount,
    this.noiseActiveSeconds,
    this.audioSampleRate,
    this.audioSampleCount,
    this.audioBaselineDbfs,
    this.audioCalibrated,
    this.digitalSilenceFraction,
    this.audioLevelStddevDb,
    this.spectralBandEnergy0,
    this.spectralBandEnergy1,
    this.spectralBandEnergy2,
    this.spectralBandEnergy3,
    this.spectralBandEnergy4,
    this.spectralFlatness,
    this.spectralCentroidHz,
    this.breathingRegularity,
    this.breathingRateHz,
    this.motionActiveSeconds,
    this.motionMeanDeviationG,
    this.motionMaxDeviationG,
  });

  bool get isQuiet => classification == 'quiet';
  bool get isNoise => classification == 'noise';
  bool get isInvalid => classification == 'invalid';

  /// Whether this recording carries the v28 spectral features needed by the
  /// heuristic staging engine (audio-features-v2 nights).
  bool get hasSpectralFeatures => spectralFlatness != null;

  /// Whether actigraphy aggregates were captured for this recording.
  bool get hasMotionFeatures => motionActiveSeconds != null;

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'started_at': startedAt.toIso8601String(),
    'duration_seconds': durationSeconds,
    'audio_rms_dbfs': audioRmsDbfs,
    'audio_peak_dbfs': audioPeakDbfs,
    'noise_score': noiseScore,
    'classification': classification,
    'valid_fraction': validFraction,
    'noise_burst_count': noiseBurstCount,
    if (audioLevelStddevDb != null) 'audio_level_stddev_db': audioLevelStddevDb,
    if (noiseActiveSeconds != null) 'noise_active_seconds': noiseActiveSeconds,
    if (audioSampleRate != null) 'audio_sample_rate': audioSampleRate,
    if (audioSampleCount != null) 'audio_sample_count': audioSampleCount,
    if (audioBaselineDbfs != null) 'audio_baseline_dbfs': audioBaselineDbfs,
    if (audioCalibrated != null) 'audio_calibrated': audioCalibrated,
    if (digitalSilenceFraction != null)
      'digital_silence_fraction': digitalSilenceFraction,
    if (spectralBandEnergy0 != null)
      'spectral_band_energy_0': spectralBandEnergy0,
    if (spectralBandEnergy1 != null)
      'spectral_band_energy_1': spectralBandEnergy1,
    if (spectralBandEnergy2 != null)
      'spectral_band_energy_2': spectralBandEnergy2,
    if (spectralBandEnergy3 != null)
      'spectral_band_energy_3': spectralBandEnergy3,
    if (spectralBandEnergy4 != null)
      'spectral_band_energy_4': spectralBandEnergy4,
    if (spectralFlatness != null) 'spectral_flatness': spectralFlatness,
    if (spectralCentroidHz != null) 'spectral_centroid_hz': spectralCentroidHz,
    if (breathingRegularity != null)
      'breathing_regularity': breathingRegularity,
    if (breathingRateHz != null) 'breathing_rate_hz': breathingRateHz,
    if (motionActiveSeconds != null)
      'motion_active_seconds': motionActiveSeconds,
    if (motionMeanDeviationG != null)
      'motion_mean_deviation_g': motionMeanDeviationG,
    if (motionMaxDeviationG != null)
      'motion_max_deviation_g': motionMaxDeviationG,
  };

  factory SleepMonitorSegment.fromMap(Map<String, dynamic> map) {
    return SleepMonitorSegment(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      durationSeconds: (map['duration_seconds'] as num).toInt(),
      audioRmsDbfs: (map['audio_rms_dbfs'] as num?)?.toDouble(),
      audioPeakDbfs: (map['audio_peak_dbfs'] as num?)?.toDouble(),
      noiseScore: (map['noise_score'] as num?)?.toDouble(),
      classification: map['classification'] as String,
      validFraction: (map['valid_fraction'] as num).toDouble(),
      noiseBurstCount: (map['noise_burst_count'] as num?)?.toInt() ?? 0,
      audioLevelStddevDb: (map['audio_level_stddev_db'] as num?)?.toDouble(),
      noiseActiveSeconds: (map['noise_active_seconds'] as num?)?.toDouble(),
      audioSampleRate: (map['audio_sample_rate'] as num?)?.toInt(),
      audioSampleCount: (map['audio_sample_count'] as num?)?.toInt(),
      audioBaselineDbfs: (map['audio_baseline_dbfs'] as num?)?.toDouble(),
      audioCalibrated: map['audio_calibrated'] as bool?,
      digitalSilenceFraction: (map['digital_silence_fraction'] as num?)
          ?.toDouble(),
      spectralBandEnergy0: (map['spectral_band_energy_0'] as num?)?.toDouble(),
      spectralBandEnergy1: (map['spectral_band_energy_1'] as num?)?.toDouble(),
      spectralBandEnergy2: (map['spectral_band_energy_2'] as num?)?.toDouble(),
      spectralBandEnergy3: (map['spectral_band_energy_3'] as num?)?.toDouble(),
      spectralBandEnergy4: (map['spectral_band_energy_4'] as num?)?.toDouble(),
      spectralFlatness: (map['spectral_flatness'] as num?)?.toDouble(),
      spectralCentroidHz: (map['spectral_centroid_hz'] as num?)?.toDouble(),
      breathingRegularity: (map['breathing_regularity'] as num?)?.toDouble(),
      breathingRateHz: (map['breathing_rate_hz'] as num?)?.toDouble(),
      motionActiveSeconds: (map['motion_active_seconds'] as num?)?.toDouble(),
      motionMeanDeviationG: (map['motion_mean_deviation_g'] as num?)
          ?.toDouble(),
      motionMaxDeviationG: (map['motion_max_deviation_g'] as num?)?.toDouble(),
    );
  }
}
