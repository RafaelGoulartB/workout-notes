import 'dart:async';
import 'package:flutter/material.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Night gradient behind the monitor. [dim] keeps it darker while a night is
/// being recorded.
class MonitorNightBackground extends StatelessWidget {
  final Widget child;
  final bool dim;

  const MonitorNightBackground({
    super.key,
    required this.child,
    this.dim = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.primaryContainer.withAlpha(dim ? 60 : 130),
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

class PermissionNotice extends StatelessWidget {
  final String text;
  final String action;
  final Future<bool> Function() onPressed;

  const PermissionNotice({
    super.key,
    required this.text,
    required this.action,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return AppSectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      color: scheme.errorContainer.withAlpha(70),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppIconBadge(Icons.alarm_off_rounded, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonal(
              onPressed: onPressed,
              child: Text(action),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact list of bedtime tips (icon, title and one short paragraph each).
class TipsCard extends StatelessWidget {
  final String title;
  final List<(IconData, String, String)> tips;

  const TipsCard({super.key, required this.title, required this.tips});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.primary,
            ),
          ),
          for (final tip in tips) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIconBadge(tip.$1),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tip.$2,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        tip.$3,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Muted centred line of text used around the big time and the waves.
class MonitorCaption extends StatelessWidget {
  final String text;

  /// Slightly brighter, for the value under the big time.
  final bool emphasis;

  const MonitorCaption(this.text, {super.key, this.emphasis = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Text(
      text,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style:
          (emphasis ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
              ?.copyWith(
                color: emphasis ? colors.primary : colors.onSurfaceVariant,
                fontFeatures: AppUi.tabular,
              ),
    );
  }
}

/// Large, light clock ("06:30"); tappable when [onTap] is set.
class MonitorBigTime extends StatelessWidget {
  final String time;
  final String? tooltip;
  final VoidCallback? onTap;

  const MonitorBigTime({
    super.key,
    required this.time,
    this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        time,
        maxLines: 1,
        style: theme.textTheme.displayLarge?.copyWith(
          fontSize: 76,
          fontWeight: FontWeight.w300,
          height: 1.1,
          letterSpacing: -1,
          color: theme.colorScheme.onSurface,
          fontFeatures: AppUi.tabular,
        ),
      ),
    );
    final onTap = this.onTap;
    if (onTap == null && tooltip == null) return Center(child: text);
    return Center(
      child: Tooltip(
        message: tooltip ?? '',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppUi.heroRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: text,
          ),
        ),
      ),
    );
  }
}

/// Fades the monitor down after a while without touches, so a glance at the
/// phone in the night is not a flash of light. Any touch brings it back; the
/// touch still reaches the screen.
class MonitorAutoDim extends StatefulWidget {
  final bool enabled;
  final Widget child;
  final Duration delay;

  const MonitorAutoDim({
    super.key,
    required this.enabled,
    required this.child,
    this.delay = const Duration(seconds: 20),
  });

  @override
  State<MonitorAutoDim> createState() => _MonitorAutoDimState();
}

class _MonitorAutoDimState extends State<MonitorAutoDim> {
  Timer? _timer;
  bool _dimmed = false;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void didUpdateWidget(MonitorAutoDim oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled) _wake();
  }

  void _restart() {
    _timer?.cancel();
    _timer = widget.enabled
        ? Timer(widget.delay, () {
            if (mounted) setState(() => _dimmed = true);
          })
        : null;
  }

  void _wake() {
    if (_dimmed) setState(() => _dimmed = false);
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      child: ColoredBox(
        color: Colors.black,
        child: AnimatedOpacity(
          opacity: _dimmed ? 0.3 : 1,
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeInOut,
          child: widget.child,
        ),
      ),
    );
  }
}
