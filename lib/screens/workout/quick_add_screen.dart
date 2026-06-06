import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import '../../database/database_helper.dart';

class QuickAddScreen extends StatefulWidget {
  const QuickAddScreen({super.key});

  @override
  State<QuickAddScreen> createState() => _QuickAddScreenState();
}

class _QuickAddScreenState extends State<QuickAddScreen> {
  final _db = DatabaseHelper.instance;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  List<_ParsedSet> _parsedSets = [];
  String? _error;
  bool _isSaving = false;

  // Suggestions
  List<Map<String, dynamic>> _recentExercises = [];

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _focusNode.requestFocus();
  }

  Future<void> _loadRecent() async {
    final workouts = await _db.getWorkouts(limit: 5);
    final exerciseIds = <String>{};
    final exercises = <Map<String, dynamic>>[];

    for (final w in workouts) {
      final entries = await _db.getWorkoutExercises(w['id'] as String);
      for (final e in entries) {
        final exId = e['exercise_id'] as String;
        if (!exerciseIds.contains(exId)) {
          exerciseIds.add(exId);
          exercises.add({
            'id': exId,
            'name': e['exercise_name'],
            'category_name': e['category_name'],
          });
        }
      }
    }

    if (mounted) setState(() => _recentExercises = exercises);
  }

  void _parseText(String text) {
    if (text.trim().isEmpty) {
      setState(() {
        _parsedSets = [];
        _error = null;
      });
      return;
    }

    // Parse formats:
    // "Supino 80kg 3x10" or "Supino 80kg x 3x10" or "Supino 80 3x10"
    // "Supino 80kg 10reps" or "Supino 80kg 10" 
    // "Supino 50kg 3x12 2x10" (multiple sets)
    try {
      final parts = text.trim().split(RegExp(r'\s+'));
      if (parts.length < 2) {
        setState(() {
          _parsedSets = [];
          _error = AppLocalizations.of(context)!.quickAddFormatError;
        });
        return;
      }

      // Find exercise name (could be multiple words)
      // Weight is the first number found
      int weightIdx = -1;
      double weight = 0;
      for (int i = 1; i < parts.length; i++) {
        final cleaned = parts[i].replaceAll('kg', '').replaceAll(',', '.');
        final num = double.tryParse(cleaned);
        if (num != null) {
          weight = num;
          weightIdx = i;
          break;
        }
      }

      if (weightIdx == -1) {
        setState(() {
          _parsedSets = [];
          _error = AppLocalizations.of(context)!.quickAddWeightNotFound;
        });
        return;
      }

      final exerciseName = parts.sublist(0, weightIdx).join(' ');

      // Remaining parts contain sets/reps info
      final remaining = parts.sublist(weightIdx + 1);
      final sets = <_ParsedSet>[];

      if (remaining.isEmpty) {
        // Just weight, assume 1 set with no reps
        sets.add(_ParsedSet(weight: weight, reps: null));
      } else {
        for (final part in remaining) {
          // Check for format like "3x10" or "3×10"
          final match = RegExp(r'(\d+)\s*[x×]\s*(\d+)').firstMatch(part);
          if (match != null) {
            final numSets = int.parse(match.group(1)!);
            final numReps = int.parse(match.group(2)!);
            for (int i = 0; i < numSets; i++) {
              sets.add(_ParsedSet(weight: weight, reps: numReps));
            }
          } else if (part.endsWith('reps') || part == 'reps') {
            // Just reps
            final reps = int.tryParse(part.replaceAll('reps', ''));
            if (reps != null && reps > 0) {
              if (sets.isEmpty) {
                sets.add(_ParsedSet(weight: weight, reps: reps));
              } else {
                // Apply to last set
                sets.last = _ParsedSet(weight: sets.last.weight, reps: reps);
              }
            }
          } else {
            // Try as just reps
            final reps = int.tryParse(part);
            if (reps != null && reps > 0 && reps <= 100) {
              if (sets.isEmpty) {
                sets.add(_ParsedSet(weight: weight, reps: reps));
              } else {
                sets.add(_ParsedSet(weight: weight, reps: reps));
              }
            }
          }
        }
      }

      setState(() {
        _parsedSets = sets;
        _error = sets.isEmpty ? AppLocalizations.of(context)!.quickAddNoSets : null;
      });
    } catch (e) {
      setState(() {
        _parsedSets = [];
        _error = '${AppLocalizations.of(context)!.commonError(e.toString())}';
      });
    }
  }

  Future<void> _save() async {
    if (_parsedSets.isEmpty || _textController.text.trim().isEmpty) return;

    setState(() => _isSaving = true);

    try {
      // Parse exercise name and weight from text
      final parts = _textController.text.trim().split(RegExp(r'\s+'));
      int weightIdx = -1;
      double weight = 0;
      for (int i = 1; i < parts.length; i++) {
        final cleaned = parts[i].replaceAll('kg', '').replaceAll(',', '.');
        final num = double.tryParse(cleaned);
        if (num != null) {
          weight = num;
          weightIdx = i;
          break;
        }
      }

      final exerciseName = parts.sublist(0, weightIdx).join(' ');

      // Find or create exercise — search both DB name and localized names
      Map<String, dynamic>? exercise;
      // First try SQL LIKE search on DB name
      final exercises = await _db.getExercises(search: exerciseName);
      if (exercises.isNotEmpty) {
        exercise = exercises.firstWhere(
          (e) => (e['name'] as String).toLowerCase() == exerciseName.toLowerCase(),
          orElse: () => exercises.first,
        );
      }
      // If not found, search across all exercises using localized names
      if (exercise == null) {
        final loc = AppLocalizations.of(context);
        if (loc != null) {
          final allExercises = await _db.getExercises();
          for (final ex in allExercises) {
            if (ExerciseLocaleHelper.exerciseMatchesSearch(loc, ex, exerciseName)) {
              exercise = ex;
              break;
            }
          }
        }
      }

      if (exercise == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context)!.quickAddExerciseNotFound(exerciseName)),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: AppLocalizations.of(context)!.quickAddCreate,
                onPressed: () => _createAndSave(exerciseName, weight),
              ),
            ),
          );
        }
        setState(() => _isSaving = false);
        return;
      }

      // Create workout and add sets
      final workoutId = await _db.createWorkout();
      final entryId = const Uuid().v4();

      final database = await _db.database;
      await database.insert('exercise_entries', {
        'id': entryId,
        'workout_id': workoutId,
        'exercise_id': exercise['id'],
        'order_index': 0,
      });

      for (final set in _parsedSets) {
        await _db.addSet(
          exerciseEntryId: entryId,
          weight: set.weight,
          reps: set.reps,
        );
      }

      // Finish workout automatically
      await _db.finishWorkout(workoutId, feelingRating: 3);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.quickAddSaved(exercise['name'], _parsedSets.length.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.commonError(e.toString())), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  Future<void> _createAndSave(String exerciseName, double weight) async {
    final catId = 'fullbody';
    final exId = await _db.addExercise(
      name: exerciseName,
      categoryId: catId,
    );

    final workoutId = await _db.createWorkout();
    final entryId = const Uuid().v4();
    final database = await _db.database;
    await database.insert('exercise_entries', {
      'id': entryId,
      'workout_id': workoutId,
      'exercise_id': exId,
      'order_index': 0,
    });

    for (final set in _parsedSets) {
      await _db.addSet(
        exerciseEntryId: entryId,
        weight: set.weight,
        reps: set.reps,
      );
    }

    await _db.finishWorkout(workoutId, feelingRating: 3);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.quickAddCreatedAndSaved(exerciseName)), behavior: SnackBarBehavior.floating),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.quickAddTitle),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _parsedSets.isNotEmpty && !_isSaving ? _save : null,
            child: _isSaving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(AppLocalizations.of(context)!.quickAddSave),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Input
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: theme.colorScheme.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  maxLines: null,
                  textInputAction: TextInputAction.done,
                  onChanged: _parseText,
                  onSubmitted: (_) => _parsedSets.isNotEmpty ? _save() : null,
                  style: theme.textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.quickAddHint,
                    hintStyle: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant.withAlpha(120)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.all(16),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // Error
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),

            // Examples
            if (_parsedSets.isEmpty && _textController.text.isEmpty) ...[
              const SizedBox(height: 16),
              Text(AppLocalizations.of(context)!.quickAddAcceptedFormats, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...[
                'Supino 80kg 3x10',
                'Rosca Direta 12kg 3x12',
                'Agachamento 100kg 5x5',
                'Leg Press 200kg 4x8',
                'Puxada Alta 50kg 3x10',
              ].map((ex) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: GestureDetector(
                  onTap: () {
                    _textController.text = ex;
                    _textController.selection = TextSelection.fromPosition(TextPosition(offset: ex.length));
                    _parseText(ex);
                    _focusNode.requestFocus();
                  },
                  child: Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 16, color: theme.colorScheme.secondary),
                      const SizedBox(width: 8),
                      Text(ex, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.secondary)),
                    ],
                  ),
                ),
              )),
            ],

            // Parsed sets preview
            if (_parsedSets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  Text(AppLocalizations.of(context)!.quickAddSetsIdentified(_parsedSets.length.toString()),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    children: _parsedSets.asMap().entries.map((entry) {
                      final i = entry.key;
                      final set = entry.value;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                              width: 28, height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: theme.colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text('${i + 1}', style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 12),
                            Text('${set.weight.toStringAsFixed(1)} kg',
                                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                            if (set.reps != null) ...[
                              const SizedBox(width: 8),
                              Text('× ${set.reps} reps', style: theme.textTheme.bodyMedium),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],

            // Recent exercises quick pick
            if (_recentExercises.isNotEmpty && _textController.text.isEmpty) ...[
              const SizedBox(height: 24),
              Text(AppLocalizations.of(context)!.quickAddRecentExercises, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _recentExercises.map((ex) => ActionChip(
                  avatar: const Icon(Icons.fitness_center, size: 16),
                  label: Text('${ex['name']}'),
                  onPressed: () {
                    _textController.text = '${ex['name']} ';
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: _textController.text.length),
                    );
                    _focusNode.requestFocus();
                  },
                )).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ParsedSet {
  final double weight;
  final int? reps;
  _ParsedSet({required this.weight, this.reps});
}
