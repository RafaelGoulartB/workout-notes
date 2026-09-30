import 'dart:async';

import 'package:flutter/widgets.dart';

/// Rebuilds only its own subtree once a second (a live clock or countdown),
/// so the screen around it never has to.
///
/// The timer runs only while the subtree is visible and the app is in the
/// foreground: [TickerMode] is off for a tab hidden in an `IndexedStack`
/// (`MainShell` disables it) and for a page covered by another route.
class SecondTicker extends StatefulWidget {
  final WidgetBuilder builder;

  const SecondTicker({super.key, required this.builder});

  @override
  State<SecondTicker> createState() => _SecondTickerState();
}

class _SecondTickerState extends State<SecondTicker>
    with WidgetsBindingObserver {
  Timer? _timer;
  bool _visible = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.valuesOf(context).enabled;
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _sync();
    // The clock is stale after a stretch in the background.
    if (foreground && mounted) setState(() {});
  }

  void _sync() {
    if (_visible && _foreground) {
      _timer ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}
