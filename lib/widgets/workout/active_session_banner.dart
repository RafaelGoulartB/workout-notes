import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:workout_notes/widgets/second_ticker.dart';

/// Banner of a session in progress on the Treino tab (gym workout, run or
/// stationary bike): a pulsing dot, a title, a live subtitle and an action.
///
/// The subtitle rebuilds on its own, so the screen hosting the banner does
/// not: [refresh] (e.g. a tracking service) and/or [tickEverySecond] (a clock)
/// drive only the subtitle text.
class ActiveSessionBanner extends StatelessWidget {
  final Color background;
  final Color foreground;
  final String title;

  /// Called on every refresh of the subtitle.
  final String Function() subtitle;

  /// Rebuilds the subtitle when it notifies.
  final Listenable? refresh;

  /// Rebuilds the subtitle every second while the banner is visible.
  final bool tickEverySecond;
  final Widget action;
  final VoidCallback onTap;
  final Duration entranceDuration;
  final Duration entranceDelay;

  const ActiveSessionBanner({
    super.key,
    required this.background,
    required this.foreground,
    required this.title,
    required this.subtitle,
    required this.action,
    required this.onTap,
    this.refresh,
    this.tickEverySecond = false,
    this.entranceDuration = const Duration(milliseconds: 300),
    this.entranceDelay = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget subtitleText() => Text(
      subtitle(),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: foreground.withAlpha(220),
      ),
    );

    Widget live = subtitleText();
    final listenable = refresh;
    if (listenable != null) {
      live = ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => subtitleText(),
      );
    }
    if (tickEverySecond) {
      final inner = live;
      live = SecondTicker(builder: (_) => inner);
    }

    return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: background,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                child: Row(
                  children: [
                    ActiveSessionDot(color: foreground),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: foreground,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 2),
                          live,
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    action,
                  ],
                ),
              ),
            ),
          ),
        )
        .animate()
        .fadeIn(duration: entranceDuration, delay: entranceDelay)
        .slideY(begin: 0.05);
  }
}

/// The pulsing "live" dot. Its animation follows [TickerMode], so it stops
/// while the tab is hidden or another page covers this one.
class ActiveSessionDot extends StatelessWidget {
  final Color color;
  const ActiveSessionDot({super.key, required this.color});

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
