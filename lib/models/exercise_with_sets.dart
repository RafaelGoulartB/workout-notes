import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';

/// Model representing an exercise with its sets during an active workout.
class ExerciseWithSets {
  final String entryId;
  final String exerciseId;
  final String name;
  final String? localeKey;
  final String exerciseType;
  final String? categoryId;
  final String categoryName;
  final Color categoryColor;
  final List<Map<String, dynamic>> sets;
  final int restTimeSeconds;

  ExerciseWithSets({
    required this.entryId,
    required this.exerciseId,
    required this.name,
    this.localeKey,
    required this.exerciseType,
    this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    List<Map<String, dynamic>>? sets,
    this.restTimeSeconds = 90,
  }) : sets = sets ?? [];

  String localizedName(AppLocalizations loc) {
    if (localeKey != null) {
      final translated = ExerciseLocaleHelper.exerciseNameFromKey(
        loc,
        localeKey!,
      );
      if (translated.isNotEmpty) return translated;
    }
    return name;
  }

  String localizedCategory(AppLocalizations loc) {
    if (categoryId != null) {
      final translated = ExerciseLocaleHelper.categoryNameFromId(
        loc,
        categoryId!,
      );
      if (translated.isNotEmpty) return translated;
    }
    return categoryName;
  }

  int get completedSets =>
      sets.where((s) => (s['is_complete'] as int?) == 1).length;

  double get maxWeight => sets.fold<double>(0, (max, s) {
    final w = (s['weight'] as num?)?.toDouble() ?? 0;
    return w > max ? w : max;
  });
}

/// Volume comparison for a strength exercise in the active workout.
class ExerciseVolumeComparison {
  final String exerciseId;
  final double currentVolume;
  final double lastVolume;

  const ExerciseVolumeComparison({
    required this.exerciseId,
    required this.currentVolume,
    required this.lastVolume,
  });

  double get delta => currentVolume - lastVolume;

  double? get deltaPercent =>
      lastVolume > 0 ? (delta / lastVolume) * 100 : null;
}

/// Volume comparison grouped by exercise category/muscle group.
class CategoryVolumeComparison {
  final String categoryId;
  final String categoryName;
  final Color categoryColor;
  final double currentVolume;
  final double lastVolume;

  const CategoryVolumeComparison({
    required this.categoryId,
    required this.categoryName,
    required this.categoryColor,
    required this.currentVolume,
    required this.lastVolume,
  });

  double get delta => currentVolume - lastVolume;

  double? get deltaPercent =>
      lastVolume > 0 ? (delta / lastVolume) * 100 : null;
}
