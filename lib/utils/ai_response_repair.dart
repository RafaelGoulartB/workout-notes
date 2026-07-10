import 'dart:convert';

import '../models/ai_chat_message.dart';
import 'text_sanitizer.dart';

/// Replaces a malformed model answer with a factual summary when the answer
/// was generated from a workout-detail tool result.
class AiResponseRepair {
  static String? repair({
    required String? response,
    required bool hadReferencePlaceholders,
    required Iterable<AiChatMessage> messages,
  }) {
    if (response == null || response.isEmpty) return response;
    if (!hadReferencePlaceholders) return TextSanitizer.sanitize(response);

    final detail = _latestWorkoutDetail(messages);
    if (detail != null) return _workoutSummary(detail);

    return TextSanitizer.sanitize(response);
  }

  static Map<String, dynamic>? _latestWorkoutDetail(
    Iterable<AiChatMessage> messages,
  ) {
    final list = messages.toList(growable: false);
    for (var index = list.length - 1; index >= 0; index--) {
      final message = list[index];
      if (!message.isTool || message.toolName != 'get_workout_detail') {
        continue;
      }
      final data = _toolData(message);
      if (data != null) return data;
    }
    return null;
  }

  static Map<String, dynamic>? _toolData(AiChatMessage message) {
    final result = message.toolResult;
    if (result?.ok == true && result?.data is Map) {
      return (result!.data as Map).cast<String, dynamic>();
    }

    final content = message.content;
    if (content == null || content.isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      if (decoded is! Map || decoded['ok'] != true || decoded['data'] is! Map) {
        return null;
      }
      return (decoded['data'] as Map).cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  static String _workoutSummary(Map<String, dynamic> detail) {
    final exercises = ((detail['exercises'] as List?) ?? const [])
        .whereType<Map>()
        .map((exercise) => exercise.cast<String, dynamic>())
        .toList(growable: false);
    final summaries = exercises.map(_exerciseSummary).toList(growable: false);
    final totalSets = summaries.fold<int>(
      0,
      (total, item) => total + item.sets.length,
    );
    final totalVolume = summaries.fold<double>(
      0,
      (total, item) => total + item.volume,
    );
    final date = _formatDate(detail['date']);

    final lines = <String>[
      'Resumo do último treino (${date ?? 'data não registrada'}):',
      '${summaries.length} exercícios, $totalSets séries e ${_formatKg(totalVolume)} de volume total.',
    ];

    for (final summary in summaries) {
      final sets = summary.sets.isEmpty
          ? 'sem séries registradas'
          : summary.sets.join(', ');
      final setCount = summary.sets.length == 1
          ? '1 série'
          : '${summary.sets.length} séries';
      lines.add(
        '- ${summary.name} — $setCount: $sets → ${_formatKg(summary.volume)}',
      );
    }

    final duration = detail['durationSeconds'];
    if (duration is num && duration > 0) {
      lines.add('Duração: ${_formatDuration(duration.toInt())}.');
    }
    final feeling = detail['feeling'];
    if (feeling is num && feeling > 0) {
      lines.add('Sensação registrada: ${feeling.toInt()}/5.');
    }
    final comment = detail['comment'];
    if (comment is String && comment.trim().isNotEmpty) {
      lines.add('Observação: ${comment.trim()}');
    }

    return lines.join('\n');
  }

  static _ExerciseSummary _exerciseSummary(Map<String, dynamic> exercise) {
    final rawSets = ((exercise['sets'] as List?) ?? const [])
        .whereType<Map>()
        .map((set) => set.cast<String, dynamic>())
        .where((set) => set['isWarmup'] != true)
        .toList(growable: false);
    var volume = 0.0;
    final setLabels = <String>[];
    for (final set in rawSets) {
      final weight = (set['weight'] as num?)?.toDouble() ?? 0;
      final reps = (set['reps'] as num?)?.toInt() ?? 0;
      volume += weight * reps;
      final label = _setLabel(set, weight: weight, reps: reps);
      if (label != null) setLabels.add(label);
    }
    return _ExerciseSummary(
      name: (exercise['exerciseName'] as String?)?.trim().isNotEmpty == true
          ? (exercise['exerciseName'] as String).trim()
          : 'Exercício sem nome',
      sets: setLabels,
      volume: volume,
    );
  }

  static String? _setLabel(
    Map<String, dynamic> set, {
    required double weight,
    required int reps,
  }) {
    if (weight > 0 && reps > 0) return '${_formatNumber(weight)}x$reps';
    final distance = (set['distance'] as num?)?.toDouble() ?? 0;
    if (distance > 0) return '${_formatNumber(distance)} km';
    final seconds = (set['timeSeconds'] as num?)?.toInt() ?? 0;
    if (seconds > 0) return _formatDuration(seconds);
    return null;
  }

  static String _formatKg(double value) => '${_formatNumber(value)} kg';

  static String _formatNumber(double value) {
    final isWhole = value == value.roundToDouble();
    final plain = isWhole ? value.toInt().toString() : value.toStringAsFixed(1);
    final parts = plain.split('.');
    final integer = parts.first;
    final groups = <String>[];
    for (var end = integer.length; end > 0; end -= 3) {
      final start = end - 3 < 0 ? 0 : end - 3;
      groups.insert(0, integer.substring(start, end));
    }
    return parts.length == 1
        ? groups.join('.')
        : '${groups.join('.')},${parts.last}';
  }

  static String? _formatDate(dynamic raw) {
    if (raw is! String || raw.isEmpty) return null;
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  static String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) {
      return minutes > 0 ? '${hours}h ${minutes}min' : '${hours}h';
    }
    return '${minutes} min';
  }
}

class _ExerciseSummary {
  final String name;
  final List<String> sets;
  final double volume;

  const _ExerciseSummary({
    required this.name,
    required this.sets,
    required this.volume,
  });
}
