import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/insights/strength_exercises_section.dart';
import 'package:workout_notes/widgets/strength/insights/strength_frequency_sections.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';
import 'package:workout_notes/widgets/strength/insights/strength_volume_sections.dart';
import 'package:workout_notes/widgets/strength/insights/strength_wellness_sections.dart';

/// Which group of analysis cards is showing.
enum _InsightsTab { volume, frequency, exercises, wellness }

/// Strength analysis in four tabs, same pattern as the running analysis:
/// volume (period summary, trend, sets per muscle, goals), frequency
/// (calendar, weekly rhythm, consistency), exercises (progress of each lift)
/// and wellness (feeling and body). Computed once per load from the full
/// history of finished workouts.
class StrengthInsightsScreen extends StatefulWidget {
  const StrengthInsightsScreen({super.key});

  @override
  State<StrengthInsightsScreen> createState() => _StrengthInsightsScreenState();
}

class _StrengthInsightsScreenState extends State<StrengthInsightsScreen> {
  bool _loading = true;
  bool _failed = false;
  StrengthInsightsData? _data;
  _InsightsTab _tab = _InsightsTab.volume;
  StrengthPeriod _period = StrengthPeriod.weeks12;
  int _year = DateTime.now().year;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await StrengthInsightsData.load();
      if (!mounted) return;
      final years = StrengthInsightsCalculator.availableYears(
        data.workouts,
        data.today,
      );
      setState(() {
        _data = data;
        _failed = false;
        _loading = false;
        if (!years.contains(_year)) _year = years.first;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final data = _data;
    final showTabs = !_loading && data != null && !data.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.strengthInsightsTitle),
        bottom: showTabs
            ? PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: AppSegmentedTabs<_InsightsTab>(
                    values: _InsightsTab.values,
                    selected: _tab,
                    labelOf: (tab) => switch (tab) {
                      _InsightsTab.volume => loc.strengthInsightsTabVolume,
                      _InsightsTab.frequency =>
                        loc.strengthInsightsTabFrequency,
                      _InsightsTab.exercises =>
                        loc.strengthInsightsTabExercises,
                      _InsightsTab.wellness => loc.strengthInsightsTabWellness,
                    },
                    onChanged: (tab) => setState(() => _tab = tab),
                  ),
                ),
              )
            : null,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _failed || data == null
          ? AppEmptyState(
              icon: Icons.error_outline_rounded,
              title: loc.strengthInsightsLoadError,
              subtitle: '',
            )
          : data.isEmpty
          ? AppEmptyState(
              icon: Icons.insights_outlined,
              title: loc.strengthInsightsEmptyTitle,
              subtitle: loc.strengthInsightsEmptySubtitle,
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                key: PageStorageKey(_tab),
                padding: AppUi.screenPadding.copyWith(top: 8, bottom: 40),
                children: [
                  for (final (i, card) in _cards(data).indexed) ...[
                    if (i > 0) const SizedBox(height: 12),
                    card,
                  ],
                ],
              ),
            ),
    );
  }

  List<Widget> _cards(StrengthInsightsData data) {
    return switch (_tab) {
      _InsightsTab.volume => _volumeCards(data),
      _InsightsTab.frequency => _frequencyCards(data),
      _InsightsTab.exercises => [StrengthExercisesSection(data: data)],
      _InsightsTab.wellness => [
        StrengthFeelingCard(data: data),
        StrengthFeelingVolumeCard(data: data),
        const StrengthBodyCard(),
      ],
    };
  }

  List<Widget> _volumeCards(StrengthInsightsData data) {
    final current = StrengthInsightsCalculator.totals(
      data.sets,
      data.workouts,
      StrengthInsightsCalculator.rangeFor(_period, data.today),
    );
    final previous = StrengthInsightsCalculator.totals(
      data.sets,
      data.workouts,
      StrengthInsightsCalculator.rangeFor(_period, data.today, previous: true),
    );
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: StrengthPeriodSelector(
          selected: _period,
          onChanged: (p) => setState(() => _period = p),
        ),
      ),
      StrengthSummaryCard(
        period: _period,
        current: current,
        previous: previous,
      ),
      StrengthVolumeTrendCard(data: data, period: _period),
      StrengthMuscleLoadCard(data: data, period: _period),
      StrengthTopExercisesCard(data: data, period: _period),
      const StrengthGoalsCard(),
    ];
  }

  List<Widget> _frequencyCards(StrengthInsightsData data) {
    final years = StrengthInsightsCalculator.availableYears(
      data.workouts,
      data.today,
    );
    final dayParts = StrengthInsightsCalculator.dayPartCounts(data.workouts);
    return [
      if (years.length > 1)
        StrengthYearSelector(
          years: years,
          selected: _year,
          onChanged: (year) => setState(() => _year = year),
        ),
      StrengthHeatmapCard(
        year: _year,
        daily: StrengthInsightsCalculator.dailySets(data.sets, year: _year),
        today: data.today,
      ),
      StrengthWeeklySessionsCard(data: data),
      StrengthConsistencyCard(
        consistency: StrengthInsightsCalculator.consistency(
          data.workouts,
          data.today,
        ),
      ),
      StrengthWeekdayCard(
        counts: StrengthInsightsCalculator.weekdayCounts(data.workouts),
      ),
      StrengthDurationCard(data: data),
      if (StrengthDayPartCard.hasData(dayParts))
        StrengthDayPartCard(counts: dayParts),
    ];
  }
}
