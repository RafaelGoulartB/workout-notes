import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/plan_overview.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';

import 'periodization_phase_screen.dart';
import 'periodization_plan_editor_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// A plan that is not necessarily the active one: its roadmap and phases,
/// plus activating, editing, finishing, archiving and deleting it.
class PeriodizationPlanScreen extends StatefulWidget {
  final PeriodizationPlan plan;

  const PeriodizationPlanScreen({super.key, required this.plan});

  @override
  State<PeriodizationPlanScreen> createState() =>
      _PeriodizationPlanScreenState();
}

class _PeriodizationPlanScreenState extends State<PeriodizationPlanScreen> {
  final _repository = DatabaseHelper.instance.periodizationRepo;
  PlanOverviewData? _data;

  DateTime get _today {
    final now = DateTime.now();
    return dayOf(now);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plan = await _repository.getPlan(widget.plan.id);
    if (plan == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    final data = await PlanOverviewData.load(_repository, plan);
    if (mounted) setState(() => _data = data);
  }

  Future<void> _setStatus(PeriodizationPlanStatus status) async {
    final loc = AppLocalizations.of(context)!;
    try {
      await _repository.setPlanStatus(widget.plan.id, status);
    } on PeriodizationValidationException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(planningErrorMessage(loc, error.code))),
      );
    }
    await _load();
  }

  Future<void> _edit() async {
    final plan = _data?.plan;
    if (plan == null) return;
    final saved = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationPlanEditorScreen(plan: plan),
      ),
    );
    if (saved != null) await _load();
  }

  Future<void> _delete() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.planningDeletePlanTitle,
      message: loc.planningDeletePlanBody(widget.plan.name),
      confirmLabel: loc.planningDelete,
    );
    if (confirmed != true) return;
    await _repository.deletePlan(widget.plan.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final data = _data;
    final plan = data?.plan ?? widget.plan;
    final active = plan.status == PeriodizationPlanStatus.active;
    return Scaffold(
      appBar: AppBar(
        title: Text(plan.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => switch (value) {
              'activate' => _setStatus(PeriodizationPlanStatus.active),
              'edit' => _edit(),
              'finish' => _setStatus(PeriodizationPlanStatus.completed),
              'archive' => _setStatus(PeriodizationPlanStatus.archived),
              'delete' => _delete(),
              _ => null,
            },
            itemBuilder: (context) => [
              if (!active)
                PopupMenuItem(
                  value: 'activate',
                  child: Text(loc.planningActivate),
                ),
              PopupMenuItem(value: 'edit', child: Text(loc.planningEditPlan)),
              if (plan.status != PeriodizationPlanStatus.completed)
                PopupMenuItem(
                  value: 'finish',
                  child: Text(loc.planningFinishPlan),
                ),
              if (plan.status != PeriodizationPlanStatus.archived)
                PopupMenuItem(
                  value: 'archive',
                  child: Text(loc.planningArchive),
                ),
              PopupMenuItem(value: 'delete', child: Text(loc.planningDelete)),
            ],
          ),
        ],
      ),
      body: data == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (!active) ...[
                  PlanningCard(
                    color: theme.colorScheme.secondaryContainer.withAlpha(90),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            loc.planningPlanInactive(
                              planStatusLabel(loc, plan.status),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          key: const Key('planActivate'),
                          onPressed: () =>
                              _setStatus(PeriodizationPlanStatus.active),
                          child: Text(loc.planningActivate),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                PlanHeaderCard(data: data, today: _today),
                PlanningSectionLabel(
                  loc.planningPhasesCount(data.phases.length),
                  icon: Icons.view_timeline_outlined,
                  actionLabel: loc.planningEdit,
                  onAction: _edit,
                ),
                for (final phase in data.phases)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: PhaseSummaryCard(
                      phase: phase,
                      target: data.targets[phase.id],
                      data: data,
                      today: _today,
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PeriodizationPhaseScreen(
                              plan: plan,
                              phase: phase,
                            ),
                          ),
                        );
                        await _load();
                      },
                    ),
                  ),
              ],
            ),
    );
  }
}

String planStatusLabel(AppLocalizations loc, PeriodizationPlanStatus status) =>
    switch (status) {
      PeriodizationPlanStatus.active => loc.planningStatusActive,
      PeriodizationPlanStatus.draft => loc.planningStatusDraft,
      PeriodizationPlanStatus.completed => loc.planningStatusCompleted,
      PeriodizationPlanStatus.archived => loc.planningStatusArchived,
    };
