import 'package:workout_notes/models/ai_proposal.dart';

/// Builds the structured, honest preview of a routine proposal: what is added,
/// removed, replaced, moved or changed, field by field, instead of net counts.
///
/// Pure: takes the routine as it is now ([base], null for a new routine), the
/// final tree the proposal would leave ([target]) and the library data of the
/// exercises involved.
abstract final class RoutineProposalDiff {
  static const _setFields = ['weight', 'reps', 'distance', 'time_seconds'];

  static Map<String, dynamic> build({
    required String action,
    required Map<String, dynamic>? base,
    required Map<String, dynamic> target,
    required Map<String, Map<String, dynamic>> exercises,
  }) {
    final baseDays = <String, Map<String, dynamic>>{};
    final baseDayOrder = <String>[];
    final baseExercises = <String, _BaseExercise>{};
    for (final day in _maps(base?['days'])) {
      final dayId = day['source_day_id'] as String;
      baseDays[dayId] = day;
      baseDayOrder.add(dayId);
      for (final exercise in _maps(day['exercises'])) {
        final id = exercise['source_routine_exercise_id'] as String;
        baseExercises[id] = _BaseExercise(dayId, exercise);
      }
    }

    final targetDays = _maps(target['days']);
    final keptDayIds = <String>{
      for (final day in targetDays)
        if (day['source_day_id'] is String &&
            baseDays.containsKey(day['source_day_id']))
          day['source_day_id'] as String,
    };
    final keptExerciseIds = <String>{
      for (final day in targetDays)
        for (final exercise in _maps(day['exercises']))
          if (exercise['source_routine_exercise_id'] is String &&
              baseExercises.containsKey(exercise['source_routine_exercise_id']))
            exercise['source_routine_exercise_id'] as String,
    };

    final counts = <String, int>{
      'days_added': 0,
      'days_removed': 0,
      'days_changed': 0,
      'exercises_added': 0,
      'exercises_removed': 0,
      'exercises_swapped': 0,
      'exercises_moved': 0,
      'exercises_changed': 0,
      'sets_added': 0,
      'sets_removed': 0,
      'sets_changed': 0,
    };
    final removals = <Map<String, dynamic>>[];
    final replacements = <Map<String, dynamic>>[];

    Map<String, dynamic> info(String? id) => {
      'exercise_id': id,
      'name': exercises[id]?['name'],
      if (exercises[id]?['locale_key'] != null)
        'locale_key': exercises[id]?['locale_key'],
      'exercise_type': exercises[id]?['type'],
    };

    final dayPreviews = <Map<String, dynamic>>[];
    for (var d = 0; d < targetDays.length; d++) {
      final day = targetDays[d];
      final sourceDay = day['source_day_id'] as String?;
      final baseDay = sourceDay == null ? null : baseDays[sourceDay];
      final isNew = baseDay == null;
      var dayChanged = false;
      if (isNew) {
        counts['days_added'] = counts['days_added']! + 1;
      } else if (baseDay['name'] != day['name'] ||
          (baseDay['notes'] ?? '') != (day['notes'] ?? '')) {
        dayChanged = true;
        counts['days_changed'] = counts['days_changed']! + 1;
      }

      final exercisePreviews = <Map<String, dynamic>>[];
      final stayingIds = <String>[];
      for (final exercise in _maps(day['exercises'])) {
        final sourceExercise =
            exercise['source_routine_exercise_id'] as String?;
        final baseEx = sourceExercise == null
            ? null
            : baseExercises[sourceExercise];
        final sets = _maps(exercise['sets']);
        if (baseEx == null) {
          counts['exercises_added'] = counts['exercises_added']! + 1;
          counts['sets_added'] = counts['sets_added']! + sets.length;
          exercisePreviews.add({
            'status': 'added',
            ...info(exercise['exercise_id'] as String?),
            if (exercise['rest_time_seconds'] != null)
              'rest': {'to': exercise['rest_time_seconds']},
            if (exercise['superset_group_id'] != null)
              'superset': {'to': exercise['superset_group_id']},
            'set_count': sets.length,
            'sets': [for (final set in sets) _setPreview('added', set, null)],
          });
          continue;
        }
        final swap = baseEx.exercise['exercise_id'] != exercise['exercise_id'];
        final movedFrom = baseEx.dayId != sourceDay ? baseEx.dayId : null;
        if (movedFrom == null) stayingIds.add(sourceExercise!);
        final restChanged =
            baseEx.exercise['rest_time_seconds'] !=
            exercise['rest_time_seconds'];
        final supersetChanged =
            (baseEx.exercise['superset_group_id'] ?? '') !=
            (exercise['superset_group_id'] ?? '');
        final setPreviews = <Map<String, dynamic>>[];
        var unchangedSets = 0;
        final keptSetIds = <String>{};
        for (final set in sets) {
          final sourceSet = set['source_set_id'] as String?;
          final baseSet = sourceSet == null
              ? null
              : _maps(baseEx.exercise['sets']).firstWhere(
                  (s) => s['source_set_id'] == sourceSet,
                  orElse: () => const {},
                );
          if (baseSet == null || baseSet.isEmpty) {
            counts['sets_added'] = counts['sets_added']! + 1;
            setPreviews.add(_setPreview('added', set, null));
            continue;
          }
          keptSetIds.add(sourceSet!);
          final changes = _setChanges(baseSet, set);
          if (changes.isEmpty) {
            unchangedSets++;
          } else {
            counts['sets_changed'] = counts['sets_changed']! + 1;
            setPreviews.add(_setPreview('changed', set, changes));
          }
        }
        for (final baseSet in _maps(baseEx.exercise['sets'])) {
          if (keptSetIds.contains(baseSet['source_set_id'])) continue;
          counts['sets_removed'] = counts['sets_removed']! + 1;
          setPreviews.add(_setPreview('removed', baseSet, null));
          removals.add({
            'type': 'set',
            'name': exercises[baseEx.exercise['exercise_id']]?['name'],
            if (exercises[baseEx.exercise['exercise_id']]?['locale_key'] !=
                null)
              'locale_key':
                  exercises[baseEx.exercise['exercise_id']]?['locale_key'],
          });
        }
        final changedAtAll =
            swap ||
            restChanged ||
            supersetChanged ||
            setPreviews.isNotEmpty ||
            movedFrom != null;
        if (swap) {
          counts['exercises_swapped'] = counts['exercises_swapped']! + 1;
          replacements.add({
            'type': 'exercise',
            'from': info(baseEx.exercise['exercise_id'] as String?),
            'to': info(exercise['exercise_id'] as String?),
          });
        }
        if (movedFrom != null) {
          counts['exercises_moved'] = counts['exercises_moved']! + 1;
        }
        if (changedAtAll && !swap && movedFrom == null) {
          counts['exercises_changed'] = counts['exercises_changed']! + 1;
        }
        exercisePreviews.add({
          'status': !changedAtAll
              ? 'unchanged'
              : (movedFrom != null &&
                    !swap &&
                    !restChanged &&
                    !supersetChanged &&
                    setPreviews.isEmpty)
              ? 'moved'
              : 'changed',
          ...info(exercise['exercise_id'] as String?),
          if (swap) 'old': info(baseEx.exercise['exercise_id'] as String?),
          if (movedFrom != null)
            'from_day': {
              'name': baseDays[movedFrom]?['name'],
              'index': baseDayOrder.indexOf(movedFrom),
            },
          if (restChanged)
            'rest': {
              'from': baseEx.exercise['rest_time_seconds'],
              'to': exercise['rest_time_seconds'],
            },
          if (supersetChanged)
            'superset': {
              'from': baseEx.exercise['superset_group_id'],
              'to': exercise['superset_group_id'],
            },
          'set_count': sets.length,
          if (unchangedSets > 0) 'unchanged_sets': unchangedSets,
          'sets': setPreviews,
        });
      }

      // Exercises of the base day that the target no longer contains.
      var dayReordered = false;
      if (baseDay != null) {
        for (final baseExercise in _maps(baseDay['exercises'])) {
          final id = baseExercise['source_routine_exercise_id'] as String;
          if (keptExerciseIds.contains(id)) continue;
          final sets = _maps(baseExercise['sets']);
          counts['exercises_removed'] = counts['exercises_removed']! + 1;
          exercisePreviews.add({
            'status': 'removed',
            ...info(baseExercise['exercise_id'] as String?),
            'set_count': sets.length,
          });
          removals.add({
            'type': 'exercise',
            ...info(baseExercise['exercise_id'] as String?),
            'day': baseDay['name'],
            'sets': sets.length,
          });
        }
        final baseSequence = [
          for (final e in _maps(baseDay['exercises']))
            if (stayingIds.contains(e['source_routine_exercise_id']))
              e['source_routine_exercise_id'] as String,
        ];
        dayReordered = !_sameSequence(baseSequence, stayingIds);
      }

      final dayChangedAtAll =
          isNew ||
          dayChanged ||
          dayReordered ||
          exercisePreviews.any((e) => e['status'] != 'unchanged');
      dayPreviews.add({
        'status': isNew
            ? 'added'
            : dayChangedAtAll
            ? 'changed'
            : 'unchanged',
        'name': day['name'],
        if (dayChanged && baseDay != null && baseDay['name'] != day['name'])
          'old_name': baseDay['name'],
        if (dayChanged &&
            baseDay != null &&
            (baseDay['notes'] ?? '') != (day['notes'] ?? ''))
          'notes_changed': true,
        if (dayReordered) 'reordered': true,
        'exercises': exercisePreviews,
      });
    }

    // Days of the base routine that the target dropped.
    final keptDayOrder = [
      for (final id in baseDayOrder)
        if (keptDayIds.contains(id)) id,
    ];
    final targetKeptOrder = [
      for (final day in targetDays)
        if (keptDayIds.contains(day['source_day_id']))
          day['source_day_id'] as String,
    ];
    final daysReordered = !_sameSequence(keptDayOrder, targetKeptOrder);
    for (final dayId in baseDayOrder) {
      if (keptDayIds.contains(dayId)) continue;
      final day = baseDays[dayId]!;
      final removedExercises = [
        for (final e in _maps(day['exercises']))
          if (!keptExerciseIds.contains(e['source_routine_exercise_id'])) e,
      ];
      counts['days_removed'] = counts['days_removed']! + 1;
      counts['exercises_removed'] =
          counts['exercises_removed']! + removedExercises.length;
      dayPreviews.add({
        'status': 'removed',
        'name': day['name'],
        'exercises': [
          for (final e in removedExercises)
            {
              'status': 'removed',
              ...info(e['exercise_id'] as String?),
              'set_count': _maps(e['sets']).length,
            },
        ],
      });
      removals.add({
        'type': 'day',
        'name': day['name'],
        'exercises': removedExercises.length,
      });
      for (final e in removedExercises) {
        removals.add({
          'type': 'exercise',
          ...info(e['exercise_id'] as String?),
          'day': day['name'],
          'sets': _maps(e['sets']).length,
        });
      }
    }

    final baseName = base?['name'] as String?;
    final baseNotes = (base?['notes'] as String?) ?? '';
    return {
      'v': kAiProposalPreviewVersion,
      'action': action,
      'routine_name': target['name'],
      'current_name': ?baseName,
      'name_changed': baseName != null && baseName != target['name'],
      'notes_changed':
          base != null && baseNotes != ((target['notes'] as String?) ?? ''),
      'days_reordered': daysReordered,
      'days': dayPreviews,
      'counts': counts,
      'removals': removals,
      'replacements': replacements,
    };
  }

  /// True when the proposal changes nothing about [base].
  static bool isNoOp(Map<String, dynamic> preview) {
    if (preview['action'] != 'update') return false;
    if (preview['name_changed'] == true || preview['notes_changed'] == true) {
      return false;
    }
    if (preview['days_reordered'] == true) return false;
    return (preview['days'] as List).every((day) {
      final map = day as Map;
      return map['status'] == 'unchanged';
    });
  }

  static Map<String, dynamic> _setPreview(
    String status,
    Map<String, dynamic> set,
    Map<String, dynamic>? changes,
  ) => {
    'status': status,
    if (set['is_warmup'] == true) 'warmup': true,
    'values': {
      for (final field in _setFields)
        if (set[field] != null) field: set[field],
    },
    'changes': ?changes,
  };

  static Map<String, dynamic> _setChanges(
    Map<String, dynamic> before,
    Map<String, dynamic> after,
  ) {
    final out = <String, dynamic>{};
    for (final field in _setFields) {
      final a = before[field];
      final b = after[field];
      if (!_sameNumber(a, b)) out[field] = {'from': a, 'to': b};
    }
    final warmBefore = before['is_warmup'] == true;
    final warmAfter = after['is_warmup'] == true;
    if (warmBefore != warmAfter) {
      out['is_warmup'] = {'from': warmBefore, 'to': warmAfter};
    }
    return out;
  }

  static bool _sameNumber(Object? a, Object? b) {
    if (a == null || b == null) return a == b;
    if (a is num && b is num) return (a - b).abs() < 1e-9;
    return a == b;
  }

  static bool _sameSequence(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static List<Map<String, dynamic>> _maps(Object? value) => value is List
      ? [
          for (final item in value)
            if (item is Map) item.cast<String, dynamic>(),
        ]
      : const [];
}

class _BaseExercise {
  final String dayId;
  final Map<String, dynamic> exercise;
  const _BaseExercise(this.dayId, this.exercise);
}
