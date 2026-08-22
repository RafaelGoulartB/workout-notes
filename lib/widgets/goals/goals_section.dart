import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/screens/workout/goal_detail_screen.dart';
import 'package:workout_notes/widgets/goals/goal_card.dart';
import 'package:workout_notes/widgets/goals/goal_form_sheet.dart';

/// Renders goals as a vertical list with an add action.
class GoalsSection extends StatefulWidget {
  final DatabaseHelper db;
  final SettingsRepository settingsRepo;

  /// When set, only goals in these scopes are listed and the create/edit
  /// sheet is restricted to the same scopes.
  final List<GoalScope> allowedScopes;

  const GoalsSection({
    super.key,
    required this.db,
    required this.settingsRepo,
    this.allowedScopes = const [GoalScope.anaerobic, GoalScope.aerobic],
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
    if (oldWidget.db != widget.db ||
        !_sameScopes(oldWidget.allowedScopes, widget.allowedScopes)) {
      _load();
    }
  }

  bool _sameScopes(List<GoalScope> a, List<GoalScope> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _isKm = await widget.settingsRepo.getIsDistanceKm();
      final goals = (await _goalRepo.getAll())
          .where((g) => widget.allowedScopes.contains(g.scope))
          .toList();
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
    final saved = await GoalFormSheet.show(
      context,
      widget.settingsRepo,
      allowedScopes: widget.allowedScopes,
    );
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
        SnackBar(
          content: Text(AppLocalizations.of(context)!.commonError(e.toString())),
        ),
      );
    }
  }

  Future<void> _editGoal(Goal goal) async {
    final saved = await GoalFormSheet.show(
      context,
      widget.settingsRepo,
      existing: goal,
      allowedScopes: widget.allowedScopes,
    );
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
        SnackBar(
          content: Text(AppLocalizations.of(context)!.commonError(e.toString())),
        ),
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
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => GoalDetailScreen(goal: goal, db: widget.db),
          ),
        )
        .then((_) => _load());
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _goals.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          GoalCard(
            goal: _goals[i],
            progress: _progressByGoal[_goals[i].id] ??
                GoalProgress.empty(DateTime.now()),
            isKm: _isKm,
            onTap: () => _openDetail(_goals[i]),
            onEdit: () => _editGoal(_goals[i]),
            onTogglePause: () => _togglePause(_goals[i]),
            onDelete: () => _deleteGoal(_goals[i]),
          ),
        ],
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addGoal,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.goalGridAdd),
          ),
        ),
      ],
    );
  }

  Widget _buildEmpty(ThemeData theme, AppLocalizations loc) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withAlpha(80),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withAlpha(28),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.flag_outlined,
              size: 28,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            loc.goalEmpty,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
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
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: _addGoal,
            icon: const Icon(Icons.add, size: 18),
            label: Text(loc.goalGridAdd),
          ),
        ],
      ),
    );
  }
}
