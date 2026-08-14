import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

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
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final plans = await _repository.getPlans();
    if (mounted) {
      setState(() {
        _plans = plans;
        _loading = false;
      });
    }
  }

  Future<void> _create() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PeriodizationPlanFormScreen()),
    );
    if (changed == true) {
      await _load();
    }
  }

  Future<void> _showPlan(PeriodizationPlan plan) async {
    final phases = await _repository.getPhases(plan.id);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .75,
        maxChildSize: .94,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
          children: [
            Text(plan.name, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              '${DateFormat.yMMMd(Intl.defaultLocale).format(plan.startDate)} – ${DateFormat.yMMMd(Intl.defaultLocale).format(plan.endDate)}',
            ),
            if (plan.notes != null) ...[
              const SizedBox(height: 10),
              Text(plan.notes!),
            ],
            const SizedBox(height: 18),
            ...phases.map(
              (phase) => Card(
                child: ListTile(
                  leading: CircleAvatar(backgroundColor: Color(phase.color)),
                  title: Text(phase.name),
                  subtitle: Text('${phase.totalWeeks}w'),
                  trailing: const Icon(Icons.chevron_right),
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
                ),
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(loc.periodizationEditPlan),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: InputDecoration(
                    labelText: loc.periodizationPlanName,
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: loc.periodizationPlanNotes,
                    border: const OutlineInputBorder(),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.periodizationStartDate),
                  subtitle: Text(
                    DateFormat.yMMMd(Intl.defaultLocale).format(start),
                  ),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2020),
                      lastDate: end,
                    );
                    if (value != null) setDialogState(() => start = value);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(loc.periodizationEndDate),
                  subtitle: Text(
                    DateFormat.yMMMd(Intl.defaultLocale).format(end),
                  ),
                  onTap: () async {
                    final value = await showDatePicker(
                      context: context,
                      initialDate: end,
                      firstDate: start,
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                    );
                    if (value != null) setDialogState(() => end = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(loc.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(loc.commonSave),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
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
        title: Text(loc.periodizationDeletePlanTitle),
        content: Text(loc.commonActionCannotBeUndone),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
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
    return Scaffold(
      appBar: AppBar(title: Text(loc.periodizationHistory)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
              itemCount: _plans.length,
              itemBuilder: (context, index) {
                final plan = _plans[index];
                return Card(
                  child: ListTile(
                    onTap: () => _showPlan(plan),
                    leading: Icon(_statusIcon(plan.status)),
                    title: Text(plan.name),
                    subtitle: Text(
                      '${_statusLabel(loc, plan.status)} · ${DateFormat.yMd(Intl.defaultLocale).format(plan.startDate)} – ${DateFormat.yMd(Intl.defaultLocale).format(plan.endDate)}',
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            _edit(plan);
                          case 'activate':
                            _status(plan, PeriodizationPlanStatus.active);
                          case 'complete':
                            _status(plan, PeriodizationPlanStatus.completed);
                          case 'archive':
                            _status(plan, PeriodizationPlanStatus.archived);
                          case 'delete':
                            _delete(plan);
                        }
                      },
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
                          child: Text(loc.commonDelete),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: Text(loc.periodizationCreatePlan),
      ),
    );
  }

  String _statusLabel(AppLocalizations loc, PeriodizationPlanStatus status) =>
      switch (status) {
        PeriodizationPlanStatus.active => loc.periodizationActive,
        PeriodizationPlanStatus.completed => loc.periodizationCompleted,
        PeriodizationPlanStatus.archived => loc.periodizationArchived,
        _ => loc.periodizationDraft,
      };

  IconData _statusIcon(PeriodizationPlanStatus status) => switch (status) {
    PeriodizationPlanStatus.active => Icons.play_circle_outline,
    PeriodizationPlanStatus.completed => Icons.check_circle_outline,
    PeriodizationPlanStatus.archived => Icons.archive_outlined,
    _ => Icons.edit_note_outlined,
  };
}
