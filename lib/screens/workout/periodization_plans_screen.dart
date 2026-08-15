import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/widgets/periodization/periodization_ui.dart';

import 'periodization_phase_detail_screen.dart';
import 'periodization_plan_form_screen.dart';

class PeriodizationPlansScreen extends StatefulWidget {
  const PeriodizationPlansScreen({super.key});

  @override
  State<PeriodizationPlansScreen> createState() =>
      _PeriodizationPlansScreenState();
}

class _PeriodizationPlansScreenState extends State<PeriodizationPlansScreen> {
  final _repository = PeriodizationRepository();
  List<PeriodizationPlan> _plans = const [];
  Map<String, List<PeriodizationPhase>> _phasesByPlan = const {};
  PeriodizationPlanStatus? _filter;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await _repository.getPlans();
    final phaseEntries = await Future.wait(
      plans.map(
        (plan) async => MapEntry(plan.id, await _repository.getPhases(plan.id)),
      ),
    );
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _phasesByPlan = Map.fromEntries(phaseEntries);
      _loading = false;
    });
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlanFormScreen()),
    );
    if (changed == true) await _load();
  }

  Future<void> _showPlan(PeriodizationPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final phases = _phasesByPlan[plan.id] ?? const <PeriodizationPhase>[];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .82,
        minChildSize: .55,
        maxChildSize: .95,
        builder: (context, controller) => CustomScrollView(
          controller: controller,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        PeriodizationStatusPill(
                          label: _statusLabel(loc, plan.status),
                          icon: _statusIcon(plan.status),
                          color: _statusColor(context, plan.status),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: loc.periodizationEditPlan,
                          onPressed: () async {
                            Navigator.pop(sheetContext);
                            await _edit(plan);
                          },
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      plan.name,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat.yMMMd(Intl.defaultLocale).format(plan.startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(plan.endDate)}  ·  ${(plan.totalDays / 7).ceil()} sem.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (plan.notes != null &&
                        plan.notes!.trim().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        plan.notes!,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (phases.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      PeriodizationPhaseTimeline(
                        phases: phases,
                        referenceDate: DateTime.now(),
                        showLabels: false,
                      ),
                    ],
                    const SizedBox(height: 24),
                    PeriodizationSectionHeader(
                      title: loc.periodizationNextPhases,
                      icon: Icons.route_outlined,
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              sliver: phases.isEmpty
                  ? SliverToBoxAdapter(
                      child: Text(
                        loc.periodizationNoUpcoming,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : SliverList.separated(
                      itemCount: phases.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final phase = phases[index];
                        return PeriodizationSurface(
                          accentColor: Color(phase.color),
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          onTap: () async {
                            Navigator.pop(sheetContext);
                            await Navigator.push(
                              this.context,
                              MaterialPageRoute(
                                builder: (_) => PeriodizationPhaseDetailScreen(
                                  plan: plan,
                                  phase: phase,
                                ),
                              ),
                            );
                            await _load();
                          },
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 19,
                                backgroundColor: Color(
                                  phase.color,
                                ).withAlpha(28),
                                foregroundColor: Color(phase.color),
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      phase.name,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    Text(
                                      '${phase.totalWeeks} sem.  ·  ${DateFormat.MMMd(Intl.defaultLocale).format(phase.startDate)} – ${DateFormat.MMMd(Intl.defaultLocale).format(phase.endDate)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(PeriodizationPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final name = TextEditingController(text: plan.name);
    final notes = TextEditingController(text: plan.notes ?? '');
    var start = plan.startDate;
    var end = plan.endDate;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            4,
            20,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  loc.periodizationEditPlan,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: name,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: loc.periodizationPlanName,
                    prefixIcon: const Icon(Icons.edit_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: notes,
                  minLines: 2,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: loc.periodizationPlanNotes,
                    alignLabelWithHint: true,
                    prefixIcon: const Icon(Icons.notes_outlined),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _EditDateButton(
                        label: loc.periodizationStartDate,
                        value: start,
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: start,
                            firstDate: DateTime(2020),
                            lastDate: end,
                          );
                          if (value != null) setSheetState(() => start = value);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _EditDateButton(
                        label: loc.periodizationEndDate,
                        value: end,
                        onTap: () async {
                          final value = await showDatePicker(
                            context: context,
                            initialDate: end,
                            firstDate: start,
                            lastDate: DateTime.now().add(
                              const Duration(days: 3650),
                            ),
                          );
                          if (value != null) setSheetState(() => end = value);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton(
                  onPressed: name.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(sheetContext, true),
                  child: Text(loc.commonSave),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (saved != true) {
      name.dispose();
      notes.dispose();
      return;
    }
    try {
      await _repository.updatePlan(
        plan.copyWith(
          name: name.text,
          notes: notes.text,
          startDate: start,
          endDate: end,
        ),
      );
      await _load();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.periodizationSaveError('$error'))),
      );
    } finally {
      name.dispose();
      notes.dispose();
    }
  }

  Future<void> _status(
    PeriodizationPlan plan,
    PeriodizationPlanStatus status,
  ) async {
    await _repository.setPlanStatus(plan.id, status);
    await _load();
  }

  Future<void> _delete(PeriodizationPlan plan) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.delete_outline),
        title: Text(loc.periodizationDeletePlanTitle),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deletePlan(plan.id);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final filtered = _filter == null
        ? _plans
        : _plans.where((plan) => plan.status == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(
          loc.periodizationHistory,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            tooltip: loc.periodizationCreatePlan,
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _plans.isEmpty
          ? PeriodizationEmptyState(
              icon: Icons.folder_open_outlined,
              title: loc.periodizationNoActiveTitle,
              subtitle: loc.periodizationNoActiveSubtitle,
              primaryLabel: loc.periodizationCreatePlan,
              onPrimary: _create,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                      child: Row(
                        children: [
                          _FilterChip(
                            label: loc.commonAll,
                            selected: _filter == null,
                            onSelected: () => setState(() => _filter = null),
                          ),
                          const SizedBox(width: 8),
                          for (final status
                              in PeriodizationPlanStatus.values) ...[
                            _FilterChip(
                              label: _statusLabel(loc, status),
                              selected: _filter == status,
                              onSelected: () =>
                                  setState(() => _filter = status),
                            ),
                            const SizedBox(width: 8),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                    sliver: filtered.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 50),
                              child: Text(
                                loc.periodizationNoCompletedPlans,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          )
                        : SliverList.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final plan = filtered[index];
                              return _PlanCard(
                                    plan: plan,
                                    phases: _phasesByPlan[plan.id] ?? const [],
                                    statusLabel: _statusLabel(loc, plan.status),
                                    statusIcon: _statusIcon(plan.status),
                                    statusColor: _statusColor(
                                      context,
                                      plan.status,
                                    ),
                                    onTap: () => _showPlan(plan),
                                    onAction: (value) {
                                      switch (value) {
                                        case 'edit':
                                          _edit(plan);
                                        case 'activate':
                                          _status(
                                            plan,
                                            PeriodizationPlanStatus.active,
                                          );
                                        case 'complete':
                                          _status(
                                            plan,
                                            PeriodizationPlanStatus.completed,
                                          );
                                        case 'archive':
                                          _status(
                                            plan,
                                            PeriodizationPlanStatus.archived,
                                          );
                                        case 'delete':
                                          _delete(plan);
                                      }
                                    },
                                  )
                                  .animate()
                                  .fadeIn(
                                    duration: 220.ms,
                                    delay: (index * 35).ms,
                                  )
                                  .slideY(begin: .025);
                            },
                          ),
                  ),
                ],
              ),
            ),
      floatingActionButton: _plans.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text(loc.periodizationCreatePlan),
            ),
    );
  }

  String _statusLabel(AppLocalizations loc, PeriodizationPlanStatus status) =>
      switch (status) {
        PeriodizationPlanStatus.active => loc.periodizationActive,
        PeriodizationPlanStatus.completed => loc.periodizationCompleted,
        PeriodizationPlanStatus.archived => loc.periodizationArchived,
        PeriodizationPlanStatus.draft => loc.periodizationDraft,
      };

  IconData _statusIcon(PeriodizationPlanStatus status) => switch (status) {
    PeriodizationPlanStatus.active => Icons.play_arrow_rounded,
    PeriodizationPlanStatus.completed => Icons.check_rounded,
    PeriodizationPlanStatus.archived => Icons.archive_outlined,
    PeriodizationPlanStatus.draft => Icons.edit_note_outlined,
  };

  Color _statusColor(BuildContext context, PeriodizationPlanStatus status) {
    final scheme = Theme.of(context).colorScheme;
    return switch (status) {
      PeriodizationPlanStatus.active => scheme.primary,
      PeriodizationPlanStatus.completed => const Color(0xFF2E7D5B),
      PeriodizationPlanStatus.archived => scheme.onSurfaceVariant,
      PeriodizationPlanStatus.draft => scheme.tertiary,
    };
  }
}

class _PlanCard extends StatelessWidget {
  final PeriodizationPlan plan;
  final List<PeriodizationPhase> phases;
  final String statusLabel;
  final IconData statusIcon;
  final Color statusColor;
  final VoidCallback onTap;
  final ValueChanged<String> onAction;

  const _PlanCard({
    required this.plan,
    required this.phases,
    required this.statusLabel,
    required this.statusIcon,
    required this.statusColor,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return PeriodizationSurface(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              PeriodizationStatusPill(
                label: statusLabel,
                icon: statusIcon,
                color: statusColor,
              ),
              const Spacer(),
              PopupMenuButton<String>(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                onSelected: onAction,
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Text(loc.periodizationEditPlan),
                  ),
                  if (plan.status != PeriodizationPlanStatus.active)
                    PopupMenuItem(
                      value: 'activate',
                      child: Text(loc.periodizationActivate),
                    ),
                  if (plan.status == PeriodizationPlanStatus.active)
                    PopupMenuItem(
                      value: 'complete',
                      child: Text(loc.periodizationComplete),
                    ),
                  if (plan.status != PeriodizationPlanStatus.archived)
                    PopupMenuItem(
                      value: 'archive',
                      child: Text(loc.periodizationArchive),
                    ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(
                      loc.commonDelete,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            plan.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${DateFormat.yMMMd(Intl.defaultLocale).format(plan.startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(plan.endDate)}  ·  ${(plan.totalDays / 7).ceil()} sem.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (phases.isNotEmpty) ...[
            const SizedBox(height: 16),
            PeriodizationPhaseTimeline(
              phases: phases,
              referenceDate: DateTime.now(),
              showLabels: false,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                Icons.layers_outlined,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Text(
                '${phases.length} ${loc.periodizationNextPhases.toLowerCase()}',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FilterChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onSelected(),
    showCheckmark: false,
    visualDensity: VisualDensity.compact,
  );
}

class _EditDateButton extends StatelessWidget {
  final String label;
  final DateTime value;
  final VoidCallback onTap;

  const _EditDateButton({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: Alignment.centerLeft,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(DateFormat.yMMMd(Intl.defaultLocale).format(value)),
      ],
    ),
  );
}
