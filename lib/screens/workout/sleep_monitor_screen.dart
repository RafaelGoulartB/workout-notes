import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_mode.dart';
import 'package:workout_notes/models/sleep_monitor_state.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/sleep_mission_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';
import 'package:workout_notes/utils/sleep_alarm_time.dart';

import 'sleep_monitor_result_screen.dart';
import 'sleep_settings_screen.dart';

class SleepMonitorScreen extends StatefulWidget {
  const SleepMonitorScreen({super.key});

  @override
  State<SleepMonitorScreen> createState() => _SleepMonitorScreenState();
}

class _SleepMonitorScreenState extends State<SleepMonitorScreen>
    with WidgetsBindingObserver {
  final _service = SleepMonitorService.instance;
  final _missions = SleepMissionService();
  Timer? _ticker;
  TimeOfDay _selectedTime = const TimeOfDay(hour: 7, minute: 0);
  SleepMonitoringMode _selectedMode = SleepMonitoringMode.alarmWithoutMission;
  bool _isBusy = false;
  bool _loading = true;
  bool _openingResult = false;
  String? _pendingAlarmResultId;
  String? _handledAlarmResultId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_onChanged);
    _initialize();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _service.removeListener(_onChanged);
    _ticker?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _service.isSupported) {
      _reloadMission();
      _service.initialize().then((_) => _service.getAlarmCapabilities());
      _openPendingAlarmResult();
    }
  }

  Future<void> _reloadMission() async {
    await _missions.load();
    if (!mounted) return;
    if (_selectedMode == SleepMonitoringMode.alarmWithMission &&
        !_missions.config.isReady) {
      setState(() {
        _selectedMode = SleepMonitoringMode.alarmWithoutMission;
      });
      await _missions.setLastMode(_selectedMode);
      return;
    }
    setState(() {});
  }

  Future<void> _initialize() async {
    await _service.initialize();
    if (!_service.isSupported) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    await _service.getAlarmCapabilities();
    await _missions.load();
    final defaultAlarm = SleepAlarmTime.defaultAlarm();
    if (!mounted) return;
    setState(() {
      _selectedTime = TimeOfDay.fromDateTime(defaultAlarm);
      final remembered = _missions.lastMode;
      _selectedMode =
          remembered == SleepMonitoringMode.alarmWithMission &&
              !_missions.config.isReady
          ? SleepMonitoringMode.alarmWithoutMission
          : remembered;
      _loading = false;
    });
  }

  void _onChanged() {
    final state = _service.state;
    if (!state.isActive &&
        state.endReason == 'alarm' &&
        state.alarmDismissed &&
        state.sessionId != null &&
        state.sessionId != _handledAlarmResultId) {
      _pendingAlarmResultId = state.sessionId;
      _handledAlarmResultId = state.sessionId;
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _openPendingAlarmResult();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _openPendingAlarmResult() async {
    final sessionId = _pendingAlarmResultId;
    if (!mounted || sessionId == null || _openingResult) return;
    _openingResult = true;
    try {
      await _service.recoverPendingSessions();
      if (!mounted) return;
      _pendingAlarmResultId = null;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepMonitorResultScreen(sessionId: sessionId),
        ),
      );
    } finally {
      _openingResult = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = _service.state;
    if (!state.supported) {
      return Scaffold(
        appBar: AppBar(title: Text(loc.sleepMonitorTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              loc.sleepMonitorAndroidOnly,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final active = state.isActive;
    final alarmAt = active && state.alarmAt != null
        ? state.alarmAt!.toLocal()
        : _selectedMode.hasAlarm
        ? SleepAlarmTime.nextOccurrence(_selectedTime)
        : null;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: Text(loc.sleepMonitorTitle)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _NightBackground(
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  16,
                  MediaQuery.paddingOf(context).top + kToolbarHeight + 12,
                  16,
                  28,
                ),
                children: active
                    ? _runningContent(loc, state, alarmAt)
                    : _readyContent(loc, state, alarmAt),
              ),
            ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: active
                  ? FilledButton.icon(
                      onPressed: _isBusy ? null : _stop,
                      icon: _busyIcon(Icons.stop_rounded),
                      label: Text(
                        state.mode == SleepMonitoringMode.alarmWithMission
                            ? loc.sleepMonitorProtectedStop
                            : loc.sleepMonitorFinish,
                      ),
                    )
                  : FilledButton.icon(
                      onPressed:
                          _isBusy ||
                              (_selectedMode.hasAlarm &&
                                  !SleepAlarmTime.isWithinMonitoringWindow(
                                    alarmAt!,
                                  ))
                          ? null
                          : () => _start(alarmAt),
                      icon: _busyIcon(Icons.bedtime_rounded),
                      label: Text(_startLabel(loc, alarmAt)),
                    ),
            ),
    );
  }

  List<Widget> _readyContent(
    AppLocalizations loc,
    SleepMonitorState state,
    DateTime? alarmAt,
  ) {
    final valid =
        alarmAt == null || SleepAlarmTime.isWithinMonitoringWindow(alarmAt);
    return [
      _NightHero(
        icon: Icons.nightlight_round,
        title: loc.sleepMonitorReady,
        subtitle: loc.sleepAlarmSectionTitle,
      ),
      const SizedBox(height: 16),
      _buildModeSelector(loc),
      if (alarmAt != null) ...[
        const SizedBox(height: 16),
        _AlarmClockCard(
          time: _formatTime(alarmAt),
          date: _formatDate(alarmAt),
          remaining: loc.sleepAlarmIn(_formatRemaining(alarmAt)),
          helper: loc.sleepAlarmTapToChange,
          onTap: _chooseAlarmTime,
        ),
      ],
      if (!valid) ...[
        const SizedBox(height: 10),
        _WarningBanner(
          icon: Icons.schedule_rounded,
          text: loc.sleepAlarmInvalidWindow,
        ),
      ],
      if (_selectedMode.hasAlarm) ...[
        const SizedBox(height: 14),
        _InfoCard(
          icon: Icons.notifications_active_outlined,
          title: loc.sleepAlarmSystemSound,
          body: loc.sleepAlarmSystemSoundBody,
        ),
        const SizedBox(height: 10),
        _InfoCard(
          icon: Icons.battery_charging_full_rounded,
          title: loc.sleepAlarmPreparation,
          body: loc.sleepAlarmPreparationBody,
        ),
      ],
      if (_selectedMode.hasAlarm && !state.exactAlarmGranted) ...[
        const SizedBox(height: 10),
        _PermissionNotice(
          text: loc.sleepAlarmExactPermission,
          action: loc.sleepAlarmEnableExactPermission,
          onPressed: _service.requestExactAlarmPermission,
        ),
      ],
      if (_selectedMode.hasAlarm &&
          state.exactAlarmGranted &&
          !state.fullScreenIntentGranted) ...[
        const SizedBox(height: 10),
        _PermissionNotice(
          text: loc.sleepAlarmFullScreenLimited,
          action: loc.sleepAlarmEnableFullScreen,
          onPressed: _service.requestFullScreenPermission,
        ),
      ],
      const SizedBox(height: 14),
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer.withAlpha(190),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.privacy_tip_outlined),
              const SizedBox(width: 10),
              Expanded(child: Text(loc.sleepMonitorLocalProcessing)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
      Text(
        loc.sleepMonitorEstimateWarning,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _runningContent(
    AppLocalizations loc,
    SleepMonitorState state,
    DateTime? alarmAt,
  ) {
    return [
      _NightHero(
        icon: Icons.graphic_eq_rounded,
        title: loc.sleepMonitorRunning,
        subtitle: alarmAt == null
            ? loc.sleepMonitorModeOnly
            : loc.sleepAlarmScheduledFor(_formatTime(alarmAt)),
      ),
      const SizedBox(height: 16),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            children: [
              Text(
                loc.sleepMonitorTimeMonitored,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _formatDuration(state.elapsed),
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 18),
              if (alarmAt != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm_rounded),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              loc.sleepAlarmRemaining,
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            Text(
                              _formatRemaining(alarmAt, withSeconds: true),
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _isBusy ? null : _chooseAlarmTime,
                        child: Text(loc.sleepAlarmChange),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              if (state.mode == SleepMonitoringMode.alarmWithMission)
                _MissionStatusBanner(
                  label: loc.sleepMonitorMissionPending,
                  body: loc.sleepMonitorModeAlarmWithMissionBody,
                ),
              if (state.mode == SleepMonitoringMode.alarmWithMission)
                const SizedBox(height: 12),
              _PermissionRow(
                granted: state.microphoneGranted,
                label: loc.sleepMonitorMicrophone,
              ),
              const SizedBox(height: 12),
              _LiveSignal(
                segment: state.latestSegment,
                noiseScore: state.currentNoiseScore,
                loc: loc,
              ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 12),
      if (state.mode == SleepMonitoringMode.alarmWithMission)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            loc.sleepMonitorProtectedStopBody,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      OutlinedButton.icon(
        onPressed: _isBusy ? null : _discard,
        icon: const Icon(Icons.delete_outline),
        label: Text(loc.sleepMonitorDiscard),
      ),
      if (state.errorCode != null) ...[
        const SizedBox(height: 14),
        Text(
          _localizedError(loc, state.errorCode),
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      ],
    ];
  }

  Widget _busyIcon(IconData fallback) => _isBusy
      ? const SizedBox.square(
          dimension: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        )
      : Icon(fallback);

  Future<void> _chooseAlarmTime() async {
    if (!_selectedMode.hasAlarm && !_service.state.mode.hasAlarm) return;
    final stateAlarm = _service.state.alarmAt?.toLocal();
    final initial = stateAlarm == null
        ? _selectedTime
        : TimeOfDay(hour: stateAlarm.hour, minute: stateAlarm.minute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      initialEntryMode: TimePickerEntryMode.dial,
    );
    if (picked == null || !mounted) return;
    final alarmAt = SleepAlarmTime.nextOccurrence(picked);
    if (!SleepAlarmTime.isWithinMonitoringWindow(alarmAt)) {
      _showMessage(AppLocalizations.of(context)!.sleepAlarmInvalidWindow);
      return;
    }
    if (_service.isMonitoring) {
      setState(() => _isBusy = true);
      final updated = await _service.updateAlarm(alarmAt);
      if (!updated && mounted) {
        _showMessage(
          _localizedError(
            AppLocalizations.of(context)!,
            _service.state.errorCode,
          ),
        );
      }
      if (mounted) setState(() => _isBusy = false);
    } else {
      setState(() => _selectedTime = picked);
    }
  }

  Future<void> _start(DateTime? alarmAt) async {
    final loc = AppLocalizations.of(context)!;
    if (_selectedMode.hasAlarm &&
        (alarmAt == null ||
            !SleepAlarmTime.isWithinMonitoringWindow(alarmAt))) {
      _showMessage(loc.sleepAlarmInvalidWindow);
      return;
    }
    setState(() => _isBusy = true);
    try {
      var granted = _service.state.microphoneGranted;
      if (!granted) granted = await _service.requestMicrophonePermission();
      if (!granted) {
        _showMessage(loc.sleepMonitorMicrophoneDenied);
        return;
      }

      final notificationsGranted = await NotificationService.instance
          .requestPermission();
      if (!notificationsGranted) {
        _showMessage(loc.sleepAlarmNotificationRequired);
        return;
      }

      if (_selectedMode.hasAlarm) {
        final capabilities = await _service.getAlarmCapabilities();
        if (capabilities['exactAlarmGranted'] != true) {
          await _service.requestExactAlarmPermission();
          if (mounted) _showMessage(loc.sleepAlarmExactPermission);
          return;
        }
      }

      if (_selectedMode.requiresMission) {
        if (!_missions.config.isReady) {
          _showMessage(loc.sleepMonitorModeMissionUnavailable);
          return;
        }
      }

      final started = await _service.startMonitoring(
        alarmAt: alarmAt,
        mode: _selectedMode,
        mission: _missions.config,
      );
      if (!started && mounted) {
        _showMessage(_localizedError(loc, _service.state.errorCode));
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _stop() async {
    final sessionId = _service.state.sessionId;
    setState(() => _isBusy = true);
    try {
      await _service.stopMonitoring();
      if (!mounted || sessionId == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SleepMonitorResultScreen(sessionId: sessionId),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _discard() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.sleepMonitorDiscardTitle),
        content: Text(loc.sleepMonitorDiscardBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.commonDiscard),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _isBusy = true);
    await _service.discardSession();
    if (mounted) setState(() => _isBusy = false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _localizedError(AppLocalizations loc, String? code) {
    switch (code) {
      case 'microphone_permission':
      case 'microphone_denied':
        return loc.sleepMonitorMicrophoneDenied;
      case 'audio_unavailable':
      case 'audio_error':
      case 'no_audio_data':
        return loc.sleepMonitorAudioUnavailable;
      case 'already_active':
        return loc.sleepMonitorAlreadyActive;
      case 'import_failed':
      case 'recovery_failed':
        return loc.sleepMonitorImportError;
      case 'exact_alarm_denied':
        return loc.sleepAlarmExactPermission;
      case 'invalid_alarm_time':
        return loc.sleepAlarmInvalidWindow;
      case 'alarm_not_configured':
        return loc.sleepMonitorModeOnlyBody;
      case 'alarm_schedule_failed':
        return loc.sleepAlarmScheduleFailed;
      case 'mission_not_configured':
        return loc.sleepMonitorModeMissionUnavailable;
      case 'camera_denied':
      case 'camera_permission':
        return loc.sleepMissionCameraDenied;
      default:
        return loc.sleepMonitorGenericError;
    }
  }

  String _startLabel(AppLocalizations loc, DateTime? alarmAt) {
    if (_selectedMode == SleepMonitoringMode.monitoringOnly) {
      return loc.sleepMonitorStartOnly;
    }
    if (_selectedMode == SleepMonitoringMode.alarmWithMission) {
      return loc.sleepMonitorStartWithMission(_formatTime(alarmAt!));
    }
    return loc.sleepMonitorStartWithAlarm(_formatTime(alarmAt!));
  }

  Widget _buildModeSelector(AppLocalizations loc) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.sleepMonitorModeSection,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          selected: _selectedMode == SleepMonitoringMode.alarmWithoutMission,
          icon: Icons.alarm_outlined,
          title: loc.sleepMonitorModeAlarmNoMission,
          body: loc.sleepMonitorModeAlarmNoMissionBody,
          onTap: () => _selectMode(SleepMonitoringMode.alarmWithoutMission),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          selected: _selectedMode == SleepMonitoringMode.alarmWithMission,
          enabled: _missions.config.isReady,
          icon: Icons.qr_code_2_rounded,
          title: loc.sleepMonitorModeAlarmWithMission,
          body: _missions.config.isReady
              ? loc.sleepMonitorModeAlarmWithMissionBody
              : loc.sleepMonitorModeMissionUnavailable,
          onTap: _missions.config.isReady
              ? () => _selectMode(SleepMonitoringMode.alarmWithMission)
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SleepSettingsScreen(),
                  ),
                ).then((_) => _reloadMission()),
        ),
        const SizedBox(height: 8),
        _ModeCard(
          selected: _selectedMode == SleepMonitoringMode.monitoringOnly,
          icon: Icons.graphic_eq_rounded,
          title: loc.sleepMonitorModeOnly,
          body: loc.sleepMonitorModeOnlyBody,
          onTap: () => _selectMode(SleepMonitoringMode.monitoringOnly),
        ),
      ],
    );
  }

  Future<void> _selectMode(SleepMonitoringMode mode) async {
    setState(() => _selectedMode = mode);
    await _missions.setLastMode(mode);
  }

  String _formatTime(DateTime date) => MaterialLocalizations.of(
    context,
  ).formatTimeOfDay(TimeOfDay.fromDateTime(date));

  String _formatDate(DateTime date) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return toBeginningOfSentenceCase(
          DateFormat('EEEE, d MMM', locale).format(date),
        ) ??
        '';
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  static String _formatRemaining(DateTime alarmAt, {bool withSeconds = false}) {
    final duration = alarmAt.difference(DateTime.now());
    final safe = duration.isNegative ? Duration.zero : duration;
    final hours = safe.inHours;
    final minutes = safe.inMinutes.remainder(60);
    if (!withSeconds) return '${hours}h ${minutes}min';
    final seconds = safe.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.body,
    required this.onTap,
    this.enabled = true,
  });

  final bool selected;
  final bool enabled;
  final IconData icon;
  final String title;
  final String body;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withAlpha(enabled ? 170 : 90);
    final foreground = enabled
        ? (selected ? scheme.onPrimaryContainer : scheme.onSurface)
        : scheme.onSurfaceVariant.withAlpha(150);
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      child: InkWell(
        // A locked mission card still opens its setup screen.
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: selected ? scheme.primary : foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: foreground.withAlpha(enabled ? 210 : 150),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected ? scheme.primary : foreground,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissionStatusBanner extends StatelessWidget {
  const _MissionStatusBanner({required this.label, required this.body});
  final String label;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.qr_code_2_rounded, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: scheme.onTertiaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(body, style: TextStyle(color: scheme.onTertiaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NightBackground extends StatelessWidget {
  final Widget child;

  const _NightBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withAlpha(145),
            scheme.surface,
            scheme.surface,
          ],
          stops: const [0, 0.42, 1],
        ),
      ),
      child: child,
    );
  }
}

class _NightHero extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _NightHero({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary.withAlpha(26),
          ),
          child: Icon(icon, size: 38, color: theme.colorScheme.primary),
        ),
        const SizedBox(height: 12),
        Text(
          title,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _AlarmClockCard extends StatelessWidget {
  final String time;
  final String date;
  final String remaining;
  final String helper;
  final VoidCallback onTap;

  const _AlarmClockCard({
    required this.time,
    required this.date,
    required this.remaining,
    required this.helper,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Column(
            children: [
              Text(
                time,
                style: theme.textTheme.displayLarge?.copyWith(
                  fontWeight: FontWeight.w300,
                  color: theme.colorScheme.primary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                date,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                remaining,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.touch_app_outlined,
                    size: 17,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    helper,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.primary,
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
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionNotice extends StatelessWidget {
  final String text;
  final String action;
  final Future<bool> Function() onPressed;

  const _PermissionNotice({
    required this.text,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.alarm_off_rounded, color: scheme.onErrorContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onPressed, child: Text(action)),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final IconData icon;
  final String text;

  const _WarningBanner({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: TextStyle(color: scheme.onErrorContainer)),
          ),
        ],
      ),
    );
  }
}

class _PermissionRow extends StatelessWidget {
  final bool granted;
  final String label;

  const _PermissionRow({required this.granted, required this.label});

  @override
  Widget build(BuildContext context) {
    final color = granted ? Colors.green : Theme.of(context).colorScheme.error;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(granted ? Icons.check_circle : Icons.warning_amber, color: color),
        const SizedBox(width: 8),
        Text('$label: ${granted ? 'OK' : '—'}'),
      ],
    );
  }
}

class _LiveSignal extends StatelessWidget {
  final SleepMonitorSegment? segment;
  final double? noiseScore;
  final AppLocalizations loc;

  const _LiveSignal({
    required this.segment,
    required this.noiseScore,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final classification = segment?.classification;
    final isNoise = classification == 'noise';
    final isInvalid = classification == 'invalid';
    final color = classification == null
        ? Theme.of(context).colorScheme.outline
        : isInvalid
        ? Theme.of(context).colorScheme.error
        : isNoise
        ? Colors.orange
        : Colors.teal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            isInvalid
                ? Icons.signal_wifi_bad
                : isNoise
                ? Icons.volume_up
                : Icons.volume_off,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              classification == null
                  ? loc.sleepMonitorWaitingSignal
                  : isInvalid
                  ? loc.sleepMonitorInvalidSignal
                  : isNoise
                  ? loc.sleepMonitorNoiseNow
                  : loc.sleepMonitorQuietNow,
            ),
          ),
          if (noiseScore != null)
            Text(
              noiseScore!.toStringAsFixed(2),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
        ],
      ),
    );
  }
}
