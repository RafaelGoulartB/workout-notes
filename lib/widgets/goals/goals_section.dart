import 'package:flutter/material.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';
import 'package:workout_notes/screens/workout/goal_detail_screen.dart';
import 'package:workout_notes/widgets/goals/goal_card.dart';
import 'package:workout_notes/widgets/goals/goal_form_sheet.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Goals card: one divided row per goal and an add row at the end.
class GoalsSection extends StatefulWidget {
  final DatabaseHelper db;
  final SettingsRepository settingsRepo;

  /// When set, only goals in these scopes are listed and the create/edit
  /// sheet is restricted to the same scopes.
  final List<GoalScope> allowedScopes;

  /// Reports how many of the listed goals are already complete, so the host
  /// screen can show a summary next to its section header.
  final void Function(int achieved, int total)? onSummaryChanged;

  /// Wraps the list in its own card; turn off when the host already is one.
  final bool framed;

  const GoalsSection({
    super.key,
    required this.db,
    required this.settingsRepo,
    this.allowedScopes = const [GoalScope.anaerobic, GoalScope.aerobic],
    this.onSummaryChanged,
    this.framed = true,
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
      widget.onSummaryChanged?.call(
        progressEntries.where((e) => e.value.isComplete).length,
        goals.length,
      );
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
          content: Text(
            AppLocalizations.of(context)!.commonError(e.toString()),
          ),
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
          content: Text(
            AppLocalizations.of(context)!.commonError(e.toString()),
          ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.goalDeleted)));
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

    final colors = theme.colorScheme;
    final addRow = InkWell(
      onTap: _addGoal,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Icon(Icons.add_rounded, size: 22, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Text(
              loc.goalGridAdd,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );

    final list = _goals.isEmpty
        ? _buildEmpty(theme, loc)
        : RunDividedList(
            children: [
              for (final goal in _goals)
                GoalCard(
                  goal: goal,
                  progress:
                      _progressByGoal[goal.id] ??
                      GoalProgress.empty(DateTime.now()),
                  isKm: _isKm,
                  onTap: () => _openDetail(goal),
                  onEdit: () => _editGoal(goal),
                  onTogglePause: () => _togglePause(goal),
                  onDelete: () => _deleteGoal(goal),
                ),
              addRow,
            ],
          );

    if (!widget.framed) return list;
    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: list,
    );
  }

  Widget _buildEmpty(ThemeData theme, AppLocalizations loc) {
    final colors = theme.colorScheme;
    return InkWell(
      onTap: _addGoal,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Row(
          children: [
            const RunIconBadge(Icons.flag_outlined, size: 44, iconSize: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.goalEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    loc.goalEmptyRowSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: _addGoal,
              tooltip: loc.goalGridAdd,
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
