import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/planning_widgets.dart';

import 'periodization_plan_editor_screen.dart';
import 'periodization_plan_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Every plan — active first, then drafts, finished and archived — each
/// with its roadmap. Tapping one opens it; the FAB creates a new plan.
class PeriodizationPlansScreen extends StatefulWidget {
  const PeriodizationPlansScreen({super.key});

  @override
  State<PeriodizationPlansScreen> createState() =>
      _PeriodizationPlansScreenState();
}

class _PeriodizationPlansScreenState extends State<PeriodizationPlansScreen> {
  final _repository = PeriodizationRepository();
  List<(PeriodizationPlan, List<PeriodizationPhase>)>? _plans;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await _repository.getPlans();
    final phases = await Future.wait(
      plans.map((plan) => _repository.getPhases(plan.id)),
    );
    if (!mounted) return;
    setState(
      () => _plans = [
        for (var i = 0; i < plans.length; i++) (plans[i], phases[i]),
      ],
    );
  }

  Future<void> _create() async {
    final planId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlanEditorScreen()),
    );
    if (planId != null) await _load();
  }

  Future<void> _open(PeriodizationPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => PeriodizationPlanScreen(plan: plan)),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final plans = _plans;
    final now = DateTime.now();
    final today = dayOf(now);
    return Scaffold(
      appBar: AppBar(title: Text(loc.planningMyPlans)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add_rounded),
        label: Text(loc.planningNewPlan),
      ),
      body: plans == null
          ? const Center(child: CircularProgressIndicator())
          : plans.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  loc.planningNoPlans,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 110),
              itemCount: plans.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final (plan, phases) = plans[index];
                final active = plan.status == PeriodizationPlanStatus.active;
                return PlanningCard(
                  onTap: () => _open(plan),
                  borderColor: active ? scheme.primary.withAlpha(140) : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              plan.name,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          PlanningPill(
                            icon: active
                                ? Icons.play_arrow_rounded
                                : Icons.circle_outlined,
                            label: planStatusLabel(loc, plan.status),
                            color: active ? scheme.primary : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${planningDateRange(plan.startDate, plan.endDate)} · '
                        '${loc.planningPhasesCount(phases.length)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (phases.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        PlanRoadmap(phases: phases, today: today),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}
