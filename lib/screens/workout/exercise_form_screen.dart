import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/widgets/form_section_card.dart';
import '../../repositories/exercise_repository.dart';

class ExerciseFormScreen extends StatefulWidget {
  final String? exerciseId;
  const ExerciseFormScreen({super.key, this.exerciseId});

  @override
  State<ExerciseFormScreen> createState() => _ExerciseFormScreenState();
}

class _ExerciseFormScreenState extends State<ExerciseFormScreen> {
  final _exerciseRepo = ExerciseRepository();
  final _nameCtl = TextEditingController();
  final _notesCtl = TextEditingController();
  final _weightIncrementCtl = TextEditingController();
  final _defaultRestCtl = TextEditingController();
  String _categoryId = 'chest';
  String _type = 'weightReps';
  String _equipment = '';
  List<Map<String, dynamic>> _categories = [];
  bool _isLoading = true;
  bool _isSaving = false;
  bool get _isEditing => widget.exerciseId != null;

  final _types = [
    {'id': 'weightReps', 'icon': Icons.fitness_center_rounded},
    {'id': 'distanceTime', 'icon': Icons.straighten_rounded},
    {'id': 'weightDistance', 'icon': Icons.monitor_weight_rounded},
    {'id': 'weightTime', 'icon': Icons.timer_rounded},
    {'id': 'repsDistance', 'icon': Icons.repeat_rounded},
    {'id': 'repsTime', 'icon': Icons.repeat_one_rounded},
    {'id': 'weightOnly', 'icon': Icons.monitor_weight_outlined},
    {'id': 'repsOnly', 'icon': Icons.repeat_one_on_outlined},
    {'id': 'distanceOnly', 'icon': Icons.straighten_outlined},
    {'id': 'timeOnly', 'icon': Icons.timer_outlined},
  ];

  final _equipmentOptions = [
    'Barbell',
    'Dumbbell',
    'Cable',
    'Machine',
    'Bodyweight',
    'Treadmill',
    'Stationary',
    'Kettlebell',
    'Band',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _notesCtl.dispose();
    _weightIncrementCtl.dispose();
    _defaultRestCtl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    _categories = await _exerciseRepo.getCategories();
    if (_isEditing) {
      final ex = await _exerciseRepo.getExercise(widget.exerciseId!);
      if (ex != null) {
        _nameCtl.text = ex['name'] as String? ?? '';
        _categoryId = ex['category_id'] as String? ?? 'chest';
        _type = ex['type'] as String? ?? 'weightReps';
        _notesCtl.text = ex['notes'] as String? ?? '';
        _equipment = ex['equipment'] as String? ?? '';
        final wi = (ex['weight_increment'] as num?)?.toDouble();
        _weightIncrementCtl.text =
            wi != null ? wi.toStringAsFixed(wi.truncateToDouble() == wi ? 0 : 1) : '';
        final drt = ex['default_rest_time'] as int?;
        _defaultRestCtl.text = drt?.toString() ?? '';
      }
    }
    setState(() => _isLoading = false);
  }

  Future<void> _save() async {
    if (_nameCtl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppLocalizations.of(context)!.exerciseFormNameRequired,
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final weightInc = double.tryParse(
        _weightIncrementCtl.text.replaceAll(',', '.'),
      );
      final restTime = int.tryParse(_defaultRestCtl.text);

      if (_isEditing) {
        await _exerciseRepo.updateExercise(
          widget.exerciseId!,
          name: _nameCtl.text.trim(),
          categoryId: _categoryId,
          type: _type,
          notes: _notesCtl.text.trim(),
          equipment: _equipment.isEmpty ? null : _equipment,
          weightIncrement: weightInc,
          defaultRestTime: restTime,
        );
      } else {
        await _exerciseRepo.addExercise(
          name: _nameCtl.text.trim(),
          categoryId: _categoryId,
          type: _type,
          notes: _notesCtl.text.trim(),
          equipment: _equipment.isEmpty ? null : _equipment,
          weightIncrement: weightInc,
          defaultRestTime: restTime,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.commonError(e.toString()),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? loc.exerciseFormTitleEdit : loc.exerciseFormTitleNew,
        ),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _save,
            child: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.exerciseFormSave),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                FormSectionCard(
                  icon: Icons.fitness_center_rounded,
                  title: loc.exerciseFormSectionBasic,
                  children: [
                    FormFieldLabel(text: loc.exerciseFormName),
                    TextField(
                      controller: _nameCtl,
                      decoration: InputDecoration(
                        hintText: loc.exerciseFormNameHint,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                      ),
                      textCapitalization: TextCapitalization.words,
                      autofocus: !_isEditing,
                    ),
                    const SizedBox(height: 16),
                    FormFieldLabel(text: loc.exerciseFormCategory),
                    _buildCategoryPicker(theme),
                    const SizedBox(height: 16),
                    FormFieldLabel(text: loc.exerciseFormType),
                    _buildTypePicker(theme),
                    const SizedBox(height: 16),
                    FormFieldLabel(text: loc.exerciseFormEquipment),
                    Autocomplete<String>(
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) {
                          return _equipmentOptions;
                        }
                        return _equipmentOptions.where(
                          (opt) => opt.toLowerCase().contains(
                                textEditingValue.text.toLowerCase(),
                              ),
                        );
                      },
                      initialValue: TextEditingValue(text: _equipment),
                      onSelected: (v) => _equipment = v,
                      fieldViewBuilder:
                          (ctx, ctl, focusNode, onSubmit) => TextField(
                        controller: ctl,
                        focusNode: focusNode,
                        decoration: InputDecoration(
                          hintText: loc.exerciseFormEquipmentHint,
                          border: const OutlineInputBorder(),
                          filled: true,
                          fillColor:
                              theme.colorScheme.surfaceContainerHighest
                                  .withAlpha(60),
                        ),
                        onSubmitted: (_) => onSubmit(),
                        onChanged: (v) => _equipment = v,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FormSectionCard(
                  icon: Icons.tune_rounded,
                  title: loc.exerciseFormSectionDefaults,
                  children: [
                    FormFieldLabel(text: loc.exerciseFormWeightIncrement),
                    TextField(
                      controller: _weightIncrementCtl,
                      decoration: InputDecoration(
                        hintText: loc.exerciseFormWeightIncrementHint,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FormFieldLabel(text: loc.exerciseFormDefaultRest),
                    TextField(
                      controller: _defaultRestCtl,
                      decoration: InputDecoration(
                        hintText: loc.exerciseFormDefaultRestHint,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    FormFieldLabel(text: loc.exerciseFormNotes),
                    TextField(
                      controller: _notesCtl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: loc.exerciseFormNotesHint,
                        border: const OutlineInputBorder(),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest
                            .withAlpha(60),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryPicker(ThemeData theme) {
    final loc = AppLocalizations.of(context)!;
    final current = _categories.firstWhere(
      (c) => c['id'] == _categoryId,
      orElse: () => {'id': _categoryId, 'name': _categoryId, 'color': 0xFF757575},
    );
    final currentName = ExerciseLocaleHelper.categoryName(loc, current);
    final currentColor = Color(current['color'] as int? ?? 0xFF757575);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: _categories.length,
                itemBuilder: (ctx, i) {
                  final cat = _categories[i];
                  final color = Color(cat['color'] as int? ?? 0xFF757575);
                  final isSelected = cat['id'] == _categoryId;
                  return ListTile(
                    leading: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    title: Text(
                      ExerciseLocaleHelper.categoryName(loc, cat),
                    ),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, cat['id'] as String),
                  );
                },
              ),
            );
          },
        );
        if (selected != null) {
          setState(() => _categoryId = selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        ),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: currentColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(currentName)),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypePicker(ThemeData theme) {
    final current = _types.firstWhere(
      (t) => t['id'] == _type,
      orElse: () => _types.first,
    );
    final currentName = _exerciseTypeName(current['id'] as String);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final selected = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) {
            return SafeArea(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                itemCount: _types.length,
                itemBuilder: (ctx, i) {
                  final t = _types[i];
                  final isSelected = t['id'] == _type;
                  return ListTile(
                    leading: Icon(
                      t['icon'] as IconData,
                      color: theme.colorScheme.primary,
                    ),
                    title: Text(_exerciseTypeName(t['id'] as String)),
                    trailing: isSelected
                        ? Icon(
                            Icons.check_rounded,
                            color: theme.colorScheme.primary,
                          )
                        : null,
                    onTap: () =>
                        Navigator.pop(ctx, t['id'] as String),
                  );
                },
              ),
            );
          },
        );
        if (selected != null) {
          setState(() => _type = selected);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outline),
          borderRadius: BorderRadius.circular(8),
          color: theme.colorScheme.surfaceContainerHighest.withAlpha(60),
        ),
        child: Row(
          children: [
            Icon(
              current['icon'] as IconData,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(currentName)),
            Icon(
              Icons.arrow_drop_down_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  String _exerciseTypeName(String typeId) {
    switch (typeId) {
      case 'weightReps':
        return AppLocalizations.of(context)!.exerciseFormTypeWeightReps;
      case 'distanceTime':
        return AppLocalizations.of(context)!.exerciseFormTypeDistanceTime;
      case 'weightDistance':
        return AppLocalizations.of(context)!.exerciseFormTypeWeightDistance;
      case 'weightTime':
        return AppLocalizations.of(context)!.exerciseFormTypeWeightTime;
      case 'repsDistance':
        return AppLocalizations.of(context)!.exerciseFormTypeRepsDistance;
      case 'repsTime':
        return AppLocalizations.of(context)!.exerciseFormTypeRepsTime;
      case 'weightOnly':
        return AppLocalizations.of(context)!.exerciseFormTypeWeightOnly;
      case 'repsOnly':
        return AppLocalizations.of(context)!.exerciseFormTypeRepsOnly;
      case 'distanceOnly':
        return AppLocalizations.of(context)!.exerciseFormTypeDistanceOnly;
      case 'timeOnly':
        return AppLocalizations.of(context)!.exerciseFormTypeTimeOnly;
      default:
        return typeId;
    }
  }
}
