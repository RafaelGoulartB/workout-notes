import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/plans/run_plan_activation.dart';
import 'package:workout_notes/screens/run/plans/run_plan_creation_flow.dart';
import 'package:workout_notes/screens/run/run_plan_detail_screen.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';
import 'package:workout_notes/widgets/run/plans/run_plan_library_cards.dart';
import 'package:workout_notes/widgets/ui/guarded_load.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// The running counterpart of [RoutinesScreen]: a library of structured plans.
/// The plan being followed is pinned on top with its next session; the rest
/// of the library sits below it.
class RunPlansScreen extends StatefulWidget {
  const RunPlansScreen({super.key});

  @override
  State<RunPlansScreen> createState() => _RunPlansScreenState();
}

class _RunPlansScreenState extends State<RunPlansScreen> with GuardedLoad {
  final _repo = DatabaseHelper.instance.runPlanRepo;
  List<RunPlan> _plans = const [];
  Map<String, RunPlanProgress> _progress = const {};

  /// Plans whose weeks are driven by a periodization phase. Those are shown as
  /// followed through the planning instead of offering their own activation.
  Set<String> _linkedToPlanning = const {};

  /// Today's / next session of the followed plan.
  RunPlanSessionView? _next;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() => guardedLoad(() async {
    final plans = await _repo.listPlans(
      includeArchived: _showArchived,
      hydrate: true,
    );
    final ids = [for (final plan in plans) plan.id];
    final progress = await _repo.getPlanProgressBatch(ids);
    final linked = await _repo.getPlanningLinkedIds(ids);
    final followed = plans.where((p) => p.isActivated).firstOrNull;
    RunPlanSessionView? next;
    if (followed != null) {
      final ledger = await _repo.getPlanLedger(followed.id);
      next = RunPlanWeekView.nextSession(followed, ledger, DateTime.now());
    }
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _progress = progress;
      _linkedToPlanning = linked;
      _next = next;
      isLoading = false;
    });
  });

  Future<void> _activate(RunPlan plan) async {
    if (await followRunPlan(context, _repo, plan) && mounted) await _load();
  }

  Future<void> _deactivate(RunPlan plan) async {
    await unfollowRunPlan(context, _repo, plan);
    if (mounted) await _load();
  }

  Future<void> _openPlan(RunPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunPlanDetailScreen(planId: plan.id)),
    );
    if (mounted) await _load();
  }

  Future<void> _createPlan() async {
    final plan = await startNewRunPlan(context, _repo);
    if (!mounted || plan == null) return;
    await _openPlan(plan);
  }

  Future<void> _startNext() async {
    final view = _next;
    if (view == null) return;
    await startRunPlanSession(context, _repo, view);
    if (mounted) await _load();
  }

  Future<void> _duplicate(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    await _repo.duplicatePlan(plan.id, loc.runPlansDuplicateSuffix(plan.name));
    if (mounted) await _load();
  }

  Future<void> _toggleArchive(RunPlan plan) async {
    await _repo.updatePlan(
      plan.id,
      status: plan.isArchived ? RunPlanStatus.active : RunPlanStatus.archived,
    );
    if (mounted) await _load();
  }

  Future<void> _delete(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.runPlansDeleteConfirm(plan.name),
      message: loc.runPlansDeleteContent,
      confirmLabel: loc.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    await _repo.deletePlan(plan.id);
    if (mounted) await _load();
  }

  RunPlanCardActions _actionsFor(RunPlan plan) => RunPlanCardActions(
    onOpen: () => _openPlan(plan),
    onDuplicate: () => _duplicate(plan),
    onToggleArchive: () => _toggleArchive(plan),
    onDelete: () => _delete(plan),
    onActivate: () => _activate(plan),
    onDeactivate: () => _deactivate(plan),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final today = DateTime.now();
    final live = _plans.where((plan) => !plan.isArchived).toList();
    final pinned = [
      for (final plan in live)
        if (plan.isActivated || _linkedToPlanning.contains(plan.id)) plan,
    ]..sort((a, b) => (b.isActivated ? 1 : 0) - (a.isActivated ? 1 : 0));
    final others = [
      for (final plan in live)
        if (!pinned.contains(plan)) plan,
    ];
    final archived = _plans.where((plan) => plan.isArchived).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.runPlansTitle),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: loc.runPlansShowArchived,
            isSelected: _showArchived,
            icon: const Icon(Icons.inventory_2_outlined),
            selectedIcon: const Icon(Icons.inventory_2),
            onPressed: () {
              setState(() => _showArchived = !_showArchived);
              _load();
            },
          ),
        ],
      ),
      floatingActionButton: _plans.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _createPlan,
              icon: const Icon(Icons.add),
              label: Text(loc.runPlansNew),
            ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : loadFailed
          ? LoadErrorView(onRetry: _load)
          : _plans.isEmpty
          ? _buildEmpty(theme, loc)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: AppUi.screenPadding.copyWith(top: 8),
                children: [
                  Text(
                    loc.runPlansSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (pinned.isNotEmpty) ...[
                    AppSectionHeader(
                      loc.runPlansFollowingSection,
                      padding: const EdgeInsets.fromLTRB(4, 16, 0, 8),
                    ),
                    for (final plan in pinned)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: RunPlanFollowedCard(
                          plan: plan,
                          progress:
                              _progress[plan.id] ?? const RunPlanProgress(),
                          linkedToPlanning: _linkedToPlanning.contains(plan.id),
                          actions: _actionsFor(plan),
                          today: today,
                          next: plan.isActivated ? _next : null,
                          onStartNext: plan.isActivated && _next != null
                              ? _startNext
                              : null,
                        ),
                      ),
                  ],
                  if (others.isNotEmpty) ...[
                    if (pinned.isNotEmpty)
                      AppSectionHeader(
                        loc.runPlansOthersSection,
                        padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                      )
                    else
                      const SizedBox(height: 12),
                    for (final plan in others) _libraryCard(plan, today),
                  ],
                  if (archived.isNotEmpty) ...[
                    AppSectionHeader(
                      loc.runPlansArchivedSection,
                      padding: const EdgeInsets.fromLTRB(4, 12, 0, 8),
                    ),
                    for (final plan in archived) _libraryCard(plan, today),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _libraryCard(RunPlan plan, DateTime today) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: RunPlanLibraryCard(
      plan: plan,
      progress: _progress[plan.id] ?? const RunPlanProgress(),
      linkedToPlanning: _linkedToPlanning.contains(plan.id),
      actions: _actionsFor(plan),
      today: today,
    ),
  );

  Widget _buildEmpty(ThemeData theme, AppLocalizations loc) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.route_outlined,
            size: 80,
            color: theme.colorScheme.primary.withAlpha(80),
          ),
          const SizedBox(height: 24),
          Text(
            loc.runPlansEmptyTitle,
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            loc.runPlansEmptySubtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _createPlan,
            icon: const Icon(Icons.add),
            label: Text(loc.runPlansNew),
          ),
        ],
      ),
    ),
  );
}
