import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/periodization/phase_editor_controller.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_identity_cards.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_nutrition_card.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_target_cards.dart';
import 'package:workout_notes/widgets/periodization/phase_editor/phase_weeks_card.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Everything a phase plans, on one screen: what it is and how long it
/// lasts, its template week, nutrition (training vs rest days), training,
/// running, body and sleep targets, and per-week adjustments.
class PeriodizationPhaseEditorScreen extends StatefulWidget {
  final PeriodizationPlan plan;
  final PeriodizationPhase phase;

  /// Injected by tests; the screen builds its own otherwise.
  final PhaseEditorController? controller;

  const PeriodizationPhaseEditorScreen({
    super.key,
    required this.plan,
    required this.phase,
    this.controller,
  });

  @override
  State<PeriodizationPhaseEditorScreen> createState() =>
      _PeriodizationPhaseEditorScreenState();
}

class _PeriodizationPhaseEditorScreenState
    extends State<PeriodizationPhaseEditorScreen> {
  late final PhaseEditorController _controller =
      widget.controller ??
      PhaseEditorController(plan: widget.plan, phase: widget.phase);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    if (widget.controller == null) _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final loc = AppLocalizations.of(context)!;
    if (_controller.name.text.trim().isEmpty) {
      _snack(loc.planningNameRequired);
      return;
    }
    try {
      await _controller.save();
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PeriodizationValidationException catch (error) {
      if (!mounted) return;
      _snack(planningErrorMessage(loc, error.code));
    }
  }

  void _snack(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<bool> _confirmDiscard() async {
    if (!_controller.dirty) return true;
    final loc = AppLocalizations.of(context)!;
    final discard = await showConfirmDialog(
      context,
      title: loc.planningDiscardTitle,
      message: loc.planningDiscardBody,
      confirmLabel: loc.planningDiscard,
      cancelLabel: loc.planningKeepEditing,
    );
    return discard;
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => PopScope(
        canPop: !_controller.dirty,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          final navigator = Navigator.of(context);
          if (await _confirmDiscard()) navigator.pop(false);
        },
        child: Scaffold(
          appBar: AppBar(title: Text(loc.planningEditPhase)),
          body: _controller.loading
              ? const Center(child: CircularProgressIndicator())
              : GestureDetector(
                  onTap: () => FocusScope.of(context).unfocus(),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                    children: [
                      PhaseIdentityCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningTemplateWeek,
                        icon: Icons.view_week_outlined,
                      ),
                      PhaseTemplateWeekCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningNutrition,
                        icon: Icons.restaurant_outlined,
                      ),
                      PhaseNutritionCard(controller: _controller, onSnack: _snack),
                      PlanningSectionLabel(
                        loc.planningTraining,
                        icon: Icons.fitness_center_outlined,
                      ),
                      PhaseTrainingCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningRunning,
                        icon: Icons.directions_run_outlined,
                      ),
                      PhaseRunningCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningBodyAndSleep,
                        icon: Icons.monitor_weight_outlined,
                      ),
                      PhaseBodySleepCard(controller: _controller),
                      PlanningSectionLabel(
                        loc.planningWeeks,
                        icon: Icons.calendar_view_week_outlined,
                      ),
                      PhaseWeeksCard(controller: _controller),
                    ],
                  ),
                ),
          bottomNavigationBar: _controller.loading
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    key: const Key('phaseEditorSave'),
                    onPressed: _controller.saving ? null : _save,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    icon: _controller.saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(loc.planningSave),
                  ),
                ),
        ),
      ),
    );
  }
}
