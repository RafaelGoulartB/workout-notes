import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/body_measurement_repository.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/progress/body_section_charts.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';

/// Weekly average feeling (1 to 5) after workouts.
class StrengthFeelingCard extends StatelessWidget {
  final StrengthInsightsData data;

  const StrengthFeelingCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final weeks = StrengthInsightsCalculator.weeklyFeeling(
      data.workouts,
      data.today,
      count: 26,
    ).where((w) => w.value != null).toList();

    return RunInsightCard(
      icon: Icons.sentiment_satisfied_alt_outlined,
      title: loc.strengthInsightsFeelingTitle,
      subtitle: loc.strengthInsightsFeelingSubtitle,
      child: StrengthTrendChart(
        unit: '1-5',
        emptyLabel: loc.strengthInsightsFeelingEmpty,
        fixedMin: 1,
        fixedMax: 5,
        points: [
          for (final w in weeks)
            StrengthTrendPoint(
              date: w.weekStart,
              value: w.value!,
              tooltip:
                  '${loc.runStatsChartTooltipWeek(DateFormat.MMMd(locale).format(w.weekStart))}\n'
                  '${RunFormatters.decimal(w.value!, 1)} ★',
            ),
        ],
      ),
    );
  }
}

/// Average workout volume for each feeling rating.
class StrengthFeelingVolumeCard extends StatelessWidget {
  final StrengthInsightsData data;

  const StrengthFeelingVolumeCard({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final rows = StrengthInsightsCalculator.feelingVsVolume(
      data.workouts,
      data.sets,
    );
    final peak = rows.fold<double>(
      0,
      (a, r) => r.averageVolume > a ? r.averageVolume : a,
    );

    return RunInsightCard(
      icon: Icons.balance_rounded,
      title: loc.strengthInsightsFeelingVolumeTitle,
      subtitle: loc.strengthInsightsFeelingVolumeSubtitle,
      info: loc.strengthInsightsFeelingVolumeInfo,
      child: rows.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: RunInsightsNote(loc.strengthInsightsFeelingEmpty),
            )
          : Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 44,
                          child: Text(
                            '${r.rating} ★',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: LinearProgressIndicator(
                              value: peak == 0 ? 0 : r.averageVolume / peak,
                              minHeight: 10,
                              backgroundColor: colors.surfaceContainerHighest
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 84,
                          child: Text(
                            StrengthFormat.volumeWithUnit(r.averageVolume),
                            textAlign: TextAlign.end,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              fontFeatures: AppUi.tabular,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: RunInsightsNote(
                    loc.strengthInsightsSessionsCount(
                      rows.fold<int>(0, (a, r) => a + r.sessions),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

/// Body measurements and weight-vs-volume, loaded on first show.
class StrengthBodyCard extends StatefulWidget {
  const StrengthBodyCard({super.key});

  @override
  State<StrengthBodyCard> createState() => _StrengthBodyCardState();
}

class _StrengthBodyCardState extends State<StrengthBodyCard> {
  bool _loading = true;
  List<Map<String, dynamic>> _summary = const [];
  List<Map<String, dynamic>> _composition = const [];
  List<Map<String, dynamic>> _weightVolume = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final body = BodyMeasurementRepository();
      final results = await Future.wait([
        body.getBodyMeasurementsSummary(),
        body.getBodyCompositionTrend(),
        DatabaseHelper.instance.analyticsRepo.getBodyWeightWithVolume(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0];
        _composition = results[1];
        _weightVolume = results[2];
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return RunInsightCard(
      icon: Icons.monitor_weight_outlined,
      title: loc.strengthInsightsBodyTitle,
      subtitle: loc.strengthInsightsBodySubtitle,
      child: _loading
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : BodySectionCharts(
              bodySummary: _summary,
              bodyComposition: _composition,
              bodyData: _weightVolume,
            ),
    );
  }
}
