import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../repositories/workout_repository.dart';
import '../../repositories/analytics_repository.dart';
import '../../services/rest_timer_service.dart';
import 'active_workout_screen.dart';
import 'quick_add_screen.dart';
import 'calendar_screen.dart';
import 'exercise_library_screen.dart';
import 'routines_screen.dart';
import 'progress_screen.dart';
import 'body_tracker_screen.dart';
import 'settings_screen.dart';
import 'rest_timer_screen.dart';
import 'workout_detail_screen.dart';

class WorkoutHomeScreen extends StatefulWidget {
  const WorkoutHomeScreen({super.key});

  @override
  State<WorkoutHomeScreen> createState() => _WorkoutHomeScreenState();
}

class _WorkoutHomeScreenState extends State<WorkoutHomeScreen> {
  final _workoutRepo = WorkoutRepository();
  final _analyticsRepo = AnalyticsRepository();
  final _timerService = RestTimerService.instance;
  bool _isLoading = true;
  List<Map<String, dynamic>> _activeWorkouts = [];
  List<Map<String, dynamic>> _upcomingWorkouts = [];
  List<Map<String, dynamic>> _completedWorkouts = [];
  bool _showCompleted = true;
  bool _showUpcoming = true;

  // Stats for header card
  int _monthWorkouts = 0;
  double _monthVolume = 0;
  double _monthCardioDistance = 0;
  int _monthCardioTime = 0;
  int _currentStreak = 0;

  // Elapsed time timer for active workout
  Timer? _elapsedTimer;

  @override
  void initState() {
    super.initState();
    _timerService.addListener(_onTimerTick);
    _loadData();
  }

  @override
  void dispose() {
    _timerService.removeListener(_onTimerTick);
    _elapsedTimer?.cancel();
    super.dispose();
  }

  void _onTimerTick() {
    if (mounted) setState(() {});
  }

  /// Starts a periodic timer that keeps the elapsed time on the active
  /// workout banner live. Cancels any previous timer first.
  void _startElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeWorkouts.isNotEmpty) {
        setState(() {});
      }
    });
  }

  /// Cancels the elapsed timer.
  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final tomorrow = DateTime(now.year, now.month, now.day + 1);
      final monthStart = DateTime(now.year, now.month, 1);

      final allWorkouts = await _workoutRepo.getWorkouts(limit: 50);
      final futureWorkouts =
          await _workoutRepo.getWorkouts(startDate: tomorrow, limit: 20);

      // Load stats
      final overview = await _analyticsRepo.getWorkoutOverviewStats();
      _currentStreak = (overview['current_streak'] as int?) ?? 0;

      // Calculate month stats
      final monthStr = monthStart.toIso8601String().substring(0, 7);
      double monthVol = 0;
      double monthCardioDist = 0;
      int monthCardioTime = 0;
      int monthCount = 0;
      for (final w in allWorkouts) {
        final wDate = w['date'] as String? ?? '';
        if (wDate.startsWith(monthStr)) {
          monthCount++;
          // Get volume and cardio distance/time for this workout
          final exercises = await _workoutRepo.getWorkoutExercises(w['id'] as String);
          for (final ee in exercises) {
            final sets = await _workoutRepo.getExerciseSets(ee['id'] as String);
            for (final s in sets) {
              if ((s['is_warmup'] as int? ?? 0) == 0) {
                monthVol += ((s['weight'] as num?)?.toDouble() ?? 0) *
                    ((s['reps'] as int?) ?? 0);
                monthCardioDist += (s['distance'] as num?)?.toDouble() ?? 0;
                monthCardioTime += (s['time_seconds'] as int?) ?? 0;
              }
            }
          }
        }
      }
      _monthWorkouts = monthCount;
      _monthVolume = monthVol;
      _monthCardioDistance = monthCardioDist;
      _monthCardioTime = monthCardioTime;

      final active = await _workoutRepo.getActiveWorkouts();
      final completed = <Map<String, dynamic>>[];
      for (final w in allWorkouts) {
        if ((w['end_time'] as String?) != null) {
          completed.add(w);
        }
      }

      if (mounted) {
        setState(() {
          _activeWorkouts = active;
          _upcomingWorkouts = futureWorkouts.take(5).toList();
          _completedWorkouts = completed.take(5).toList();
          _isLoading = false;
        });
        // Keep the elapsed time live when there is an active workout
        if (active.isNotEmpty) {
          _startElapsedTimer();
        } else {
          _stopElapsedTimer();
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ===================== ACTIONS =====================
  Future<void> _startWorkout() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ActiveWorkoutScreen()),
    );
    _loadData();
  }

  Future<void> _openActiveWorkout(Map<String, dynamic> workout) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ActiveWorkoutScreen(workoutId: workout['id'] as String?),
      ),
    );
    _loadData();
  }

  Future<void> _quickAdd() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const QuickAddScreen()),
    );
    _loadData();
  }

  // ===================== HELPERS =====================
  String _formatVolume(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }

  String _formatDistance(double km) {
    if (km >= 100) return '${km.toStringAsFixed(0)}k';
    return km.toStringAsFixed(1);
  }

  String _formatMinutes(int seconds) {
    if (seconds <= 0) return '0';
    final min = seconds ~/ 60;
    if (min >= 60) return '${min ~/ 60}h${min % 60}';
    return '${min}min';
  }

  String _formatHeaderDate(AppLocalizations loc) {
    return DateFormat('EEEE, d MMMM', Intl.defaultLocale)
        .format(DateTime.now());
  }

  /// Returns a friendly "Last workout: `<when>`" string. Empty when there is
  /// no completed workout yet.
  String _lastWorkoutLabel(AppLocalizations loc) {
    if (_completedWorkouts.isEmpty) return '';
    final raw = _completedWorkouts.first['date'] as String?;
    if (raw == null || raw.isEmpty) return '';
    final workoutDate = DateTime.parse(raw);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final wd = DateTime(workoutDate.year, workoutDate.month, workoutDate.day);
    final diff = today.difference(wd).inDays;
    if (diff == 0) return loc.workoutHomeLastWorkoutToday;
    if (diff == 1) return loc.workoutHomeLastWorkoutYesterday;
    if (diff < 7) {
      return loc.workoutHomeLastWorkoutAgo('$diff ${loc.workoutHomeDays}');
    }
    return DateFormat.MMMd(Intl.defaultLocale).format(workoutDate);
  }

  /// Pretty-prints the elapsed time of the active workout (e.g. "23 min",
  /// "1h 12min"). Returns null if it can't be computed.
  String? _activeElapsed(Map<String, dynamic> workout) {
    final startStr = workout['start_time'] as String?;
    if (startStr == null) return null;
    final start = DateTime.tryParse(startStr);
    if (start == null) return null;
    final elapsed = DateTime.now().difference(start);
    if (elapsed.isNegative) return null;
    final h = elapsed.inHours;
    final m = elapsed.inMinutes % 60;
    if (h > 0) return '${h}h ${m}min';
    if (m > 0) return '${m}min';
    return '${elapsed.inSeconds}s';
  }

  bool get _hasAnyHistory =>
      _activeWorkouts.isNotEmpty || _completedWorkouts.isNotEmpty;

  // ===================== BUILD =====================
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatHeaderDate(loc),
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: _buildAppBarActions(theme, loc),
      ),
      body: _isLoading
          ? const _LoadingSkeleton()
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // First-time empty state replaces the stats card.
                  if (!_hasAnyHistory)
                    SliverToBoxAdapter(
                      child: _buildFirstTimeEmpty(theme, loc),
                    )
                  else
                    SliverToBoxAdapter(
                      child: _buildHeaderStats(theme, loc),
                    ),
                  // Active workout banner — shown right after the stats
                  // card so the high-level summary still leads the page.
                  if (_activeWorkouts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildActiveBanner(theme, loc, _activeWorkouts.first),
                    ),
                  SliverToBoxAdapter(child: _buildSectionHeader(loc.workoutHomeSectionQuickActions, theme)),
                  SliverToBoxAdapter(child: _buildQuickActions(theme, loc)),
                  SliverToBoxAdapter(child: _buildSectionHeader(loc.workoutHomeSectionTools, theme)),
                  SliverToBoxAdapter(child: _buildNavGrid(theme, loc)),
                  if (_upcomingWorkouts.isNotEmpty)
                    SliverToBoxAdapter(child: _buildUpcomingSection(theme, loc)),
                  if (_completedWorkouts.isNotEmpty)
                    SliverToBoxAdapter(child: _buildCompletedSection(theme, loc)),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
            ),
    );
  }

  // ===================== APP BAR =====================
  List<Widget> _buildAppBarActions(ThemeData theme, AppLocalizations loc) {
    return [
      if (_timerService.isActive)
        _TimerPill(
          remainingSeconds: _timerService.remainingSeconds,
          isRunning: _timerService.isRunning,
          isPaused: _timerService.isPaused,
          shortTime: _timerService.shortTime,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const RestTimerScreen()),
          ),
        )
      else
        IconButton(
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CalendarScreen()),
          ),
          tooltip: loc.workoutHomeHistoryTooltip,
        ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const WorkoutSettingsScreen()),
        ),
        tooltip: loc.workoutHomeSettingsTooltip,
      ),
    ];
  }

  // ===================== ACTIVE WORKOUT BANNER =====================
  Widget _buildActiveBanner(
      ThemeData theme, AppLocalizations loc, Map<String, dynamic> workout) {
    final elapsed = _activeElapsed(workout) ?? '--';

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Material(
        color: theme.colorScheme.primary,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _openActiveWorkout(workout),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
            child: Row(
              children: [
                // Pulsing dot
                _PulsingDot(color: theme.colorScheme.onPrimary),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        loc.workoutHomeOngoing,
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        loc.workoutHomeActiveBannerSubtitle(elapsed),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              theme.colorScheme.onPrimary.withAlpha(220),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onPrimary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.play_arrow_rounded,
                          size: 18, color: theme.colorScheme.primary),
                      const SizedBox(width: 2),
                      Text(
                        loc.workoutHomeActiveBannerAction,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 60.ms).slideY(begin: 0.05);
  }

  // ===================== STATS =====================
  Widget _buildHeaderStats(ThemeData theme, AppLocalizations loc) {
    final lastWorkout = _lastWorkoutLabel(loc);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.colorScheme.surfaceContainerHighest.withAlpha(200),
              theme.colorScheme.surfaceContainerLow,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _StatItem(
                    label: loc.workoutHomeMonthWorkouts,
                    value: '$_monthWorkouts',
                    icon: Icons.fitness_center,
                    color: theme.colorScheme.primary,
                    theme: theme,
                  ),
                ),
                _StatDivider(theme: theme),
                Expanded(
                  child: _StatItem(
                    label: loc.workoutHomeVolume,
                    value: _formatVolume(_monthVolume),
                    unit: 'kg',
                    icon: Icons.auto_graph,
                    color: theme.colorScheme.secondary,
                    theme: theme,
                  ),
                ),
                _StatDivider(theme: theme),
                Expanded(
                  child: _StatItem(
                    label: loc.workoutHomeStreak,
                    value: '$_currentStreak',
                    unit: _currentStreak == 1
                        ? loc.workoutHomeDay
                        : loc.workoutHomeDays,
                    icon: Icons.local_fire_department,
                    color: Colors.orange,
                    theme: theme,
                  ),
                ),
              ],
            ),
            if (_monthCardioDistance > 0 || _monthCardioTime > 0) ...[
              const SizedBox(height: 10),
              Container(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(60),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: loc.workoutHomeCardioDistance,
                      value: _formatDistance(_monthCardioDistance),
                      icon: Icons.map,
                      color: const Color(0xFFE53935),
                      theme: theme,
                    ),
                  ),
                  _StatDivider(theme: theme),
                  Expanded(
                    child: _StatItem(
                      label: loc.workoutHomeCardioTime,
                      value: _formatMinutes(_monthCardioTime),
                      icon: Icons.timer_outlined,
                      color: Colors.deepOrange,
                      theme: theme,
                    ),
                  ),
                  _StatDivider(theme: theme),
                  Expanded(
                    child: _StatItem(
                      label: loc.commonTotal,
                      value: _monthCardioDistance > 0 && _monthCardioTime > 0 ? (_monthCardioTime / _monthCardioDistance).toStringAsFixed(0) : '--',
                      unit: '/km',
                      icon: Icons.speed,
                      color: Colors.brown,
                      theme: theme,
                    ),
                  ),
                ],
              ),
            ],
            if (lastWorkout.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                height: 1,
                color: theme.colorScheme.outlineVariant.withAlpha(80),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Icon(Icons.history,
                      size: 14, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '${loc.workoutHomeLastWorkout}: ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    lastWorkout,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 120.ms)
        .slideY(begin: 0.05);
  }

  // ===================== SECTION HEADER =====================
  Widget _buildSectionHeader(String text, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 1.5,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  // ===================== QUICK ACTIONS =====================
  Widget _buildQuickActions(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: _ActionCard(
              icon: Icons.fitness_center,
              label: loc.workoutHomeNewWorkout,
              subtitle: loc.workoutHomeStartNow,
              color: theme.colorScheme.primary,
              onTap: _startWorkout,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ActionCard(
              icon: Icons.bolt,
              label: loc.workoutHomeQuickAdd,
              subtitle: loc.workoutHomeQuickAddSubtitle,
              color: theme.colorScheme.secondary,
              onTap: _quickAdd,
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 200.ms);
  }

  // ===================== NAV GRID (2x2) =====================
  Widget _buildNavGrid(ThemeData theme, AppLocalizations loc) {
    final items = [
      _NavItemData(
        Icons.fitness_center,
        loc.workoutHomeExercises,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ExerciseLibraryScreen())),
      ),
      _NavItemData(
        Icons.repeat,
        loc.workoutHomeRoutines,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const RoutinesScreen())),
      ),
      _NavItemData(
        Icons.bar_chart,
        loc.workoutHomeProgress,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const ProgressScreen())),
      ),
      _NavItemData(
        Icons.monitor_weight_outlined,
        loc.workoutHomeBodyMeasurements,
        () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const BodyTrackerScreen())),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side:
              BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
        ),
        clipBehavior: Clip.antiAlias,
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 1.6,
            mainAxisSpacing: 0,
            crossAxisSpacing: 0,
          ),
          itemCount: items.length,
          itemBuilder: (ctx, i) {
            final item = items[i];
            final isLeft = i % 2 == 0;
            final isBottom = i < 2;
            return _NavTile(
              icon: item.icon,
              label: item.label,
              onTap: item.onTap,
              showLeftBorder: !isLeft,
              showTopBorder: !isBottom,
            );
          },
        ),
      ),
    ).animate().fadeIn(duration: 350.ms, delay: 280.ms);
  }

  // ===================== UPCOMING =====================
  Widget _buildUpcomingSection(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleSectionHeader(
            icon: Icons.schedule,
            iconBg: theme.colorScheme.secondaryContainer,
            iconFg: theme.colorScheme.onSecondaryContainer,
            title: loc.workoutHomeUpcoming,
            count: _upcomingWorkouts.length,
            expanded: _showUpcoming,
            onTap: () => setState(() => _showUpcoming = !_showUpcoming),
          ),
          if (_showUpcoming) ...[
            const SizedBox(height: 8),
            ...(_upcomingWorkouts
                .map((w) => _buildWorkoutCard(w, theme, isActive: false))),
          ],
        ],
      ),
    );
  }

  // ===================== COMPLETED =====================
  Widget _buildCompletedSection(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CollapsibleSectionHeader(
            icon: Icons.check_circle_outline,
            iconBg: theme.colorScheme.primaryContainer,
            iconFg: theme.colorScheme.onPrimaryContainer,
            title: loc.workoutHomeCompleted,
            count: _completedWorkouts.length,
            expanded: _showCompleted,
            onTap: () => setState(() => _showCompleted = !_showCompleted),
          ),
          if (_showCompleted) ...[
            const SizedBox(height: 8),
            ...(_completedWorkouts
                .map((w) => _buildWorkoutCard(w, theme, isActive: false))),
          ],
        ],
      ),
    );
  }

  // ===================== FIRST-TIME EMPTY =====================
  Widget _buildFirstTimeEmpty(ThemeData theme, AppLocalizations loc) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer.withAlpha(120),
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withAlpha(30),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 32,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              loc.workoutHomeEmptyTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              loc.workoutHomeEmptySubtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _startWorkout,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(loc.workoutHomeEmptyCta),
            ),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(duration: 300.ms, delay: 120.ms)
        .slideY(begin: 0.05);
  }

  // ===================== WORKOUT CARD =====================
  Widget _buildWorkoutCard(Map<String, dynamic> workout, ThemeData theme,
      {required bool isActive}) {
    final date = (workout['date'] as String?) ?? '';
    final formatted = date.isNotEmpty
        ? DateFormat(
            Intl.defaultLocale?.startsWith('pt') == true
                ? "d 'de' MMMM yyyy"
                : 'MMMM d, yyyy',
            Intl.defaultLocale,
          ).format(DateTime.parse(date))
        : '';
    final duration = (workout['duration_seconds'] as int?) ?? 0;
    final durStr = isActive
        ? AppLocalizations.of(context)!.workoutHomeOngoing
        : duration > 0
            ? AppLocalizations.of(context)!
                .workoutDetailDuration(duration ~/ 60, duration % 60)
            : '--';
    final feeling = (workout['feeling_rating'] as int?) ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isActive
                ? theme.colorScheme.primary.withAlpha(100)
                : theme.colorScheme.outlineVariant.withAlpha(80),
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    WorkoutDetailScreen(workoutId: workout['id'] as String),
              ),
            );
            _loadData();
          },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? theme.colorScheme.primary.withAlpha(25)
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isActive
                        ? Icons.play_circle_fill
                        : Icons.fitness_center,
                    color: isActive
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(formatted,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(durStr,
                          style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (feeling > 0)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(
                      5,
                      (i) => Icon(
                        i < feeling ? Icons.star : Icons.star_border,
                        size: 14,
                        color: Colors.amber,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===================== SHARED WIDGETS =====================

/// Loading skeleton — keeps the layout stable so the transition into real
/// content doesn't cause a jarring jump.
class _LoadingSkeleton extends StatelessWidget {
  const _LoadingSkeleton();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.surfaceContainerHighest;
    BoxDecoration box({double r = 8}) => BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(r),
        );
    Widget line({required double h, double? w, double r = 8}) => Container(
          height: h,
          width: w,
          decoration: box(r: r),
        );
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        line(h: 24, w: 180),
        const SizedBox(height: 8),
        line(h: 14, w: 240),
        const SizedBox(height: 20),
        line(h: 90, r: 20),
        const SizedBox(height: 20),
        line(h: 12, w: 80),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: line(h: 90, r: 16)),
            const SizedBox(width: 12),
            Expanded(child: line(h: 90, r: 16)),
          ],
        ),
        const SizedBox(height: 20),
        line(h: 12, w: 60),
        const SizedBox(height: 12),
        line(h: 110, r: 16),
        const SizedBox(height: 20),
        line(h: 12, w: 100),
        const SizedBox(height: 12),
        line(h: 64, r: 12),
        const SizedBox(height: 8),
        line(h: 64, r: 12),
      ],
    );
  }
}

class _PulsingDot extends StatelessWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 16,
      height: 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                begin: const Offset(0.6, 0.6),
                end: const Offset(1.0, 1.0),
                duration: 1.seconds,
              )
              .fadeOut(begin: 0.6, duration: 1.seconds),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  final ThemeData theme;
  const _StatDivider({required this.theme});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.colorScheme.outlineVariant.withAlpha(80),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final ThemeData theme;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.theme,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Text(
              value,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                height: 1.1,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 2),
              Text(
                unit!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withAlpha(25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 14),
              Text(label,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool showLeftBorder;
  final bool showTopBorder;

  const _NavTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.showLeftBorder,
    required this.showTopBorder,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.outlineVariant.withAlpha(80);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: showLeftBorder
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
              top: showTopBorder
                  ? BorderSide(color: borderColor)
                  : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18, color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _CollapsibleSectionHeader extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconFg;
  final String title;
  final int count;
  final bool expanded;
  final VoidCallback onTap;

  const _CollapsibleSectionHeader({
    required this.icon,
    required this.iconBg,
    required this.iconFg,
    required this.title,
    required this.count,
    required this.expanded,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 18, color: iconFg),
            ),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            if (count > 0) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _TimerPill extends StatelessWidget {
  final int remainingSeconds;
  final bool isRunning;
  final bool isPaused;
  final String shortTime;
  final VoidCallback onTap;

  const _TimerPill({
    required this.remainingSeconds,
    required this.isRunning,
    required this.isPaused,
    required this.shortTime,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUrgent = remainingSeconds <= 5 && isRunning;
    final bg = isUrgent
        ? Colors.red.withAlpha(40)
        : theme.colorScheme.primaryContainer;
    final fg = isUrgent ? Colors.red : theme.colorScheme.onPrimaryContainer;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaused ? Icons.pause : Icons.timer,
              size: 18,
              color: fg,
            ),
            const SizedBox(width: 4),
            Text(
              shortTime,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItemData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  _NavItemData(this.icon, this.label, this.onTap);
}
