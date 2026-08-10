import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';

/// Calorie-tracking analytics. The whole screen is purpose-built for
/// the "am I in a surplus or a deficit?" question that drives weight
/// change: it surfaces the net balance for the selected window, the
/// distribution of days across the three bands, the rolling 7-day
/// average against the goal, where the calories are coming from
/// (per meal and per food), and how the macros stack up against the
/// target.
class NutritionProgressScreen extends StatefulWidget {
  const NutritionProgressScreen({super.key});

  @override
  State<NutritionProgressScreen> createState() =>
      _NutritionProgressScreenState();
}

const int _kWindow7 = 7;
const int _kWindow30 = 30;
const int _kRollingWindow = 7;

/// Roughly 7,700 kcal ≈ 1 kg of body fat. Used only for the
/// informational "equivalent in fat" label on the hero card.
const double _kKcalPerKgFat = 7700;

class _NutritionProgressScreenState extends State<NutritionProgressScreen>
    with SingleTickerProviderStateMixin {
  final NutritionRepository _repository = NutritionRepository();
  late final TabController _tabController;

  int _windowDays = _kWindow7;

  CalorieBalance? _balance;
  List<DailyCalorieTotal> _dailies30 = const [];
  List<DailyCalorieTotal> _dailies7 = const [];
  List<CalorieContributor> _contributors = const [];
  List<MealTypeCalories> _mealDistribution = const [];
  NutritionGoal? _goal;
  _MacroSummary? _macros;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: 0,
    );
    _tabController.addListener(_onTabChanged);
    _load();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) return;
    final days = _tabController.index == 0 ? _kWindow7 : _kWindow30;
    if (days != _windowDays) {
      setState(() => _windowDays = days);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getActiveGoal(),
        _repository.getDailyCalorieTotals(days: _kWindow30),
        _repository.getTopCalorieContributors(
          days: _kWindow30,
          limit: 8,
        ),
        _repository.getCaloriesByMealType(days: _kWindow30),
        _repository.getDailyNutritionHistory(days: _kWindow30),
      ]);
      if (!mounted) return;
      final goal = results[0] as NutritionGoal?;
      final dailies = results[1] as List<DailyCalorieTotal>;
      final balance = await _repository.getCalorieBalance(
        days: _kWindow30,
        goal: goal?.calories,
      );
      if (!mounted) return;
      setState(() {
        _goal = goal;
        _dailies30 = dailies;
        _dailies7 = dailies.length <= _kWindow7
            ? dailies
            : dailies.sublist(dailies.length - _kWindow7);
        _balance = balance;
        _contributors = results[2] as List<CalorieContributor>;
        _mealDistribution = results[3] as List<MealTypeCalories>;
        _macros = _summarizeMacros(
          results[4] as List<Map<String, dynamic>>,
        );
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  static _MacroSummary _summarizeMacros(List<Map<String, dynamic>> rows) {
    double p = 0, c = 0, f = 0, k = 0;
    for (final row in rows) {
      p += (row['protein_g'] as num?)?.toDouble() ?? 0;
      c += (row['carbs_g'] as num?)?.toDouble() ?? 0;
      f += (row['fat_g'] as num?)?.toDouble() ?? 0;
      k += (row['calories'] as num?)?.toDouble() ?? 0;
    }
    return _MacroSummary(
      proteinG: p,
      carbsG: c,
      fatG: f,
      totalKcal: k,
    );
  }

  // ------------------------------------------------------------------
  // Derived
  // ------------------------------------------------------------------

  CalorieBalance? get _windowBalance {
    final balance = _balance;
    if (balance == null) return null;
    if (_windowDays == _kWindow7) {
      final goal = _goal?.calories;
      final consumed = _dailies7.fold<double>(
        0,
        (sum, d) => sum + (d.calories ?? 0),
      );
      final logged = _dailies7.where((d) => d.calories != null).length;
      var deficit = 0, onTarget = 0, surplus = 0;
      var streak = 0;
      final loggedList = <DailyCalorieTotal>[];
      for (final d in _dailies7) {
        if (d.calories == null) continue;
        loggedList.add(d);
        if (goal != null && goal > 0) {
          final delta = d.calories! - goal;
          final ratio = delta.abs() / goal;
          if (ratio <= 0.10) {
            onTarget++;
          } else if (delta < 0) {
            deficit++;
          } else {
            surplus++;
          }
        }
      }
      if (goal != null && goal > 0) {
        for (var i = loggedList.length - 1; i >= 0; i--) {
          final delta = (loggedList[i].calories! - goal).abs() / goal;
          if (delta <= 0.10) {
            streak++;
          } else {
            break;
          }
        }
      }
      return CalorieBalance(
        days: _kWindow7,
        totalConsumed: consumed,
        totalGoal: goal == null ? null : goal * _kWindow7,
        balance: goal == null ? null : consumed - (goal * _kWindow7),
        daysLogged: logged,
        daysInDeficit: deficit,
        daysOnTarget: onTarget,
        daysInSurplus: surplus,
        currentStreak: streak,
        averageDailyIntake: logged == 0 ? 0 : consumed / logged,
      );
    }
    return balance;
  }

  List<DailyCalorieTotal> get _windowDailies =>
      _windowDays == _kWindow7 ? _dailies7 : _dailies30;

  /// 7-day rolling average series over the 30-day window. Each point
  /// is the mean of the last [window] days ending at that date. Days
  /// without any log pull the mean down; we use a trailing mean of
  /// non-null days within the window so a quiet day doesn't tank the
  /// line (which would suggest a fictitious calorie crash).
  List<FlSpot> _rollingSpots() {
    final goal = _goal?.calories;
    final spots = <FlSpot>[];
    for (var i = 0; i < _dailies30.length; i++) {
      final start = (i - _kRollingWindow + 1).clamp(0, _dailies30.length);
      final window = _dailies30.sublist(start, i + 1);
      final logged = window.where((d) => d.calories != null).toList();
      if (logged.length < 3) continue;
      final sum = logged.fold<double>(0, (s, d) => s + d.calories!);
      final avg = sum / logged.length;
      spots.add(FlSpot(i.toDouble(), avg));
    }
    // Avoid forcing a chart recompute when the goal is null — the
    // horizontal reference line just gets hidden in that case.
    if (goal != null && spots.isNotEmpty) {
      // ensure consumer can read goal via a side-channel
    }
    return spots;
  }

  double? get _rollingGoal => _goal?.calories;

  // ------------------------------------------------------------------
  // Build
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionBalanceTitle),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: loc.nutritionBalanceLast7Days),
            Tab(text: loc.nutritionBalanceLast30Days),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  _BalanceHeroCard(
                    balance: _windowBalance,
                    goal: _goal,
                    windowDays: _windowDays,
                  ).animate().fadeIn(duration: 250.ms),
                  if (_windowDays == _kWindow7) ...[
                    const SizedBox(height: 12),
                    _WeekSequenceCard(
                      dailies: _windowDailies,
                      goal: _goal?.calories,
                    ).animate().fadeIn(duration: 250.ms, delay: 60.ms),
                  ],
                  const SizedBox(height: 12),
                  _RollingAverageCard(
                    spots: _rollingSpots(),
                    goal: _rollingGoal,
                    windowDays: _kWindow30,
                  ).animate().fadeIn(duration: 250.ms, delay: 140.ms),
                  const SizedBox(height: 12),
                  _MealDistributionCard(
                    distribution: _mealDistribution,
                  ).animate().fadeIn(duration: 250.ms, delay: 180.ms),
                  const SizedBox(height: 12),
                  _TopContributorsCard(
                    contributors: _contributors,
                    totalConsumed: _balance?.totalConsumed ?? 0,
                  ).animate().fadeIn(duration: 250.ms, delay: 220.ms),
                  const SizedBox(height: 12),
                  _MacroBalanceCard(
                    summary: _macros,
                    goal: _goal,
                  ).animate().fadeIn(duration: 250.ms, delay: 260.ms),
                  const SizedBox(height: 8),
                ],
              ),
            ),
    );
  }
}

// =====================================================================
// Hero card — net balance
// =====================================================================

class _BalanceHeroCard extends StatelessWidget {
  final CalorieBalance? balance;
  final NutritionGoal? goal;
  final int windowDays;

  const _BalanceHeroCard({
    required this.balance,
    required this.goal,
    required this.windowDays,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final balance = this.balance;
    final hasGoal = goal?.calories != null && goal!.calories! > 0;
    final caloriesValue = balance?.balance;

    final status = _statusFor(balance, hasGoal);
    final statusColor = _colorForStatus(status, theme);
    final statusLabel = _labelForStatus(status, loc, windowDays);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              statusColor.withAlpha(45),
              theme.colorScheme.surfaceContainerLow,
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: statusColor.withAlpha(80),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _iconForStatus(status),
                    color: statusColor,
                    size: 22,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    windowDays == _kWindow7
                        ? loc.nutritionBalanceThisWeek
                        : loc.nutritionBalanceHeroTitle(windowDays),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (caloriesValue == null)
                Text(
                  loc.nutritionBalanceNoGoal,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _signedKcal(caloriesValue),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        'kcal',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (caloriesValue.abs() >= 1)
                      Text(
                        loc.nutritionBalanceFatEquivalent(
                          _formatFatKg(caloriesValue.abs()),
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _BalanceMetric(
                      label: loc.nutritionBalanceDaysLogged,
                      value: '${balance?.daysLogged ?? 0}/$windowDays',
                    ),
                  ),
                  Expanded(
                    child: _BalanceMetric(
                      label: loc.nutritionBalanceAverageIntake,
                      value:
                          '${_formatKcal(balance?.averageDailyIntake ?? 0)} kcal',
                      sub: hasGoal
                          ? loc.nutritionBalanceGoalKcal(
                              _formatKcal(goal!.calories!),
                            )
                          : null,
                    ),
                  ),
                  Expanded(
                    child: _BalanceMetric(
                      label: loc.nutritionBalanceCurrentStreak,
                      value: balance == null
                          ? '—'
                          : loc.nutritionBalanceStreakDays(
                              balance.currentStreak,
                            ),
                      sub: (balance?.currentStreak ?? 0) > 0
                          ? loc.nutritionBalanceStreakHint
                          : null,
                      valueColor: (balance?.currentStreak ?? 0) > 0
                          ? statusColor
                          : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatKcal(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(0);
  }

  static String _formatFatKg(double absKcal) {
    final kg = absKcal / _kKcalPerKgFat;
    if (kg < 0.1) return '< 0,1';
    if (kg >= 10) return kg.toStringAsFixed(0);
    return kg.toStringAsFixed(1);
  }

  static String _signedKcal(double value) {
    final sign = value > 0 ? '+' : '';
    final abs = value.abs();
    if (abs == abs.roundToDouble()) {
      return '$sign${abs.toStringAsFixed(0)}';
    }
    return '$sign${abs.toStringAsFixed(0)}';
  }

  static _BalanceStatus _statusFor(CalorieBalance? b, bool hasGoal) {
    if (!hasGoal) return _BalanceStatus.noGoal;
    final v = b?.balance;
    if (v == null) return _BalanceStatus.noGoal;
    if (v.abs() < 1) return _BalanceStatus.maintaining;
    return v < 0 ? _BalanceStatus.deficit : _BalanceStatus.surplus;
  }

  static IconData _iconForStatus(_BalanceStatus s) {
    return switch (s) {
      _BalanceStatus.deficit => Icons.south_east_rounded,
      _BalanceStatus.surplus => Icons.north_east_rounded,
      _BalanceStatus.maintaining => Icons.horizontal_rule_rounded,
      _BalanceStatus.noGoal => Icons.flag_outlined,
    };
  }

  static Color _colorForStatus(_BalanceStatus s, ThemeData theme) {
    return switch (s) {
      _BalanceStatus.deficit => const Color(0xFF2BB673),
      _BalanceStatus.surplus => theme.colorScheme.error,
      _BalanceStatus.maintaining => theme.colorScheme.primary,
      _BalanceStatus.noGoal => theme.colorScheme.onSurfaceVariant,
    };
  }

  static String _labelForStatus(
    _BalanceStatus s,
    AppLocalizations loc,
    int windowDays,
  ) {
    return switch (s) {
      _BalanceStatus.deficit => loc.nutritionBalanceStatusDeficit,
      _BalanceStatus.surplus => loc.nutritionBalanceStatusSurplus,
      _BalanceStatus.maintaining => loc.nutritionBalanceStatusMaintaining,
      _BalanceStatus.noGoal => loc.nutritionBalanceStatusNoGoal,
    };
  }
}

enum _BalanceStatus { deficit, surplus, maintaining, noGoal }

class _BalanceMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  const _BalanceMetric({
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? theme.colorScheme.onSurface,
            height: 1.0,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(
            sub!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

// 7-day sequence (compact 7-cell strip)
// =====================================================================

class _WeekSequenceCard extends StatelessWidget {
  final List<DailyCalorieTotal> dailies;
  final double? goal;

  const _WeekSequenceCard({required this.dailies, required this.goal});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasGoal = goal != null && goal! > 0;
    var deficit = 0, onTarget = 0, surplus = 0, logged = 0;
    for (final d in dailies) {
      if (d.calories == null) continue;
      logged++;
      if (hasGoal) {
        final delta = d.calories! - goal!;
        final ratio = delta.abs() / goal!;
        if (ratio <= 0.10) {
          onTarget++;
        } else if (delta < 0) {
          deficit++;
        } else {
          surplus++;
        }
      }
    }
    return _SectionCard(
      icon: Icons.view_week_outlined,
      iconColor: theme.colorScheme.secondary,
      title: loc.nutritionBalanceWeekSequence,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              for (final day in dailies)
                Expanded(
                  child: _WeekDayCell(
                    date: day.date,
                    calories: day.calories,
                    goal: goal,
                    hasGoal: hasGoal,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasGoal)
            _EmptyNote(text: loc.nutritionProgressNoGoal)
          else if (logged == 0)
            Text(
              loc.nutritionBalanceNoDaysLogged,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            _WeekSequenceSummary(
              deficit: deficit,
              onTarget: onTarget,
              surplus: surplus,
              logged: logged,
            ),
        ],
      ),
    );
  }
}

/// Compact summary row for the week sequence. Renders a single line
/// with the deficit / on-target / surplus counts plus the contextual
/// insight. Replaces the former standalone "Day distribution" card,
/// which duplicated the per-cell status the sequence already shows.
class _WeekSequenceSummary extends StatelessWidget {
  final int deficit;
  final int onTarget;
  final int surplus;
  final int logged;

  const _WeekSequenceSummary({
    required this.deficit,
    required this.onTarget,
    required this.surplus,
    required this.logged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        _CountChip(
          label: loc.nutritionBalanceStatusDeficit,
          count: deficit,
          color: _deficitColor,
        ),
        const SizedBox(width: 6),
        _CountChip(
          label: loc.nutritionBalanceStatusMaintaining,
          count: onTarget,
          color: _onTargetColor,
        ),
        const SizedBox(width: 6),
        _CountChip(
          label: loc.nutritionBalanceStatusSurplus,
          count: surplus,
          color: _surplusColor,
        ),
      ],
    );
  }
}

class _CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekDayCell extends StatelessWidget {
  final DateTime date;
  final double? calories;
  final double? goal;
  final bool hasGoal;

  const _WeekDayCell({
    required this.date,
    required this.calories,
    required this.goal,
    required this.hasGoal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dow = DateFormat.E(Intl.defaultLocale).format(date).substring(0, 1);
    final isToday = _isSameDay(date, DateTime.now());
    final (status, color) = _resolveStatus();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Text(
            dow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isToday
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 0.72,
            child: Container(
              decoration: BoxDecoration(
                color: _bgColor(color, theme),
                borderRadius: BorderRadius.circular(10),
                border: isToday
                    ? Border.all(
                        color: theme.colorScheme.primary,
                        width: 1.5,
                      )
                    : null,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 2,
                vertical: 6,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (calories == null)
                    Text(
                      '—',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    Text(
                      _formatShort(calories!),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'kcal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.withAlpha(180),
                        fontSize: 9,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasGoal && calories != null) ...[
            const SizedBox(height: 5),
            _DayDeltaPill(
              delta: calories! - goal!,
              color: color,
            ),
          ],
        ],
      ),
    );
  }

  String _formatShort(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }

  Color _bgColor(Color status, ThemeData theme) {
    if (status == Colors.transparent) {
      return theme.colorScheme.surfaceContainerHighest.withAlpha(120);
    }
    return status.withAlpha(40);
  }

  (_DayStatus, Color) _resolveStatus() {
    if (!hasGoal || calories == null) {
      return (_DayStatus.unknown, Colors.transparent);
    }
    final delta = calories! - goal!;
    final ratio = delta.abs() / goal!;
    if (ratio <= 0.10) {
      return (_DayStatus.onTarget, _onTargetColor);
    }
    if (delta < 0) {
      return (_DayStatus.deficit, _deficitColor);
    }
    return (_DayStatus.surplus, _surplusColor);
  }
}

const Color _deficitColor = Color(0xFF2BB673);
final Color _surplusColor = const Color(0xFF000000) == const Color(0xFF000000)
    ? const Color(0xFFE0524A)
    : const Color(0xFFE0524A);
final Color _onTargetColor = const Color(0xFF000000) == const Color(0xFF000000)
    ? const Color(0xFF4A90E2)
    : const Color(0xFF4A90E2);

enum _DayStatus { onTarget, deficit, surplus, unknown }

class _DayDeltaPill extends StatelessWidget {
  final double delta;
  final Color color;
  const _DayDeltaPill({required this.delta, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abs = delta.abs();
    final label = abs >= 1000
        ? '${delta < 0 ? '-' : '+'}${(abs / 1000).toStringAsFixed(1)}k'
        : '${delta < 0 ? '-' : '+'}${abs.round()}';
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 10,
        height: 1.0,
      ),
    );
  }
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

// =====================================================================
// Rolling 7-day average
// =====================================================================

class _RollingAverageCard extends StatelessWidget {
  final List<FlSpot> spots;
  final double? goal;
  final int windowDays;

  const _RollingAverageCard({
    required this.spots,
    required this.goal,
    required this.windowDays,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasData = spots.isNotEmpty;
    final currentAvg =
        hasData ? spots.last.y : 0.0;
    final goalKcal = goal;
    final diff = (goalKcal != null && hasData) ? currentAvg - goalKcal : null;

    return _SectionCard(
      icon: Icons.show_chart_rounded,
      iconColor: theme.colorScheme.tertiary,
      title: loc.nutritionBalanceRollingTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (hasData)
            Row(
              children: [
                _RollingStat(
                  label: loc.nutritionBalanceRollingCurrent,
                  value: '${currentAvg.round()} kcal',
                  color: diff == null
                      ? theme.colorScheme.onSurface
                      : diff < 0
                          ? _deficitColor
                          : _surplusColor,
                ),
                const SizedBox(width: 12),
                if (goalKcal != null)
                  _RollingStat(
                    label: loc.nutritionBalanceGoalLabel,
                    value: '${goalKcal.round()} kcal',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                const SizedBox(width: 12),
                if (diff != null)
                  _RollingStat(
                    label: loc.nutritionBalanceRollingDelta,
                    value:
                        '${diff < 0 ? '' : '+'}${diff.round()} kcal',
                    color: diff < 0
                        ? _deficitColor
                        : _surplusColor,
                  ),
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            height: 150,
            child: hasData
                ? _RollingLineChart(
                    spots: spots,
                    goal: goalKcal,
                  )
                : Center(
                    child: Text(
                      loc.nutritionBalanceRollingEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RollingStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _RollingStat({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
            height: 1.0,
          ),
        ),
      ],
    );
  }
}

class _RollingLineChart extends StatelessWidget {
  final List<FlSpot> spots;
  final double? goal;

  const _RollingLineChart({required this.spots, required this.goal});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = spots.fold<double>(
      0,
      (acc, s) => s.y > acc ? s.y : acc,
    );
    final chartMax = (maxY > (goal ?? 0) ? maxY : (goal ?? 0)) * 1.2;
    final safeMax = chartMax <= 0 ? 1000.0 : chartMax;

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: safeMax,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 10,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => spots.map((spot) {
              return LineTooltipItem(
                '${spot.y.round()} kcal',
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              );
            }).toList(),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 34,
              getTitlesWidget: (value, meta) {
                return Text(
                  value >= 1000
                      ? '${(value / 1000).toStringAsFixed(1)}k'
                      : value.round().toString(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 18,
              interval: 7,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx != 0 && idx != 14 && idx != 28) {
                  return const SizedBox.shrink();
                }
                final daysAgo = _kWindow30 - idx;
                final label = daysAgo == 1
                    ? 'ontem'
                    : '${daysAgo}d atrás';
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: safeMax / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: theme.colorScheme.outlineVariant.withAlpha(60),
            strokeWidth: 1,
            dashArray: const [3, 4],
          ),
        ),
        extraLinesData: goal == null
            ? const ExtraLinesData()
            : ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: goal!,
                    color: theme.colorScheme.primary.withAlpha(180),
                    strokeWidth: 1.4,
                    dashArray: const [6, 4],
                  ),
                ],
              ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            barWidth: 2.6,
            color: theme.colorScheme.primary,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  theme.colorScheme.primary.withAlpha(70),
                  theme.colorScheme.primary.withAlpha(10),
                ],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }
}

// =====================================================================
// Meal distribution
// =====================================================================

class _MealDistributionCard extends StatelessWidget {
  final List<MealTypeCalories> distribution;

  const _MealDistributionCard({required this.distribution});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (distribution.isEmpty) {
      return _SectionCard(
        icon: Icons.restaurant_outlined,
        iconColor: theme.colorScheme.secondary,
        title: loc.nutritionBalanceMealDistribution,
        child: _EmptyNote(text: loc.nutritionBalanceMealEmpty),
      );
    }
    final total =
        distribution.fold<double>(0, (s, m) => s + m.totalCalories);
    final top = distribution.take(5).toList();
    final otherTotal = total -
        top.fold<double>(0, (s, m) => s + m.totalCalories);

    return _SectionCard(
      icon: Icons.restaurant_outlined,
      iconColor: theme.colorScheme.secondary,
      title: loc.nutritionBalanceMealDistribution,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < top.length; i++)
            _MealDistributionRow(
              rank: i + 1,
              entry: top[i],
              total: total,
            ),
          if (otherTotal > 0 && distribution.length > 5)
            _MealDistributionRow(
              rank: top.length + 1,
              entry: MealTypeCalories(
                mealType: 'other',
                displayName: loc.nutritionBalanceOtherMeals,
                totalCalories: otherTotal,
                itemCount: 0,
              ),
              total: total,
            ),
        ],
      ),
    );
  }
}

class _MealDistributionRow extends StatelessWidget {
  final int rank;
  final MealTypeCalories entry;
  final double total;

  const _MealDistributionRow({
    required this.rank,
    required this.entry,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final percent =
        total == 0 ? 0 : ((entry.totalCalories / total) * 100).round();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.displayName,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${entry.totalCalories.round()} kcal · $percent%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0 : entry.totalCalories / total,
                    minHeight: 6,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(100),
                    color: theme.colorScheme.secondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 56,
            child: Text(
              loc.nutritionItemCount(entry.itemCount),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Top calorie contributors
// =====================================================================

class _TopContributorsCard extends StatelessWidget {
  final List<CalorieContributor> contributors;
  final double totalConsumed;

  const _TopContributorsCard({
    required this.contributors,
    required this.totalConsumed,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    if (contributors.isEmpty || totalConsumed == 0) {
      return _SectionCard(
        icon: Icons.local_dining_outlined,
        iconColor: theme.colorScheme.tertiary,
        title: loc.nutritionBalanceTopContributors,
        child: _EmptyNote(text: loc.nutritionBalanceTopEmpty),
      );
    }
    final top = contributors.take(8).toList();
    final topShare = top.fold<double>(
          0,
          (s, c) => s + c.totalCalories,
        ) /
        totalConsumed;

    return _SectionCard(
      icon: Icons.local_dining_outlined,
      iconColor: theme.colorScheme.tertiary,
      title: loc.nutritionBalanceTopContributors,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (top.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                loc.nutritionBalanceTopShare(
                  top.length,
                  (topShare * 100).round(),
                ),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (var i = 0; i < top.length; i++)
            _ContributorRow(
              rank: i + 1,
              entry: top[i],
              totalConsumed: totalConsumed,
            ),
        ],
      ),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  final int rank;
  final CalorieContributor entry;
  final double totalConsumed;

  const _ContributorRow({
    required this.rank,
    required this.entry,
    required this.totalConsumed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final percent = totalConsumed == 0
        ? 0
        : ((entry.totalCalories / totalConsumed) * 100).round();
    final title = entry.brand == null || entry.brand!.isEmpty
        ? entry.name
        : '${entry.name} · ${entry.brand}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$rank',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  loc.nutritionBalanceContributorMeta(
                    entry.totalCalories.round(),
                    entry.occurrences,
                  ),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: totalConsumed == 0
                        ? 0
                        : entry.totalCalories / totalConsumed,
                    minHeight: 5,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest
                        .withAlpha(100),
                    color: theme.colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '$percent%',
              textAlign: TextAlign.end,
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =====================================================================
// Macros distribution
// =====================================================================

class _MacroBalanceCard extends StatelessWidget {
  final _MacroSummary? summary;
  final NutritionGoal? goal;

  const _MacroBalanceCard({required this.summary, required this.goal});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final data = summary;
    if (data == null) {
      return _SectionCard(
        icon: Icons.pie_chart_outline_rounded,
        iconColor: theme.colorScheme.primary,
        title: loc.nutritionBalanceMacros,
        child: const SizedBox(
          height: 120,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (data.totalKcal == 0) {
      return _SectionCard(
        icon: Icons.pie_chart_outline_rounded,
        iconColor: theme.colorScheme.primary,
        title: loc.nutritionBalanceMacros,
        child: _EmptyNote(text: loc.nutritionBalanceMacrosEmpty),
      );
    }
    final proteinKcal = data.proteinG * 4;
    final carbsKcal = data.carbsG * 4;
    final fatKcal = data.fatG * 9;
    final proteinPct = (proteinKcal / data.totalKcal) * 100;
    final carbsPct = (carbsKcal / data.totalKcal) * 100;
    final fatPct = (fatKcal / data.totalKcal) * 100;
    return _SectionCard(
      icon: Icons.pie_chart_outline_rounded,
      iconColor: theme.colorScheme.primary,
      title: loc.nutritionBalanceMacros,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 130,
                height: 130,
                child: _MacroDonut(
                  proteinPct: proteinPct,
                  carbsPct: carbsPct,
                  fatPct: fatPct,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MacroLegendRow(
                      label: loc.nutritionProgressProtein,
                      percent: proteinPct,
                      grams: data.proteinG,
                      goalG: goal?.proteinG,
                      color: const Color(0xFFF29E38),
                    ),
                    const SizedBox(height: 10),
                    _MacroLegendRow(
                      label: loc.nutritionProgressCarbs,
                      percent: carbsPct,
                      grams: data.carbsG,
                      goalG: goal?.carbsG,
                      color: const Color(0xFF20A39E),
                    ),
                    const SizedBox(height: 10),
                    _MacroLegendRow(
                      label: loc.nutritionProgressFat,
                      percent: fatPct,
                      grams: data.fatG,
                      goalG: goal?.fatG,
                      color: const Color(0xFF8E44AD),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroSummary {
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double totalKcal;
  const _MacroSummary({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.totalKcal,
  });
}

class _MacroDonut extends StatelessWidget {
  final double proteinPct;
  final double carbsPct;
  final double fatPct;

  const _MacroDonut({
    required this.proteinPct,
    required this.carbsPct,
    required this.fatPct,
  });

  @override
  Widget build(BuildContext context) {
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 32,
        startDegreeOffset: -90,
        sections: [
          PieChartSectionData(
            value: proteinPct,
            color: const Color(0xFFF29E38),
            radius: 22,
            showTitle: false,
          ),
          PieChartSectionData(
            value: carbsPct,
            color: const Color(0xFF20A39E),
            radius: 22,
            showTitle: false,
          ),
          PieChartSectionData(
            value: fatPct,
            color: const Color(0xFF8E44AD),
            radius: 22,
            showTitle: false,
          ),
        ],
      ),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }
}

class _MacroLegendRow extends StatelessWidget {
  final String label;
  final double percent;
  final double grams;
  final double? goalG;
  final Color color;

  const _MacroLegendRow({
    required this.label,
    required this.percent,
    required this.grams,
    required this.goalG,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasGoal = goalG != null && goalG! > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${percent.round()}%',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          hasGoal
              ? '${_formatG(grams)} / ${_formatG(goalG!)} g'
              : '${_formatG(grams)} g',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (hasGoal) ...[
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (grams / goalG!).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: theme.colorScheme.surfaceContainerHighest
                  .withAlpha(100),
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  static String _formatG(double v) {
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }
}

// =====================================================================
// Shared building blocks
// =====================================================================

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;

  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: iconColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(icon, size: 16, color: iconColor),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;
  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
