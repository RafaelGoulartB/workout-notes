import 'sleep_stage_type.dart';

/// A privacy-preserving 30-second sleep-stage prediction.
///
/// Only probabilities and the resulting label are persisted. Audio samples
/// and spectrograms never cross this model boundary.
class SleepStageEpoch {
  final String id;
  final String sessionId;
  final DateTime startedAt;
  final int durationSeconds;
  final SleepStageType stage;
  final double confidence;
  final double? awakeProbability;
  final double? sleepingProbability;
  final double? deepProbability;
  final String algorithmVersion;
  final String source;

  const SleepStageEpoch({
    required this.id,
    required this.sessionId,
    required this.startedAt,
    required this.durationSeconds,
    required this.stage,
    required this.confidence,
    required this.awakeProbability,
    required this.sleepingProbability,
    required this.deepProbability,
    required this.algorithmVersion,
    this.source = 'acoustic_model',
  });

  DateTime get endedAt =>
      startedAt.add(Duration(seconds: durationSeconds.clamp(1, 3600)));

  bool get isSleep =>
      stage == SleepStageType.sleeping || stage == SleepStageType.deep;

  Map<String, dynamic> toMap() => {
    'id': id,
    'session_id': sessionId,
    'started_at': startedAt.toIso8601String(),
    'duration_seconds': durationSeconds,
    'stage': stage.name,
    'confidence': confidence,
    'awake_probability': awakeProbability,
    'sleeping_probability': sleepingProbability,
    'deep_probability': deepProbability,
    'algorithm_version': algorithmVersion,
    'source': source,
  };

  factory SleepStageEpoch.fromMap(Map<String, dynamic> map) {
    return SleepStageEpoch(
      id: map['id'] as String,
      sessionId: map['session_id'] as String,
      startedAt: DateTime.parse(map['started_at'] as String),
      durationSeconds: (map['duration_seconds'] as num).toInt(),
      stage: SleepStageType.fromWire(map['stage']),
      confidence: (map['confidence'] as num?)?.toDouble() ?? 0,
      awakeProbability: (map['awake_probability'] as num?)?.toDouble(),
      sleepingProbability: (map['sleeping_probability'] as num?)?.toDouble(),
      deepProbability: (map['deep_probability'] as num?)?.toDouble(),
      algorithmVersion:
          (map['algorithm_version'] as String?) ?? 'unknown-model',
      source: (map['source'] as String?) ?? 'acoustic_model',
    );
  }
}
