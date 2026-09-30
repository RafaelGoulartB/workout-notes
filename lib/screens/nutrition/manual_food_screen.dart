import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/nutrition/manual_food_controller.dart';
import 'package:workout_notes/widgets/nutrition/manual_food/manual_food_form_sections.dart';

/// Form for adding a new food manually to the local cache. The new
/// food is persisted via [NutritionRepository.createManualFood] and
/// popped to the caller so the search screen can hand it off to the
/// quantity sheet.
///
/// When [initial] is provided (AI label extraction), the form is
/// pre-filled so the user can review and correct the parsed values
/// before saving. [source] is recorded as the food's origin.
class ManualFoodScreen extends StatefulWidget {
  final NutritionRepository repository;
  final String source;
  final AiFoodLabelDraft? initial;
  final FoodWithDetails? existingFood;

  const ManualFoodScreen({
    super.key,
    required this.repository,
    this.source = FoodSource.manual,
    this.initial,
    this.existingFood,
  });

  @override
  State<ManualFoodScreen> createState() => _ManualFoodScreenState();
}

class _ManualFoodScreenState extends State<ManualFoodScreen> {
  final _formKey = GlobalKey<FormState>();
  late final ManualFoodController _form;

  @override
  void initState() {
    super.initState();
    _form = ManualFoodController(
      repository: widget.repository,
      source: widget.source,
      initial: widget.initial,
      existingFood: widget.existingFood,
    );
  }

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    try {
      final food = await _form.save();
      if (!mounted) return;
      Navigator.of(context).pop(food);
    } catch (e) {
      if (!mounted) return;
      final loc = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.commonError(e.toString()))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _form,
      builder: (context, _) {
        final isSaving = _form.isSaving;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.existingFood == null
                  ? loc.nutritionManualTitle
                  : loc.nutritionManualEditTitle,
            ),
            centerTitle: true,
            actions: [
              TextButton(
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(loc.nutritionSave),
              ),
            ],
          ),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                children: [
                  ManualFoodFormSections(
                    form: _form,
                    validators: ManualFoodValidators(loc, _form),
                  ),
                ],
              ),
            ),
          ),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                onPressed: isSaving ? null : _save,
                icon: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(loc.nutritionSave),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
