import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/services/run_export_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_achievements_section.dart';
import 'package:workout_notes/widgets/run/run_detail_widgets.dart';
import 'package:workout_notes/widgets/run/run_medal_badge.dart';
import 'package:workout_notes/widgets/run/run_route_sketch.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Fixed-size (4:5) poster of a run for social sharing: route sketch,
/// distance, time, pace, elevation, medals and the app name. Always dark so
/// it looks the same whatever the app theme is.
class RunShareCard extends StatelessWidget {
  static const double width = 360;
  static const double height = 450;

  final RunActivity activity;
  final List<RunAchievementPlacement> medals;

  const RunShareCard({
    super.key,
    required this.activity,
    this.medals = const [],
  });

  static const Color _ink = Color(0xFF0E1419);
  static const Color _inkSoft = Color(0xFF1B2731);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final accent = Theme.of(context).colorScheme.primary;
    final accentSoft = Color.lerp(accent, Colors.white, 0.35)!;
    final locale = Localizations.localeOf(context).toString();
    final title = activity.title?.trim().isNotEmpty == true
        ? activity.title!.trim()
        : runDefaultTitle(loc, activity);
    final date = DateFormat.yMMMEd(locale).format(activity.startedAt.toLocal());
    final route = RunRouteSketch.parse(activity.polylineSummary);
    final hasRoute = RunRouteSketch.hasShape(route);
    final elevation = activity.isRun ? activity.elevationGainMeters : null;
    final moving = activity.movingTimeSeconds > 0
        ? activity.movingTimeSeconds
        : activity.durationSeconds;

    const white = Colors.white;
    final white70 = Colors.white.withValues(alpha: 0.7);

    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.alphaBlend(accent.withValues(alpha: 0.28), _ink),
              _inkSoft,
              _ink,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 26, 26, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.directions_run_rounded,
                    size: 18,
                    color: accentSoft,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    loc.appTitle.toUpperCase(),
                    style: TextStyle(
                      color: accentSoft,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      date,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: TextStyle(color: white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Expanded(
                child: Center(
                  child: hasRoute
                      ? RunRouteSketch(
                          points: route,
                          width: 300,
                          height: 170,
                          color: accentSoft,
                          endColor: Colors.white,
                          strokeWidth: 4,
                        )
                      : Icon(
                          activity.isStationaryBike
                              ? Icons.pedal_bike_rounded
                              : Icons.directions_run_rounded,
                          size: 84,
                          color: accentSoft.withValues(alpha: 0.5),
                        ),
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    RunFormatters.distanceKm(activity.distanceMeters),
                    style: const TextStyle(
                      color: white,
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      height: 1,
                      letterSpacing: -1.5,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'km',
                    style: TextStyle(
                      color: white70,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _CardStat(
                    label: loc.runReviewTime,
                    value: RunFormatters.duration(moving),
                  ),
                  if (activity.isStationaryBike)
                    _CardStat(
                      label: loc.stationaryBikeAverageSpeed,
                      value:
                          '${RunFormatters.speedKmh(activity.averageSpeedKmh)} '
                          '${loc.stationaryBikeSpeedUnit}',
                    )
                  else
                    _CardStat(
                      label: loc.runDetailAvgPace,
                      value:
                          '${RunFormatters.paceShort(activity.avgPaceSecPerKm)}'
                          ' /km',
                    ),
                  if (elevation != null)
                    _CardStat(
                      label: loc.runDetailElevation,
                      value: '+${elevation.round()} m',
                    )
                  else if ((activity.calories ?? 0) > 0)
                    _CardStat(
                      label: loc.runDetailCalories,
                      value: '${activity.calories} kcal',
                    ),
                ],
              ),
              if (medals.isNotEmpty) ...[
                const SizedBox(height: 14),
                RunMedalBadgeRow(
                  placements: medals,
                  maxVisible: 3,
                  labelFor: (kind) => runAchievementKindShortLabel(loc, kind),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _CardStat extends StatelessWidget {
  final String label;
  final String value;

  const _CardStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet with a live preview of the [RunShareCard] and a share button.
Future<void> showRunShareSheet(
  BuildContext context, {
  required RunActivity activity,
  List<RunAchievementPlacement> medals = const [],
  RunExportService? exportService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _ShareSheet(
      activity: activity,
      medals: medals,
      exportService: exportService ?? RunExportService(),
    ),
  );
}

class _ShareSheet extends StatefulWidget {
  final RunActivity activity;
  final List<RunAchievementPlacement> medals;
  final RunExportService exportService;

  const _ShareSheet({
    required this.activity,
    required this.medals,
    required this.exportService,
  });

  @override
  State<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends State<_ShareSheet> {
  final _boundaryKey = GlobalKey();
  bool _busy = false;

  Future<void> _share() async {
    if (_busy) return;
    final loc = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final png = await RunExportService.capturePng(_boundaryKey);
      if (png == null) throw StateError('capture_failed');
      await widget.exportService.sharePng(activity: widget.activity, png: png);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(loc.runShareError)));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.runShareTitle,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.6,
              ),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: FittedBox(
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: RunShareCard(
                        activity: widget.activity,
                        medals: widget.medals,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _share,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(loc.runShareSend),
            ),
          ],
        ),
      ),
    );
  }
}
