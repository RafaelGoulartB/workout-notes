import 'dart:async';

import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/services/notification_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';

import 'sleep_monitor_result_screen.dart';

class SleepMonitorScreen extends StatefulWidget {
  const SleepMonitorScreen({super.key});

  @override
  State<SleepMonitorScreen> createState() => _SleepMonitorScreenState();
}

class _SleepMonitorScreenState extends State<SleepMonitorScreen>
    with WidgetsBindingObserver {
  final _service = SleepMonitorService.instance;
  Timer? _ticker;
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service.addListener(_onChanged);
    _service.initialize();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _service.isMonitoring) setState(() {});
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
    if (state == AppLifecycleState.resumed) {
      _service.initialize();
    }
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final state = _service.state;
    final active = state.isActive;
    return Scaffold(
      appBar: AppBar(title: Text(loc.sleepMonitorTitle)),
      body: !state.supported
          ? Center(child: Text(loc.sleepMonitorAndroidOnly))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        Icon(
                          active ? Icons.graphic_eq : Icons.nightlight_round,
                          size: 48,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          active
                              ? loc.sleepMonitorRunning
                              : loc.sleepMonitorReady,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _formatDuration(state.elapsed),
                          style: Theme.of(context).textTheme.displaySmall
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 14),
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
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
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
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isBusy ? null : (active ? _stop : _start),
                  icon: _isBusy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(active ? Icons.stop : Icons.mic_none),
                  label: Text(
                    active ? loc.sleepMonitorFinish : loc.sleepMonitorStart,
                  ),
                ),
                if (active) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : _discard,
                    icon: const Icon(Icons.delete_outline),
                    label: Text(loc.sleepMonitorDiscard),
                  ),
                ],
                if (state.errorCode != null) ...[
                  const SizedBox(height: 14),
                  Text(
                    _localizedError(loc, state.errorCode!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Future<void> _start() async {
    final loc = AppLocalizations.of(context)!;
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
      if (!notificationsGranted && mounted) {
        _showMessage(loc.sleepMonitorNotificationsLimited);
      }
      final started = await _service.startMonitoring();
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
        return loc.sleepMonitorAudioUnavailable;
      case 'already_active':
        return loc.sleepMonitorAlreadyActive;
      case 'import_failed':
      case 'recovery_failed':
        return loc.sleepMonitorImportError;
      default:
        return code == null
            ? loc.sleepMonitorGenericError
            : loc.sleepMonitorGenericError;
    }
  }

  static String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
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
