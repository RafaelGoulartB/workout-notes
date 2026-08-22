import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_detail_screen.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/run_plan_ui.dart';

/// The running counterpart of [RoutinesScreen]: a library of structured plans.
class RunPlansScreen extends StatefulWidget {
  const RunPlansScreen({super.key});

  @override
  State<RunPlansScreen> createState() => _RunPlansScreenState();
}

class _RunPlansScreenState extends State<RunPlansScreen> {
  final _repo = RunPlanRepository();
  List<RunPlan> _plans = const [];
  Map<String, RunPlanProgress> _progress = const {};

  /// Plans whose weeks are driven by a periodization phase. Those are shown as
  /// followed through the planning instead of offering their own activation.
  Set<String> _linkedToPlanning = const {};
  bool _loading = true;
  bool _showArchived = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final plans = await _repo.listPlans(
      includeArchived: _showArchived,
      hydrate: true,
    );
    final progress = <String, RunPlanProgress>{};
    final linked = <String>{};
    for (final plan in plans) {
      progress[plan.id] = await _repo.getPlanProgress(plan.id);
      if (await _repo.isLinkedToPeriodization(plan.id)) linked.add(plan.id);
    }
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _progress = progress;
      _linkedToPlanning = linked;
      _loading = false;
    });
  }

  /// Starts following [plan], confirming first when another plan is active —
  /// only one plan can drive "which run is due today".
  Future<void> _activate(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final current = await _repo.getActivatedPlan(hydrate: false);
    if (!mounted) return;
    if (current != null && current.id != plan.id) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.runPlanReplaceActiveTitle),
          content: Text(loc.runPlanReplaceActiveBody(current.name)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(loc.runPlanActivate),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final created = await _repo.activatePlan(plan.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.runPlanActivatedMessage(created))),
    );
    await _load();
  }

  Future<void> _deactivate(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    await _repo.deactivatePlan(plan.id);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.runPlanDeactivatedMessage)));
    await _load();
  }

  Future<void> _openPlan(RunPlan plan) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunPlanDetailScreen(planId: plan.id)),
    );
    if (mounted) _load();
  }

  Future<void> _createPlan() async {
    final loc = AppLocalizations.of(context)!;
    final template = await showModalBottomSheet<Object?>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _TemplateSheet(loc: loc),
    );
    if (template == null || !mounted) return;

    // A template already knows what it is called, so creating it is one tap.
    // Only a blank plan has to ask for a name.
    if (template is RunPlanTemplate) {
      final plan = await RunPlanTemplates.create(
        _repo,
        template,
        name: RunPlanUi.goalLabel(loc, template.goalKind),
      );
      if (!mounted) return;
      await _openPlan(plan);
      return;
    }

    final name = await _promptName('');
    if (name == null || !mounted) return;
    final plan = await _repo.createPlan(name: name);
    if (!mounted) return;
    await _openPlan(plan);
  }

  Future<String?> _promptName(String initial) {
    final loc = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runPlansNew),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: loc.runPlanName,
            hintText: loc.runPlanNameHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(ctx, value);
            },
            child: Text(loc.commonSave),
          ),
        ],
      ),
    );
  }

  Future<void> _duplicate(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    await _repo.duplicatePlan(plan.id, loc.runPlansDuplicateSuffix(plan.name));
    if (mounted) _load();
  }

  Future<void> _toggleArchive(RunPlan plan) async {
    await _repo.updatePlan(
      plan.id,
      status: plan.isArchived ? RunPlanStatus.active : RunPlanStatus.archived,
    );
    if (mounted) _load();
  }

  Future<void> _delete(RunPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.runPlansDeleteConfirm(plan.name)),
        content: Text(loc.runPlansDeleteContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.deletePlan(plan.id);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final active = _plans.where((plan) => !plan.isArchived).toList();
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
          ? _buildEmpty(theme, loc)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  Text(
                    loc.runPlansSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final plan in active) ...[
                    _PlanCard(
                      plan: plan,
                      progress: _progress[plan.id],
                      linkedToPlanning: _linkedToPlanning.contains(plan.id),
                      onTap: () => _openPlan(plan),
                      onDuplicate: () => _duplicate(plan),
                      onToggleArchive: () => _toggleArchive(plan),
                      onDelete: () => _delete(plan),
                      onActivate: () => _activate(plan),
                      onDeactivate: () => _deactivate(plan),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (archived.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      loc.runPlansArchivedSection.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final plan in archived) ...[
                      _PlanCard(
                        plan: plan,
                        progress: _progress[plan.id],
                        linkedToPlanning: _linkedToPlanning.contains(plan.id),
                        onTap: () => _openPlan(plan),
                        onDuplicate: () => _duplicate(plan),
                        onToggleArchive: () => _toggleArchive(plan),
                        onDelete: () => _delete(plan),
                        onActivate: () => _activate(plan),
                        onDeactivate: () => _deactivate(plan),
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ],
              ),
            ),
    );
  }

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

/// Template picker. Showing the shape of the first week (how many sessions, of
/// which kinds) is what makes "Base aeróbica" mean something before creating it.
class _TemplateSheet extends StatelessWidget {
  final AppLocalizations loc;

  const _TemplateSheet({required this.loc});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              loc.runPlansFromTemplate,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final option in RunPlanTemplates.all)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _TemplateCard(
                option: option,
                onTap: () => Navigator.pop(context, option),
              ),
            ),
          const SizedBox(height: 8),
          const Divider(height: 8),
          ListTile(
            leading: const Icon(Icons.edit_note),
            title: Text(loc.runPlansBlank),
            onTap: () => Navigator.pop(context, 'blank'),
          ),
        ],
      ),
    );
  }
}

class _TemplateCard extends StatelessWidget {
  final RunPlanTemplate option;
  final VoidCallback onTap;

  const _TemplateCard({required this.option, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final kinds = <String>{
      for (final session in option.week) RunPlanUi.kindLabel(loc, session.kind),
    };

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(90)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_outlined,
                  size: 20,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      RunPlanUi.goalLabel(loc, option.goalKind),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${loc.runPlanWeeksValue(option.weeks)} · '
                      '${loc.runPlanTemplateSessions(option.week.length)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (kinds.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        kinds.join(' · '),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress? progress;

  /// Driven by a periodization phase: the card says so and hides its own
  /// activation, which would fight the phase for the week mapping.
  final bool linkedToPlanning;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleArchive;
  final VoidCallback onDelete;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  const _PlanCard({
    required this.plan,
    required this.progress,
    required this.linkedToPlanning,
    required this.onTap,
    required this.onDuplicate,
    required this.onToggleArchive,
    required this.onDelete,
    required this.onActivate,
    required this.onDeactivate,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final scheme = theme.colorScheme;
    final subtitle = <String>[
      RunPlanUi.goalLabel(loc, plan.goalKind),
      loc.runPlanWeeksValue(plan.weeks),
      if (plan.raceDate != null)
        DateFormat('d MMM y', Intl.defaultLocale).format(plan.raceDate!),
    ].join(' · ');

    var total = 0.0;
    for (var week = 0; week < plan.weeks; week++) {
      total += plan.weeklyDistanceMeters(week);
    }
    final averageVolume = plan.weeks == 0 ? 0.0 : total / plan.weeks;
    final sessionsPerWeek = plan.weeks == 0
        ? 0
        : (plan.workouts.length / plan.weeks).round();
    final countdown = _raceCountdown(plan.raceDate);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withAlpha(90)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: plan.isArchived ? 0.6 : 1,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.route_outlined,
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            plan.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (plan.isArchived)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      )
                    else if (plan.isActivated || linkedToPlanning)
                      _FollowingBadge(
                        label: linkedToPlanning
                            ? loc.periodizationTitle.toUpperCase()
                            : loc.runPlanActiveBadge,
                        icon: linkedToPlanning
                            ? Icons.route_rounded
                            : Icons.play_circle_outline,
                      ),
                    PopupMenuButton<String>(
                      onSelected: (value) => switch (value) {
                        'activate' => onActivate(),
                        'deactivate' => onDeactivate(),
                        'duplicate' => onDuplicate(),
                        'archive' => onToggleArchive(),
                        'delete' => onDelete(),
                        _ => null,
                      },
                      itemBuilder: (ctx) => [
                        if (!plan.isArchived && !linkedToPlanning)
                          PopupMenuItem(
                            value: plan.isActivated
                                ? 'deactivate'
                                : 'activate',
                            child: Text(
                              plan.isActivated
                                  ? loc.runPlanDeactivate
                                  : loc.runPlanActivate,
                            ),
                          ),
                        PopupMenuItem(
                          value: 'duplicate',
                          child: Text(loc.runPlansDuplicate),
                        ),
                        PopupMenuItem(
                          value: 'archive',
                          child: Text(
                            plan.isArchived
                                ? loc.runPlansUnarchive
                                : loc.runPlansArchive,
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(loc.runPlansDelete),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          loc.runPlanWeeklyVolumeTitle.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                            letterSpacing: .8,
                          ),
                        ),
                      ),
                      Text(
                        loc.runPlanWeekSummary(
                          RunPlanUi.kmValue(averageVolume),
                          sessionsPerWeek,
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                if (total > 0) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: RunPlanVolumeBars(plan: plan, height: 26),
                  ),
                ],
                if (progress?.hasProgress == true ||
                    plan.isActivated ||
                    linkedToPlanning) ...[
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _PlanProgressRow(
                      plan: plan,
                      progress: progress ?? const RunPlanProgress(),
                      viaPlanning: linkedToPlanning,
                    ),
                  ),
                ],
                if (countdown != null) ...[
                  const SizedBox(height: 10),
                  _MiniStat(
                    icon: Icons.flag_outlined,
                    label: loc.runPlanRaceCountdown(countdown),
                    highlight: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Days from today to the race, or null when the race has passed / is unset.
  static int? _raceCountdown(DateTime? raceDate) {
    if (raceDate == null) return null;
    final now = DateTime.now();
    final days = DateTime(
      raceDate.year,
      raceDate.month,
      raceDate.day,
    ).difference(DateTime(now.year, now.month, now.day)).inDays;
    return days < 0 ? null : days;
  }
}

class _FollowingBadge extends StatelessWidget {
  final String label;
  final IconData icon;

  const _FollowingBadge({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.primary.withAlpha(30),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w900,
              fontSize: 10,
              letterSpacing: .6,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// Sessions ticked off against the plan's total, plus where in the plan the
/// user currently is. The week only shows for a plan with a real anchor —
/// either its own activation or a periodization phase.
class _PlanProgressRow extends StatelessWidget {
  final RunPlan plan;
  final RunPlanProgress progress;
  final bool viaPlanning;

  const _PlanProgressRow({
    required this.plan,
    required this.progress,
    required this.viaPlanning,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final week = plan.activeWeekIndexOn(DateTime.now());
    final detail = <String>[
      if (week != null) loc.runPlanCurrentWeek(week + 1, plan.weeks),
      if (viaPlanning && week == null) loc.runPlanActiveVia,
      if (progress.skippedSessions > 0)
        loc.runPlanSkippedCount(progress.skippedSessions),
    ].join('  ·  ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                loc.runPlanProgressTitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
            Text(
              loc.runPlanProgressValue(
                progress.completedSessions,
                progress.totalSessions,
              ),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress.fraction,
            minHeight: 6,
            color: scheme.primary,
            backgroundColor: scheme.primary.withAlpha(30),
          ),
        ),
        if (detail.isNotEmpty) ...[
          const SizedBox(height: 5),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool highlight;

  const _MiniStat({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(24),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
