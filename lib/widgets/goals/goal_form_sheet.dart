import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';
import 'package:workout_notes/repositories/goal_repository.dart';
import 'package:workout_notes/repositories/settings_repository.dart';

/// Bottom sheet for creating or editing a user goal.
/// Multi-step flow: scope → metric → period+target.
class GoalFormSheet extends StatefulWidget {
  final Goal? existing; // null = create, non-null = edit
  final SettingsRepository settingsRepo;

  /// Scopes the user may pick. When a single scope is allowed, the
  /// scope step is hidden and that scope is forced.
  final List<GoalScope> allowedScopes;

  const GoalFormSheet({
    super.key,
    this.existing,
    required this.settingsRepo,
    this.allowedScopes = const [GoalScope.anaerobic, GoalScope.aerobic],
  });

  /// Convenience: shows the sheet and returns the saved goal (or null on cancel).
  static Future<Goal?> show(
    BuildContext context,
    SettingsRepository settingsRepo, {
    Goal? existing,
    List<GoalScope> allowedScopes = const [
      GoalScope.anaerobic,
      GoalScope.aerobic,
    ],
  }) {
    return showModalBottomSheet<Goal>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => GoalFormSheet(
        existing: existing,
        settingsRepo: settingsRepo,
        allowedScopes: allowedScopes,
      ),
    );
  }

  @override
  State<GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<GoalFormSheet> {
  late GoalScope _scope;
  late GoalMetric _metric;
  late GoalPeriod _period;
  late TextEditingController _titleController;
  late TextEditingController _valueController;
  double? _suggestedTarget;
  bool _isLoadingSuggestion = false;

  List<GoalScope> get _scopes {
    final scopes = widget.allowedScopes;
    if (scopes.isEmpty) return const [GoalScope.anaerobic];
    return scopes;
  }

  bool get _showScopeSelector => _scopes.length > 1;

  @override
  void initState() {
    super.initState();
    final g = widget.existing;
    final defaultScope = _scopes.first;
    final existingScope = g?.scope;
    _scope = (existingScope != null && _scopes.contains(existingScope))
        ? existingScope
        : defaultScope;
    final validMetrics = GoalMetric.forScope(_scope);
    final preferred = g?.metric ?? GoalMetric.volume;
    _metric = validMetrics.contains(preferred) ? preferred : validMetrics.first;
    _period = g?.period ?? GoalPeriod.weekly;
    _titleController = TextEditingController(text: g?.title ?? '');
    _valueController = TextEditingController(
      text: g != null ? _formatNumber(g.targetValue) : '',
    );
    if (g == null) {
      _loadSuggestion();
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  String _formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  Future<void> _loadSuggestion() async {
    setState(() => _isLoadingSuggestion = true);
    try {
      final repo = GoalRepository();
      // The unit toggle (km/mi) is irrelevant for the suggestion because the
      // user will re-enter their preferred unit.
      final s = await repo.suggestTarget(_scope, _metric, _period);
      if (mounted) {
        setState(() {
          _suggestedTarget = s;
          _isLoadingSuggestion = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingSuggestion = false);
    }
  }

  void _applySuggested() {
    if (_suggestedTarget == null) return;
    _valueController.text = _formatNumber(_suggestedTarget!);
  }

  void _save() {
    final value = double.tryParse(_valueController.text.replaceAll(',', '.'));
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.commonError('valor inválido'))),
      );
      return;
    }
    final id = widget.existing?.id ?? const Uuid().v4();
    final goal = Goal(
      id: id,
      title: _titleController.text.trim(),
      scope: _scope,
      metric: _metric,
      period: _period,
      targetValue: value,
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      isActive: widget.existing?.isActive ?? true,
      color: widget.existing?.color,
    );
    Navigator.of(context).pop(goal);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final mediaQuery = MediaQuery.of(context);
    final isEdit = widget.existing != null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                isEdit ? loc.goalEditTitle : loc.goalCreateTitle,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_showScopeSelector) ...[
                const SizedBox(height: 16),
                _buildScopeSelector(loc),
              ],
              const SizedBox(height: 16),
              _buildMetricSelector(loc),
              const SizedBox(height: 16),
              _buildPeriodSelector(loc),
              const SizedBox(height: 16),
              _buildTitleField(loc),
              const SizedBox(height: 12),
              _buildValueField(loc),
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(loc.commonCancel),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(loc.commonSave),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScopeSelector(AppLocalizations loc) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.goalStep1,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < _scopes.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _scopeOption(
                  label: _scopes[i] == GoalScope.aerobic
                      ? loc.goalScopeAerobic
                      : loc.goalScopeAnaerobic,
                  icon: _scopes[i] == GoalScope.aerobic
                      ? Icons.directions_run
                      : Icons.fitness_center,
                  color: _scopes[i] == GoalScope.aerobic
                      ? const Color(0xFFE53935)
                      : theme.colorScheme.primary,
                  value: _scopes[i],
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _scopeOption({
    required String label,
    required IconData icon,
    required Color color,
    required GoalScope value,
  }) {
    final theme = Theme.of(context);
    final isSelected = _scope == value;
    return InkWell(
      onTap: () {
        setState(() {
          _scope = value;
          // Reset metric to a valid one for the new scope
          final valid = GoalMetric.forScope(_scope);
          if (!valid.contains(_metric)) {
            _metric = valid.first;
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? color.withAlpha(40) : theme.colorScheme.surfaceContainerHighest.withAlpha(60),
          border: Border.all(
            color: isSelected ? color : theme.colorScheme.outlineVariant.withAlpha(60),
            width: isSelected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(icon, color: isSelected ? color : theme.colorScheme.onSurfaceVariant, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? color : theme.colorScheme.onSurface,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricSelector(AppLocalizations loc) {
    final theme = Theme.of(context);
    final valid = GoalMetric.forScope(_scope);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.goalStep2,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: valid.map((m) {
            final isSelected = _metric == m;
            return ChoiceChip(
              label: Text(_metricLabel(loc, m)),
              selected: isSelected,
              onSelected: (_) => setState(() => _metric = m),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _metricLabel(AppLocalizations loc, GoalMetric m) {
    switch (m) {
      case GoalMetric.volume:
        return loc.goalMetricVolume;
      case GoalMetric.days:
        return loc.goalMetricDays;
      case GoalMetric.distance:
        return loc.goalMetricDistance;
      case GoalMetric.time:
        return loc.goalMetricTime;
    }
  }

  Widget _buildPeriodSelector(AppLocalizations loc) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.goalChoosePeriod,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        SegmentedButton<GoalPeriod>(
          segments: [
            ButtonSegment(
              value: GoalPeriod.weekly,
              label: Text(loc.goalPeriodWeekly),
              icon: const Icon(Icons.calendar_view_week, size: 16),
            ),
            ButtonSegment(
              value: GoalPeriod.monthly,
              label: Text(loc.goalPeriodMonthly),
              icon: const Icon(Icons.calendar_month, size: 16),
            ),
          ],
          selected: {_period},
          onSelectionChanged: (s) => setState(() => _period = s.first),
        ),
      ],
    );
  }

  Widget _buildTitleField(AppLocalizations loc) {
    return TextField(
      controller: _titleController,
      decoration: InputDecoration(
        labelText: loc.goalLabelTitle,
        hintText: loc.goalTitleHint,
        border: const OutlineInputBorder(),
        prefixIcon: const Icon(Icons.title, size: 20),
      ),
    );
  }

  Widget _buildValueField(AppLocalizations loc) {
    final theme = Theme.of(context);
    final unitLabel = _unitLabel(loc);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _valueController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: loc.goalTargetValue,
            hintText: loc.goalTargetHint,
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.flag, size: 20),
            suffixText: unitLabel,
          ),
        ),
        if (_isLoadingSuggestion)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
                const SizedBox(width: 8),
                Text(
                  loc.goalSuggestedTarget('...'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontStyle: FontStyle.italic,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          )
        else if (_suggestedTarget != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: InkWell(
              onTap: _applySuggested,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome,
                        size: 14, color: theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Text(
                      loc.goalSuggestedTarget(
                        '${_formatNumber(_suggestedTarget!)} $unitLabel',
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _unitLabel(AppLocalizations loc) {
    switch (_metric) {
      case GoalMetric.volume:
        return 'kg';
      case GoalMetric.days:
        return loc.goalMetricDays.toLowerCase();
      case GoalMetric.distance:
        return 'km';
      case GoalMetric.time:
        return 'min';
    }
  }
}
