import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_night_summary.dart';
import 'package:workout_notes/screens/alarms/traditional_alarms_screen.dart';
import 'package:workout_notes/screens/settings/settings_screen.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_result_screen.dart';
import 'package:workout_notes/screens/sleep/sleep_monitor_screen.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/utils/load_generation.dart';
import 'package:workout_notes/widgets/ai/ai_coach_header_button.dart';
import 'package:workout_notes/widgets/sleep/sleep_history_row.dart';
import 'package:workout_notes/widgets/sleep/sleep_last_night_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_trend_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_week_card.dart';
import 'package:workout_notes/widgets/ui/load_error_view.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class SleepTrackerScreen extends StatefulWidget {
  const SleepTrackerScreen({super.key});

  @override
  State<SleepTrackerScreen> createState() => _SleepTrackerScreenState();
}

class _SleepTrackerScreenState extends State<SleepTrackerScreen> {
  static const int _historyPageSize = 10;
  static const int _trendDays = 30;

  final _repository = DatabaseHelper.instance.sleepRepo;
  final _monitorRepository = DatabaseHelper.instance.sleepMonitorRepo;
  final _monitorService = SleepMonitorService.instance;
  final _sleepGoalService = SleepGoalService();
  List<SleepEntry> _entries = const [];
  List<SleepEntry> _weekEntries = const [];
  List<SleepEntry> _trendEntries = const [];
  List<SleepMonitorSession> _unestimatedSessions = const [];
  SleepDashboardStats? _stats;
  SleepNightSummary? _latestNight;
  Map<String, SleepNightSummary> _nightSummaries = const {};
  final _generation = LoadGeneration();
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _loadFailed = false;
  int _historyDisplayCount = 5;
  int _totalEntries = 0;
  bool _hasMoreHistory = false;
  bool _isLoadingMoreHistory = false;
  int _lastRecoveryCount = 0;
  int _lastAnalysisRevision = 0;
  late DateTime _weekEnd;
  bool _isChangingWeek = false;
  int _sleepGoalMinutes = SleepGoalService.defaultGoalMinutes;

  @override
  void initState() {
    super.initState();
    _weekEnd = dayOf(DateTime.now());
    _monitorService.addListener(_onMonitorChanged);
    _lastRecoveryCount = _monitorService.recoveredCount;
    _lastAnalysisRevision = _monitorService.analysisRevision;
    _bootstrap();
    if (_lastRecoveryCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showRecoveryMessage(_lastRecoveryCount);
      });
    }
  }

  @override
  void dispose() {
    _generation.invalidate();
    _monitorService.removeListener(_onMonitorChanged);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _monitorService.initialize();
    if (mounted) await _load();
  }

  void _onMonitorChanged() {
    if (mounted) {
      setState(() {});
      if (_monitorService.recoveredCount > _lastRecoveryCount) {
        _lastRecoveryCount = _monitorService.recoveredCount;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _showRecoveryMessage(_lastRecoveryCount);
        });
      }
      if (_monitorService.analysisRevision > _lastAnalysisRevision) {
        _lastAnalysisRevision = _monitorService.analysisRevision;
        _load();
      }
      if (!_monitorService.isMonitoring &&
          (_monitorService.state.status == 'completed' ||
              _monitorService.state.status == 'interrupted')) {
        _load();
      }
    }
  }

  void _showRecoveryMessage(int count) {
    final loc = AppLocalizations.of(context);
    if (loc == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(loc.sleepMonitorRecovered(count))));
  }

  /// Reloads the dashboard. Only the newest load applies its result, and a
  /// failed one keeps what is on screen (with a retry) instead of looking like
  /// an empty history.
  Future<void> _load() async {
    final token = _generation.begin();
    if (mounted && !_hasLoaded) setState(() => _isLoading = true);
    try {
      final today = dayOf(DateTime.now());
      final results = await Future.wait<Object>([
        _repository.getEntries(limit: _historyPageSize + 1),
        _repository.getDashboardStats(referenceDate: _weekEnd),
        _sleepGoalService.load(),
        _monitorRepository.getNightSummaries(limit: _trendDays),
        _repository.getEntryCount(),
        _monitorRepository.getUnestimatedSessions(),
        _repository.getEntries(
          from: _weekEnd.subtract(const Duration(days: 6)),
          to: _weekEnd,
        ),
        _repository.getEntries(
          from: today.subtract(const Duration(days: _trendDays - 1)),
          to: today,
        ),
      ]);
      final entryPage = results[0] as List<SleepEntry>;
      final entries = entryPage.take(_historyPageSize).toList(growable: false);
      final stats = results[1] as SleepDashboardStats;
      final nightSummaries = results[3] as List<SleepNightSummary>;
      final summariesByEntry = {
        for (final summary in nightSummaries) summary.entry.id: summary,
      };
      if (!mounted || !_generation.isCurrent(token)) return;
      setState(() {
        _entries = entries;
        _unestimatedSessions = results[5] as List<SleepMonitorSession>;
        _stats = stats;
        _sleepGoalMinutes = results[2] as int;
        _latestNight = stats.latest == null
            ? null
            : summariesByEntry[stats.latest!.id];
        _nightSummaries = summariesByEntry;
        _historyDisplayCount = 5;
        _totalEntries = results[4] as int;
        _hasMoreHistory = entryPage.length > _historyPageSize;
        _weekEntries = results[6] as List<SleepEntry>;
        _trendEntries = results[7] as List<SleepEntry>;
        _hasLoaded = true;
        _loadFailed = false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || !_generation.isCurrent(token)) return;
      setState(() {
        _loadFailed = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreHistory() async {
    if (_isLoadingMoreHistory) return;
    if (_historyDisplayCount < _entries.length) {
      setState(() {
        _historyDisplayCount = math.min(
          _historyDisplayCount + 5,
          _entries.length,
        );
      });
      return;
    }
    if (!_hasMoreHistory) return;

    setState(() => _isLoadingMoreHistory = true);
    try {
      final offset = _entries.length;
      final results = await Future.wait<Object>([
        _repository.getEntries(limit: _historyPageSize + 1, offset: offset),
        _monitorRepository.getNightSummaries(
          limit: _historyPageSize,
          offset: offset,
        ),
      ]);
      final page = results[0] as List<SleepEntry>;
      final additions = page.take(_historyPageSize).toList(growable: false);
      final summaries = results[1] as List<SleepNightSummary>;
      if (!mounted) return;
      setState(() {
        _entries = [..._entries, ...additions];
        _nightSummaries = {
          ..._nightSummaries,
          for (final summary in summaries) summary.entry.id: summary,
        };
        _historyDisplayCount = _entries.length;
        _hasMoreHistory = page.length > _historyPageSize;
      });
    } finally {
      if (mounted) setState(() => _isLoadingMoreHistory = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _formatHeaderDate(),
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
        actions: [
          const AiCoachHeaderButton(),
          IconButton(
            tooltip: loc.alarmTitle,
            icon: const Icon(Icons.alarm_rounded),
            onPressed: _openTraditionalAlarms,
          ),
          IconButton(
            tooltip: loc.settingsTitle,
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openAppSettings,
          ),
        ],
      ),
      floatingActionButton: _buildMonitorFab(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : (_loadFailed && !_hasLoaded)
          ? LoadErrorView(onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: _entries.isEmpty
                  ? _buildEmptyState(loc)
                  : _buildContent(loc),
            ),
    );
  }

  String _formatHeaderDate() =>
      DateFormat('EEEE, d MMMM', Intl.defaultLocale).format(DateTime.now());

  Widget _buildEmptyState(AppLocalizations loc) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppUi.screenPadding,
      child: Column(
        children: [
          if (_loadFailed) LoadErrorBanner(onRetry: _load),
          ..._incompleteSessionCards(loc),
          SizedBox(
            height: MediaQuery.sizeOf(context).height * .5,
            child: AppEmptyState(
              icon: Icons.nightlight_round,
              title: loc.sleepEmptyTitle,
              subtitle: loc.sleepEmptySubtitle,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(AppLocalizations loc) {
    final stats = _stats!;
    final weeklyDays = _weeklyDays();
    final latest = stats.latest;
    final latestSession = _latestNight?.session;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: AppUi.screenPadding,
      children: [
        if (_loadFailed) LoadErrorBanner(onRetry: _load),
        ..._incompleteSessionCards(loc),
        if (latest != null) ...[
          SleepLastNightCard(
            entry: latest,
            session: latestSession,
            goalMinutes: _sleepGoalMinutes,
            onTap: () => _showDetails(latest),
          ),
        ],
        AppSectionHeader(
          '${loc.sleepWeekTitle} · ${SleepUi.dayMonth(weeklyDays.first)} – '
          '${SleepUi.dayMonth(weeklyDays.last)}',
          padding: const EdgeInsets.fromLTRB(4, 18, 0, 6),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('sleep-previous-week'),
                tooltip: loc.sleepPreviousWeek,
                visualDensity: VisualDensity.compact,
                onPressed: _isChangingWeek ? null : () => _changeWeek(-1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              IconButton(
                key: const Key('sleep-next-week'),
                tooltip: loc.sleepNextWeek,
                visualDensity: VisualDensity.compact,
                onPressed: _isChangingWeek || !_canGoToNextWeek
                    ? null
                    : () => _changeWeek(1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
        ),
        SleepWeekCard(
          stats: stats,
          entries: _weekEntries,
          days: weeklyDays,
          goalMinutes: _sleepGoalMinutes,
        ),
        AppSectionHeader(loc.sleepTrendChart),
        SleepTrendCard(
          entries: _trendEntries,
          end: DateTime.now(),
          goalMinutes: _sleepGoalMinutes,
          deepMinutesByEntry: {
            for (final summary in _nightSummaries.values)
              if (summary.session?.deepSleepMinutes != null &&
                  (summary.session?.stageConfidence ?? 0) >= 0.6)
                summary.entry.id: summary.session!.deepSleepMinutes!,
          },
        ),
        AppSectionHeader(
          loc.sleepHistory,
          trailing: Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              loc.sleepEntries(_totalEntries),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
        _buildHistory(loc),
      ],
    );
  }

  Widget? _buildMonitorFab() {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    final state = _monitorService.state;
    final isActive = _monitorService.isMonitoring;
    final loc = AppLocalizations.of(context)!;
    if (!isActive && state.isAlarmPending) {
      // The alarm of the night still waits for an answer (ringing or
      // snoozed): lead straight to it instead of "start monitoring".
      final alarmAt = state.alarmAt?.toLocal();
      final colors = Theme.of(context).colorScheme;
      return FloatingActionButton.extended(
        heroTag: 'sleep-monitor-fab',
        onPressed: _openMonitor,
        backgroundColor: colors.tertiaryContainer,
        foregroundColor: colors.onTertiaryContainer,
        icon: Icon(
          state.isAlarmRinging ? Icons.alarm_rounded : Icons.snooze_rounded,
        ),
        label: Text(
          state.isAlarmRinging || alarmAt == null
              ? loc.sleepMonitorAlarmRinging
              : loc.alarmSnoozingUntil(
                  MaterialLocalizations.of(
                    context,
                  ).formatTimeOfDay(TimeOfDay.fromDateTime(alarmAt)),
                ),
        ),
      );
    }
    final elapsed = DurationFormat.clock(state.elapsed);
    return FloatingActionButton.extended(
      heroTag: 'sleep-monitor-fab',
      onPressed: _openMonitor,
      icon: Icon(isActive ? Icons.graphic_eq_rounded : Icons.nightlight_round),
      label: Text(
        isActive
            ? '${loc.sleepMonitorOpenActive} · $elapsed'
            : loc.sleepMonitorCta,
      ),
    );
  }

  List<Widget> _incompleteSessionCards(AppLocalizations loc) => [
    for (final session in _unestimatedSessions)
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: AppSectionCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: AppListRow(
            leading: AppIconBadge(
              Icons.bedtime_outlined,
              color: Theme.of(context).colorScheme.tertiary,
            ),
            title: loc.sleepIncompleteNight,
            subtitle: DateFormat.yMd(
              Localizations.localeOf(context).toLanguageTag(),
            ).add_jm().format(session.startedAt.toLocal()),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      SleepMonitorResultScreen(sessionId: session.id),
                ),
              );
              if (mounted) await _load();
            },
          ),
        ),
      ),
  ];

  Future<void> _openTraditionalAlarms() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const TraditionalAlarmsScreen()),
    );
    if (mounted) await _load();
  }

  Future<void> _openAppSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppSettingsScreen()),
    );
    if (mounted) await _load();
  }

  bool get _canGoToNextWeek {
    return _weekEnd.isBefore(dayOf(DateTime.now()));
  }

  Future<void> _changeWeek(int direction) async {
    if (_isChangingWeek) return;
    final today = dayOf(DateTime.now());
    var candidate = _weekEnd.add(Duration(days: direction * 7));
    if (candidate.isAfter(today)) candidate = today;
    if (candidate == _weekEnd) return;

    setState(() => _isChangingWeek = true);
    try {
      final results = await Future.wait<Object>([
        _repository.getDashboardStats(referenceDate: candidate),
        _repository.getEntries(
          from: candidate.subtract(const Duration(days: 6)),
          to: candidate,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _weekEnd = candidate;
        _stats = results[0] as SleepDashboardStats;
        _weekEntries = results[1] as List<SleepEntry>;
      });
    } finally {
      if (mounted) setState(() => _isChangingWeek = false);
    }
  }

  Widget _buildHistory(AppLocalizations loc) {
    final visibleCount = math.min(_historyDisplayCount, _entries.length);
    final colors = Theme.of(context).colorScheme;
    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AppDividedList(
        children: [
          for (final entry in _entries.take(visibleCount))
            SleepHistoryRow(
              entry: entry,
              summary: _nightSummaries[entry.id],
              goalMinutes: _sleepGoalMinutes,
              onTap: () => _showDetails(entry),
            ),
          if (visibleCount < _entries.length || _hasMoreHistory)
            TextButton.icon(
              onPressed: _isLoadingMoreHistory ? null : _loadMoreHistory,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: colors.primary,
              ),
              icon: _isLoadingMoreHistory
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more_rounded),
              label: Text(loc.sleepLoadMoreCount(5)),
            ),
        ],
      ),
    );
  }

  Future<void> _openMonitor() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SleepMonitorScreen()),
    );
    await _load();
  }

  Future<void> _showDetails(SleepEntry entry) async {
    final monitorSession = await _monitorRepository.getSessionForSleepEntry(
      entry.id,
    );
    if (!mounted) return;
    if (monitorSession != null) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              SleepMonitorResultScreen(sessionId: monitorSession.id),
        ),
      );
      await _load();
      return;
    }
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) {
        final mediaQuery = MediaQuery.of(sheetContext);
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: mediaQuery.size.height * 0.9,
            ),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                0,
                20,
                24 + mediaQuery.viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    loc.sleepNightOf(SleepUi.weekdayDayMonth(entry.date)),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    SleepUi.duration(loc, entry.effectiveSleepMinutes),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                  const SizedBox(height: 16),
                  AppMetricGrid(
                    children: [
                      AppMetricBox(
                        icon: Icons.bedtime_outlined,
                        label: loc.sleepDuration,
                        value: SleepUi.duration(loc, entry.sleepMinutes),
                      ),
                      AppMetricBox(
                        icon: Icons.timelapse_outlined,
                        label: loc.sleepActualDuration,
                        value: entry.actualSleepMinutes == null
                            ? '--'
                            : SleepUi.duration(loc, entry.actualSleepMinutes),
                      ),
                      AppMetricBox(
                        icon: Icons.nightlight_outlined,
                        label: loc.sleepBedtime,
                        value: SleepUi.clock(entry.bedtimeMinutes),
                      ),
                      AppMetricBox(
                        icon: Icons.wb_sunny_outlined,
                        label: loc.sleepWakeTime,
                        value: SleepUi.clock(entry.wakeTimeMinutes),
                      ),
                      if (entry.timeInBedMinutes != null)
                        AppMetricBox(
                          icon: Icons.hotel_rounded,
                          label: loc.sleepMonitorTimeInBed,
                          value: SleepUi.duration(loc, entry.timeInBedMinutes),
                        ),
                      if (entry.efficiency != null)
                        AppMetricBox(
                          icon: Icons.speed_rounded,
                          label: loc.sleepEfficiency,
                          value: '${entry.efficiency!.round()}%',
                        ),
                    ],
                  ),
                  if (entry.comment != null && entry.comment!.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(entry.comment!),
                  ],
                  const SizedBox(height: 18),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _deleteEntry(entry);
                      },
                      icon: const Icon(Icons.delete_outline),
                      label: Text(loc.sleepDelete),
                      style: TextButton.styleFrom(
                        foregroundColor: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteEntry(SleepEntry entry) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.sleepDelete,
      message: loc.sleepDeleteConfirm,
      confirmLabel: loc.commonDelete,
      destructive: true,
    );
    if (confirmed != true) return;
    await _repository.delete(entry.id);
    if (!mounted) return;
    await _load();
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.sleepDeleted)));
    }
  }

  List<DateTime> _weeklyDays() {
    return List.generate(
      7,
      (index) => _weekEnd.subtract(Duration(days: 6 - index)),
    );
  }
}
