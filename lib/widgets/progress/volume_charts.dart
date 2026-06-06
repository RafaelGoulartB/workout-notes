import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/utils/progress_helpers.dart';

/// Displays volume section: volume by category pie, energy system mini,
/// and top exercises.
class VolumeCharts extends StatelessWidget {
  final List<Map<String, dynamic>> volumeByCategory;
  final List<Map<String, dynamic>> energySystems;
  final List<Map<String, dynamic>> topExercises;

  const VolumeCharts({
    super.key,
    required this.volumeByCategory,
    required this.energySystems,
    required this.topExercises,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Volume by category (pie) + Energy system (mini) side by side
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: _VolumeByCategoryPie(data: volumeByCategory),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child:
                  _EnergySystemMini(data: energySystems),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Top exercises
        if (topExercises.isNotEmpty) ...[
          Text(
            loc.progressTopExercises,
            style: theme.textTheme.bodySmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          _TopExercisesChart(data: topExercises),
        ],
      ],
    );
  }
}

/// Volume by category pie chart.
class _VolumeByCategoryPie extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _VolumeByCategoryPie({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (data.isEmpty) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(loc.progressNoData,
                style: theme.textTheme.bodySmall),
          ),
        ),
      );
    }

    final total =
        data.fold<double>(0, (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0));

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              loc.progressVolumeByGroup,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 10),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 150,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 1,
                        centerSpaceRadius: 20,
                        sections: data.asMap().entries.map((e) {
                          final vol =
                              (e.value['volume'] as num?)?.toDouble() ?? 0;
                          final pct =
                              total > 0 ? vol / total * 100 : 0.0;
                          return PieChartSectionData(
                            color: Color(
                                e.value['color'] as int? ?? 0xFF757575),
                            value: vol,
                            title: pct >= 8
                                ? '${pct.toStringAsFixed(0)}%'
                                : '',
                            titleStyle: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                            radius: pct >= 15 ? 32 : 26,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: data.take(5).map((cat) {
                      final vol =
                          (cat['volume'] as num?)?.toDouble() ?? 0;
                      final pct =
                          total > 0 ? vol / total * 100 : 0.0;
                      return Padding(
                        padding:
                            const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Color(cat['color'] as int? ??
                                    0xFF757575),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${ExerciseLocaleHelper.categoryName(AppLocalizations.of(context)!, cat)} ${pct.toStringAsFixed(0)}%',
                              style: TextStyle(fontSize: 8),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Energy system distribution mini pie.
class _EnergySystemMini extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _EnergySystemMini({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    if (data.isEmpty) return const SizedBox.shrink();

    final total =
        data.fold<double>(0, (a, b) => a + ((b['volume'] as num?)?.toDouble() ?? 0));
    final colors = <String, Color>{
      'aerobic': Colors.green,
      'anaerobic': Colors.red
    };
    final labels = <String, String>{
      'aerobic': loc.progressAerobic,
      'anaerobic': loc.progressAnaerobic
    };

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            Text(
              loc.progressEnergySystem,
              style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600, fontSize: 10),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 1,
                  centerSpaceRadius: 12,
                  sections: data.map((es) {
                    final system =
                        es['energy_system'] as String? ?? 'anaerobic';
                    final vol =
                        (es['volume'] as num?)?.toDouble() ?? 0;
                    final pct =
                        total > 0 ? vol / total * 100 : 0.0;
                    return PieChartSectionData(
                      color: colors[system] ?? Colors.grey,
                      value: vol,
                      title: pct > 0
                          ? '${pct.toStringAsFixed(0)}%'
                          : '',
                      titleStyle: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                      radius: 28,
                    );
                  }).toList(),
                ),
              ),
            ),
            ...data.map((es) {
              final system =
                  es['energy_system'] as String? ?? '';
              final vol =
                  (es['volume'] as num?)?.toDouble() ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: colors[system] ?? Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${labels[system] ?? system}: ${formatVolume(vol)}',
                      style: TextStyle(fontSize: 7),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Top exercises by volume chart with horizontal progress bars.
class _TopExercisesChart extends StatelessWidget {
  final List<Map<String, dynamic>> data;

  const _TopExercisesChart({required this.data});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final maxVol = data.fold<double>(0, (a, b) {
      final v = (b['volume'] as num?)?.toDouble() ?? 0;
      return a > v ? a : v;
    });

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: data.take(5).map((ex) {
            final vol = (ex['volume'] as num?)?.toDouble() ?? 0;
            final pct = maxVol > 0 ? vol / maxVol : 0.0;
            final catColor = Color(
                ex['category_color'] as int? ?? 0xFF757575);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 28,
                    decoration: BoxDecoration(
                      color: catColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 100,
                    child: Text(
                      ExerciseLocaleHelper.exerciseName(
                          AppLocalizations.of(context)!, ex),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                        color: catColor,
                        minHeight: 14,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    child: Text(
                      formatVolume(vol),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
