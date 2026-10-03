import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_template.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_controller.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_days_step.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_intent_step.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_pace_step.dart';
import 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_preview_step.dart';
import 'package:workout_notes/services/run_plan_history.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/services/run_plan_text.dart';
import 'package:workout_notes/services/runner_strength_routine.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

export 'package:workout_notes/screens/run/plan_wizard/run_plan_wizard_time.dart'
    show parseRaceTime;

/// Coach-style wizard: days → intent/volume → paces → preview → create.
///
/// Pops with the created [RunPlan]. The new plan is activated right away
/// (with an undo) unless that would silently replace a plan the athlete is
/// already following.
class RunPlanCustomizeScreen extends StatefulWidget {
  final RunPlanTemplate template;

  /// When set, skips loading GPS history (tests).
  final RunPlanHistoryInsights? history;

  /// Clock for race-date maths (tests).
  final DateTime? today;

  const RunPlanCustomizeScreen({
    super.key,
    required this.template,
    this.history,
    this.today,
  });

  @override
  State<RunPlanCustomizeScreen> createState() => _RunPlanCustomizeScreenState();
}

class _RunPlanCustomizeScreenState extends State<RunPlanCustomizeScreen> {
  final _repo = DatabaseHelper.instance.runPlanRepo;
  late final RunPlanWizardController _controller;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _controller = RunPlanWizardController(
      template: widget.template,
      history: widget.history,
      todayOverride: widget.today,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.language = _language(context);
    _controller.seedName();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static RunPlanLanguage _language(BuildContext context) =>
      Localizations.localeOf(context).languageCode == 'pt'
      ? RunPlanLanguage.pt
      : RunPlanLanguage.en;

  /// Opens [template] in a fresh wizard; a plan created there closes this one.
  Future<void> _switchTo(RunPlanTemplate template) async {
    final plan = await Navigator.push<RunPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanCustomizeScreen(
          template: template,
          history: _controller.history,
          today: widget.today,
        ),
      ),
    );
    if (plan != null && mounted) Navigator.pop(context, plan);
  }

  /// Closes the wizard, asking first when that would throw answers away.
  Future<void> _requestClose() async {
    if (_creating) return;
    if (!_controller.hasChanges) {
      Navigator.pop(context);
      return;
    }
    final loc = AppLocalizations.of(context)!;
    final discard = await showConfirmDialog(
      context,
      title: loc.runPlanWizardDiscardTitle,
      message: loc.runPlanWizardDiscardBody,
      confirmLabel: loc.commonDiscard,
      cancelLabel: loc.runPlanWizardKeepEditing,
      destructive: true,
    );
    if (discard == true && mounted) Navigator.pop(context);
  }

  /// Follows the freshly created [plan]. Returns the number of scheduled
  /// sessions, or null when the plan was left inactive: another plan is being
  /// followed and the athlete declined to switch, that plan drives a planning
  /// phase (never replaced behind its back), or activation failed. A failure
  /// here must never cost the athlete the plan they just built.
  Future<int?> _activate(RunPlan plan, AppLocalizations loc) async {
    try {
      final current = await _repo.getActivatedPlan(hydrate: false);
      if (current != null && current.id != plan.id) {
        if (await _repo.isLinkedToPeriodization(current.id)) return null;
        if (!mounted) return null;
        final confirmed = await showConfirmDialog(
          context,
          title: loc.runPlanReplaceActiveTitle,
          message: loc.runPlanReplaceActiveBody(current.name),
          confirmLabel: loc.runPlanActivate,
          cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
        );
        if (confirmed != true) return null;
      }
      return await _repo.activatePlan(plan.id);
    } catch (_) {
      return null;
    }
  }

  Future<void> _create() async {
    final outline = _controller.outline;
    if (_creating ||
        !_controller.daysValid ||
        !(outline?.readiness.canCreate ?? false)) {
      return;
    }
    setState(() => _creating = true);
    final loc = AppLocalizations.of(context)!;
    // Grabbed up front: the SnackBar has to outlive this route's pop.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final RunPlan plan;
    try {
      plan = await RunPlanTemplates.create(
        _repo,
        widget.template,
        name: _controller.planName,
        config: _controller.config,
      );
      if (_controller.includeStrength) {
        try {
          await RunnerStrengthRoutine().ensure(pt: _controller.isPt);
        } catch (_) {
          // The plan stands on its own; strength can be set up later.
        }
      }
    } catch (e, stack) {
      debugPrint('run_plan_customize_screen: action failed: $e\n$stack');
      if (!mounted) return;
      setState(() => _creating = false);
      messenger.showSnackBar(
        SnackBar(content: Text(loc.commonSomethingWentWrong)),
      );
      return;
    }
    final scheduled = await _activate(plan, loc);
    if (!mounted) return;
    navigator.pop(plan);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            scheduled == null
                ? loc.runPlanWizardCreatedMessage
                : loc.runPlanActivatedMessage(scheduled),
          ),
          action: scheduled == null
              ? null
              : SnackBarAction(
                  label: loc.commonUndo,
                  onPressed: () => _repo.deactivatePlan(plan.id),
                ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) => _buildScaffold(context),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final controller = _controller;
    final outline = controller.outline;
    final step = controller.step;
    final last = step == kRunPlanWizardSteps - 1;
    final canNext = controller.canAdvance(outline);

    return PopScope(
      canPop: !controller.hasChanges && !_creating,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _requestClose();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(loc.runPlanCustomizeTitle),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: _requestClose,
          ),
        ),
        body: Column(
          children: [
            _WizardHeader(
              title: widget.template.title(controller.isPt),
              step: step,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  switch (step) {
                    0 => RunPlanWizardDaysStep(
                      controller: controller,
                      outline: outline,
                      onSwitchTemplate: _switchTo,
                    ),
                    1 => RunPlanWizardIntentStep(controller: controller),
                    2 => RunPlanWizardPaceStep(
                      controller: controller,
                      outline: outline,
                    ),
                    _ => RunPlanWizardPreviewStep(
                      controller: controller,
                      outline: outline,
                      onSwitchTemplate: _switchTo,
                    ),
                  },
                ],
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Row(
                  children: [
                    if (step > 0)
                      TextButton(
                        onPressed: _creating ? null : controller.back,
                        child: Text(loc.runPlanCustomizeBack),
                      ),
                    const Spacer(),
                    FilledButton(
                      onPressed: !canNext || _creating
                          ? null
                          : (last ? _create : controller.next),
                      child: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              last
                                  ? loc.runPlanCustomizeCreate
                                  : loc.runPlanCustomizeNext,
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Template title, tagline and the four-segment progress bar.
class _WizardHeader extends StatelessWidget {
  final String title;
  final int step;

  const _WizardHeader({required this.title, required this.step});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.runPlanCustomizeSubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (var i = 0; i < kRunPlanWizardSteps; i++)
                Expanded(
                  child: Container(
                    height: 4,
                    margin: EdgeInsets.only(
                      right: i < kRunPlanWizardSteps - 1 ? 6 : 0,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      color: i <= step
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            loc.runPlanWizardStepOf(step + 1, kRunPlanWizardSteps),
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
