import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import '../../services/rest_timer_service.dart';

class RestTimerScreen extends StatefulWidget {
  const RestTimerScreen({super.key});

  @override
  State<RestTimerScreen> createState() => _RestTimerScreenState();
}

class _RestTimerScreenState extends State<RestTimerScreen> with WidgetsBindingObserver {
  final _timerService = RestTimerService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _timerService.addListener(_onTick);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerService.removeListener(_onTick);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _timerService.isRunning) {
      _timerService.pause();
    }
  }

  void _onTick() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isActive = _timerService.isActive;
    final remaining = _timerService.remainingSeconds;
    final total = _timerService.totalSeconds;
    final progress = total > 0 ? remaining / total : 0.0;
    final isWarning = remaining <= 5 && _timerService.isRunning;
    final isComplete = !_timerService.isRunning && remaining <= 0 && isActive;
    final isPaused = _timerService.isPaused;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.restTimerTitle),
        centerTitle: true,
        actions: [
          if (isActive)
            TextButton(
              onPressed: () {
                _timerService.stop();
                setState(() {});
              },
              child: Text(AppLocalizations.of(context)!.restTimerStop),
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer circle
              Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                  border: Border.all(
                    color: isComplete
                        ? Colors.green
                        : isWarning
                            ? Colors.orange
                            : _timerService.isRunning
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                    width: 4,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 260,
                      height: 260,
                      child: CircularProgressIndicator(
                        value: isActive && total > 0 ? progress : 0.0,
                        strokeWidth: 8,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation(
                          isComplete ? Colors.green : isWarning ? Colors.orange : theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          isActive ? _timerService.formattedTime : '--:--',
                          style: theme.textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 64,
                            color: isComplete
                                ? Colors.green
                                : isWarning
                                    ? Colors.orange
                                    : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isComplete
                              ? AppLocalizations.of(context)!.restTimerComplete
                              : isPaused
                                  ? AppLocalizations.of(context)!.restTimerPaused
                                  : _timerService.isRunning
                                      ? AppLocalizations.of(context)!.restTimerResting
                                      : AppLocalizations.of(context)!.restTimerReady,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            letterSpacing: 2,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: isComplete || (!_timerService.isRunning && !isActive)
                        ? null
                        : isPaused
                            ? _timerService.resume
                            : _timerService.pause,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isPaused ? Icons.play_circle_filled : Icons.pause_circle_filled,
                          size: 56,
                          color: isPaused
                              ? Colors.green
                              : (_timerService.isRunning ? Colors.orange : theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isPaused ? AppLocalizations.of(context)!.restTimerResume : AppLocalizations.of(context)!.restTimerPause,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isPaused ? Colors.green : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Preset times (only when idle)
              if (!_timerService.isActive)
                Column(
                  children: [
                    Text(AppLocalizations.of(context)!.restTimerStartRest, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [30, 60, 90, 120, 180].map((sec) => FilledButton(
                        onPressed: () {
                          _timerService.start(sec);
                          HapticFeedback.mediumImpact();
                        },
                        child: Text(sec >= 60 ? '${sec ~/ 60}min' : '${sec}s'),
                      )).toList(),
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
