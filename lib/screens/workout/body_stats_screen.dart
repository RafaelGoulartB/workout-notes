import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/body_measurement_types.dart';
import 'package:workout_notes/screens/workout/body_stats_controller.dart';
import 'package:workout_notes/widgets/body_tracker/stats/body_stats_cards.dart';
import 'package:workout_notes/widgets/body_tracker/stats/body_stats_primitives.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Progress statistics for body measurements: Sunday-to-Sunday weekly
/// averages, week-over-week comparison, rate of change, goal tracking and
/// logging consistency.
class BodyStatsScreen extends StatefulWidget {
  final String initialTypeId;

  /// Types the user chose to track on the dashboard. Falls back to every
  /// known type when empty.
  final List<MeasureType> types;

  const BodyStatsScreen({
    super.key,
    this.initialTypeId = 'weight',
    this.types = const [],
  });

  @override
  State<BodyStatsScreen> createState() => _BodyStatsScreenState();
}

class _BodyStatsScreenState extends State<BodyStatsScreen> {
  late final BodyStatsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = BodyStatsController(
      initialTypeId: widget.initialTypeId,
      types: widget.types,
    );
    _controller.load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;

    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final c = _controller;
        final analytics = c.analytics;
        final goal = c.goalProgress(analytics);

        return Scaffold(
          appBar: AppBar(title: Text(loc.bodyStatsTitle), centerTitle: true),
          body: c.loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: c.load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      BodyStatsTypeSelector(controller: c),
                      const SizedBox(height: 12),
                      BodyStatsPeriodSelector(controller: c),
                      if (analytics.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 48),
                          child: AppEmptyState(
                            icon: Icons.insights_outlined,
                            title: loc.bodyStatsEmptyTitle,
                            subtitle: loc.bodyStatsEmptySubtitle,
                          ),
                        )
                      else ...[
                        const SizedBox(height: 16),
                        BodyStatsWeekHero(controller: c, analytics: analytics),
                        BodyStatsSectionHeader(loc.bodyStatsSectionChart),
                        BodyStatsChartCard(controller: c, analytics: analytics),
                        BodyStatsSectionHeader(loc.bodyStatsSectionRate),
                        BodyStatsRateCard(controller: c, analytics: analytics),
                        if (goal != null) ...[
                          BodyStatsSectionHeader(loc.bodyStatsSectionGoal),
                          BodyStatsGoalCard(
                            controller: c,
                            analytics: analytics,
                            progress: goal,
                          ),
                        ],
                        BodyStatsSectionHeader(loc.bodyStatsSectionConsistency),
                        BodyStatsConsistencyCard(
                          controller: c,
                          analytics: analytics,
                        ),
                        if (analytics.months.length >= 2) ...[
                          BodyStatsSectionHeader(loc.bodyStatsSectionMonthly),
                          BodyStatsMonthlyCard(
                            controller: c,
                            analytics: analytics,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
        );
      },
    );
  }
}
