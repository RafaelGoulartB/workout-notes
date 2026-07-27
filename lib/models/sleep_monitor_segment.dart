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
  });

  bool get isQuiet => classification == 'quiet';
  bool get isNoise => classification == 'noise';
  bool get isInvalid => classification == 'invalid';

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
    );
  }
}
