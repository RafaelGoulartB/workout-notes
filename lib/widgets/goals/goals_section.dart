import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/screens/workout/goal_detail_screen.dart';
import 'package:workout_notes/widgets/goals/goal_card.dart';
import 'package:workout_notes/widgets/goals/goal_form_sheet.dart';

/// Renders the goals grid with the "+" add button at the end.
class GoalsSection extends StatefulWidget {
  final DatabaseHelper db;
  final SettingsRepository settingsRepo;

  const GoalsSection({
    super.key,
    required this.db,
    required this.settingsRepo,
  });

  @override
  State<GoalsSection> createState() => _GoalsSectionState();
}

class _GoalsSectionState extends State<GoalsSection> {
  final GoalRepository _goalRepo = GoalRepository();
  List<Goal> _goals = [];
  final Map<String, GoalProgress> _progressByGoal = {};
  bool _isLoading = true;
  bool _isKm = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant GoalsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.db != widget.db) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _isKm = await widget.settingsRepo.getIsDistanceKm();
      final goals = await _goalRepo.getAll();
      final progressEntries = await Future.wait(
        goals.map((g) async {
          try {
            final p = await _goalRepo.getProgress(g);
            return MapEntry(g.id, p);
          } catch (_) {
            return MapEntry(g.id, GoalProgress.empty(DateTime.now()));
          }
        }),
      );
      if (!mounted) return;
      setState(() {
        _goals = goals;
        _progressByGoal
          ..clear()
          ..addEntries(progressEntries);
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addGoal() async {
    final saved = await GoalFormSheet.show(context, widget.settingsRepo);
    if (saved == null) return;
    try {
      await _goalRepo.insert(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.goalSaved)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commonError(e.toString()))),
      );
    }
  }

  Future<void> _editGoal(Goal goal) async {
    final saved = await GoalFormSheet.show(context, widget.settingsRepo, existing: goal);
    if (saved == null) return;
    try {
      await _goalRepo.update(saved);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.goalSaved)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commonError(e.toString()))),
      );
    }
  }

  Future<void> _togglePause(Goal goal) async {
    await _goalRepo.toggleActive(goal.id, !goal.isActive);
    await _load();
  }

  Future<void> _deleteGoal(Goal goal) async {
    final loc = AppLocalizations.of(context)!;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(loc.goalDeleteConfirm),
        content: Text(loc.goalDeleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(loc.commonCancel),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(foregroundColor: Colors.red),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _goalRepo.delete(goal.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.goalDeleted)),
    );
    await _load();
  }

  void _openDetail(Goal goal) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GoalDetailScreen(goal: goal, db: widget.db),
    )).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_goals.isEmpty) {
      return _buildEmpty(theme, loc);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.4,
          ),
          itemCount: _goals.length,
          itemBuilder: (context, i) {
            final goal = _goals[i];
            final progress = _progressByGoal[goal.id] ?? GoalProgress.empty(DateTime.now());
            return GoalCard(
              goal: goal,
              progress: progress,
              isKm: _isKm,
              onTap: () => _openDetail(goal),
              onEdit: () => _editGoal(goal),
              onTogglePause: () => _togglePause(goal),
              onDelete: () => _deleteGoal(goal),
            );
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: TextButton.icon(
            onPressed: _addGoal,
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.goalGridAdd),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withAlpha(60),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.flag_outlined,
              size: 40,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            loc.goalEmpty,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            loc.goalEmptySubtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _addGoal,
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.goalGridAdd),
          ),
        ],
      ),
    );
  }
}
