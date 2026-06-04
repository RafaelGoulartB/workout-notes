import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class RestTimerScreen extends StatefulWidget {
  const RestTimerScreen({super.key});

  @override
  State<RestTimerScreen> createState() => _RestTimerScreenState();
}

class _RestTimerScreenState extends State<RestTimerScreen> with WidgetsBindingObserver {
  int _seconds = 90;
  int _remaining = 90;
  bool _isRunning = false;
  bool _isPaused = false;
  Timer? _timer;
  final TextEditingController _customController = TextEditingController();

  final List<int> _presets = [30, 60, 90, 120, 180];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _customController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _isRunning) {
      _timer?.cancel();
      // Keep time, just pause timer
      setState(() => _isPaused = true);
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() {
      _remaining = _seconds;
      _isRunning = true;
      _isPaused = false;
    });

    if (_remaining > 0) {
      HapticFeedback.mediumImpact();
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 0) {
        timer.cancel();
        setState(() {
          _isRunning = false;
          _isPaused = false;
        });
        _onTimerComplete();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _pauseTimer() {
    _timer?.cancel();
    setState(() => _isPaused = true);
  }

  void _resumeTimer() {
    setState(() => _isPaused = false);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remaining <= 0) {
        timer.cancel();
        setState(() {
          _isRunning = false;
          _isPaused = false;
        });
        _onTimerComplete();
        return;
      }
      setState(() => _remaining--);
    });
  }

  void _resetTimer() {
    _timer?.cancel();
    setState(() {
      _remaining = _seconds;
      _isRunning = false;
      _isPaused = false;
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    setState(() {
      _isRunning = false;
      _isPaused = false;
      _remaining = _seconds;
    });
  }

  void _onTimerComplete() {
    HapticFeedback.heavyImpact();
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.notifications_active, size: 64, color: Colors.green),
              const SizedBox(height: 16),
              Text('Descanso Concluído!', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text('Hora da próxima série 💪'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vamos!'),
            ),
          ],
        ),
      );
    }
  }

  void _setPreset(int seconds) {
    _stopTimer();
    setState(() {
      _seconds = seconds;
      _remaining = seconds;
    });
  }

  void _showCustomDialog() {
    _customController.text = _seconds.toString();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tempo Personalizado'),
        content: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _customController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Segundos',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _customController.text = (int.tryParse(_customController.text) ?? 0 + 30).toString(),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('+30s'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(_customController.text);
              if (v != null && v > 0) {
                _setPreset(v);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Definir'),
          ),
        ],
      ),
    );
  }

  String get _formattedTime {
    final min = _remaining ~/ 60;
    final sec = _remaining % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  double get _progress => _seconds > 0 ? _remaining / _seconds : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWarning = _remaining <= 10 && _isRunning;
    final isComplete = _remaining <= 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Temporizador'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Timer display
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
                            : theme.colorScheme.primary.withAlpha(80),
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
                        value: _progress,
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
                          _formattedTime,
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
                          _isRunning ? (_isPaused ? 'PAUSADO' : 'DESCANSANDO') : 'PRONTO',
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

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRunning && !_isPaused)
                    _ControlButton(
                      icon: Icons.pause_circle_filled,
                      label: 'Pausar',
                      color: Colors.orange,
                      onTap: _pauseTimer,
                    )
                  else if (_isPaused)
                    _ControlButton(
                      icon: Icons.play_circle_filled,
                      label: 'Continuar',
                      color: Colors.green,
                      onTap: _resumeTimer,
                    )
                  else if (!_isRunning)
                    _ControlButton(
                      icon: Icons.play_circle_filled,
                      label: 'Iniciar',
                      color: Colors.green,
                      onTap: _startTimer,
                    ),
                  const SizedBox(width: 16),
                  if (_isRunning || _isPaused)
                    _ControlButton(
                      icon: Icons.stop_circle_outlined,
                      label: 'Parar',
                      color: theme.colorScheme.error,
                      onTap: _stopTimer,
                    ),
                ],
              ),

              const SizedBox(height: 40),

              // Presets
              Text('Tempo de Descanso', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ..._presets.map((sec) => ChoiceChip(
                    label: Text(sec >= 60 ? '${sec ~/ 60}min' : '${sec}s'),
                    selected: _seconds == sec && !_isRunning,
                    onSelected: (_) => _setPreset(sec),
                  )),
                  ActionChip(
                    avatar: const Icon(Icons.edit, size: 16),
                    label: const Text('Custom'),
                    onPressed: _showCustomDialog,
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

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon, required this.label,
    required this.color, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 4),
          Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
