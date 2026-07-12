import 'package:flutter/material.dart';

/// Personal record reached by the workout that was just completed.
class PR {
  final String exerciseName;
  final String type;
  final String value;
  final String previous;

  const PR({
    required this.exerciseName,
    required this.type,
    required this.value,
    required this.previous,
  });

  String get label => type == 'weight' ? 'Peso Máximo' : 'Volume';

  IconData get icon =>
      type == 'weight' ? Icons.emoji_events : Icons.inventory_2;
}

/// Aggregate values shown after a workout is completed.
class WorkoutSummary {
  final int durationSeconds;
  final double totalVolume;
  final int totalSets;
  final int completedSets;
  final List<PR> prs;
  final double totalDistance;
  final int totalCardioTime;

  const WorkoutSummary({
    required this.durationSeconds,
    required this.totalVolume,
    required this.totalSets,
    required this.completedSets,
    this.prs = const [],
    this.totalDistance = 0,
    this.totalCardioTime = 0,
  });

  String get formattedDuration {
    if (durationSeconds <= 0) return '--';
    final hours = durationSeconds ~/ 3600;
    final minutes = (durationSeconds % 3600) ~/ 60;
    final seconds = durationSeconds % 60;
    if (hours >= 24) {
      final days = hours ~/ 24;
      final remainingHours = hours % 24;
      return remainingHours > 0 ? '${days}d ${remainingHours}h' : '${days}d';
    }
    if (hours > 0) return '${hours}h${minutes.toString().padLeft(2, '0')}min';
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  String get formattedVolume {
    if (totalVolume >= 1000000) {
      return '${(totalVolume / 1000000).toStringAsFixed(1)}M';
    }
    if (totalVolume >= 1000) {
      return '${(totalVolume / 1000).toStringAsFixed(1)}k';
    }
    return totalVolume.toStringAsFixed(0);
  }

  double? get densityKgPerMinute {
    if (durationSeconds <= 0 || totalVolume <= 0) return null;
    return totalVolume / (durationSeconds / 60.0);
  }

  String get formattedDensity {
    final density = densityKgPerMinute;
    if (density == null) return '--';
    return density.toStringAsFixed(density >= 10 ? 0 : 1);
  }

  String get formattedDistance =>
      totalDistance <= 0 ? '--' : '${totalDistance.toStringAsFixed(1)} km';

  String get formattedCardioTime {
    if (totalCardioTime <= 0) return '--';
    final minutes = totalCardioTime ~/ 60;
    if (minutes >= 60) return '${minutes ~/ 60}h${minutes % 60}min';
    return '${minutes}min';
  }
}
