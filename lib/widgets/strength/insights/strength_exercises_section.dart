import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_calculator.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/strength/insights/strength_charts.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Every exercise trained with its estimated-1RM sparkline, best mark, last
/// session and count; searchable and filterable by muscle group.
class StrengthExercisesSection extends StatefulWidget {
  final StrengthInsightsData data;

  const StrengthExercisesSection({super.key, required this.data});

  @override
  State<StrengthExercisesSection> createState() =>
      _StrengthExercisesSectionState();
}

class _StrengthExercisesSectionState extends State<StrengthExercisesSection> {
  static const _pageSize = 25;

  late List<StrengthExerciseSummary> _all;
  final _search = TextEditingController();
  String _query = '';
  String? _categoryId;
  int _shown = _pageSize;

  @override
  void initState() {
    super.initState();
    _all = StrengthInsightsCalculator.exerciseSummaries(widget.data.sets);
  }

  @override
  void didUpdateWidget(StrengthExercisesSection old) {
    super.didUpdateWidget(old);
    if (old.data != widget.data) {
      _all = StrengthInsightsCalculator.exerciseSummaries(widget.data.sets);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<StrengthExerciseSummary> _filtered(AppLocalizations loc) {
    final q = _query.trim().toLowerCase();
    return [
      for (final e in _all)
        if ((_categoryId == null || e.categoryId == _categoryId) &&
            (q.isEmpty ||
                ExerciseLocaleHelper.exerciseName(
                  loc,
                  e.exerciseRow,
                ).toLowerCase().contains(q)))
          e,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final data = widget.data;
    final list = _filtered(loc);
    final visible = list.take(_shown).toList();

    return RunInsightCard(
      icon: Icons.show_chart_rounded,
      title: loc.strengthInsightsExercisesTitle,
      subtitle: loc.strengthInsightsExercisesSubtitle,
      info: loc.strengthInsightsExercisesInfo,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _search,
            decoration: InputDecoration(
              hintText: loc.strengthInsightsExercisesSearch,
              prefixIcon: const Icon(Icons.search_rounded),
              isDense: true,
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                        _shown = _pageSize;
                      }),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppUi.tileRadius),
              ),
            ),
            onChanged: (v) => setState(() {
              _query = v;
              _shown = _pageSize;
            }),
          ),
          if (data.categories.length > 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  ChoiceChip(
                    label: Text(loc.strengthInsightsExercisesAll),
                    showCheckmark: false,
                    selected: _categoryId == null,
                    onSelected: (_) => setState(() {
                      _categoryId = null;
                      _shown = _pageSize;
                    }),
                  ),
                  for (final c in data.categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(strengthCategoryLabel(loc, c)),
                      showCheckmark: false,
                      selected: _categoryId == c['id'],
                      onSelected: (_) => setState(() {
                        _categoryId = c['id'] as String;
                        _shown = _pageSize;
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: RunInsightsNote(loc.strengthInsightsExercisesEmpty),
              ),
            )
          else
            AppDividedList(
              children: [
                for (final e in visible)
                  _ExerciseRow(
                    summary: e,
                    color: data.categoryColor(e.categoryId),
                    locale: locale,
                  ),
              ],
            ),
          if (list.length > visible.length)
            Align(
              alignment: Alignment.center,
              child: TextButton(
                onPressed: () => setState(() => _shown += _pageSize),
                child: Text(loc.strengthInsightsShowMore),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final StrengthExerciseSummary summary;
  final Color color;
  final String locale;

  const _ExerciseRow({
    required this.summary,
    required this.color,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final name = ExerciseLocaleHelper.exerciseName(loc, summary.exerciseRow);
    final trend = summary.trendPercent;
    final now = DateTime.now();
    final date = summary.lastDate.year == now.year
        ? DateFormat.MMMd(locale).format(summary.lastDate)
        : DateFormat.yMMMd(locale).format(summary.lastDate);
    final hasE1rm = summary.bestE1rm != null;

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => openStrengthExercise(
        context,
        exerciseId: summary.exerciseId,
        exerciseRow: summary.exerciseRow,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 38,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loc.strengthInsightsExerciseMeta(summary.sessions, date),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (summary.e1rmSeries.isNotEmpty) ...[
              const SizedBox(width: 8),
              StrengthSparkline(
                values: summary.e1rmSeries,
                color: trend != null && trend < 0
                    ? colors.error
                    : colors.primary,
              ),
            ],
            const SizedBox(width: 10),
            SizedBox(
              width: 64,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    hasE1rm
                        ? '${StrengthFormat.weight(summary.bestE1rm!)} kg'
                        : loc.strengthInsightsRepsValue(summary.maxReps),
                    maxLines: 1,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                  Text(
                    hasE1rm
                        ? (trend == null
                              ? loc.strengthInsightsBestE1rm
                              : '${trend > 0 ? '+' : ''}${RunFormatters.decimal(trend, 0)}%')
                        : loc.strengthInsightsBestReps,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: trend == null
                          ? colors.onSurfaceVariant
                          : trend >= 0
                          ? colors.primary
                          : colors.error,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
