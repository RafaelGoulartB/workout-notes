import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/strength/insights/strength_insights_data.dart';

/// Best marks of every exercise grouped by muscle group, with a search box.
class StrengthRecordsList extends StatefulWidget {
  final List<StrengthRecord> records;

  /// Anaerobic categories in library order (`id`, `name`, `color`...).
  final List<Map<String, dynamic>> categories;
  final void Function(StrengthRecord record) onOpen;

  const StrengthRecordsList({
    super.key,
    required this.records,
    required this.categories,
    required this.onOpen,
  });

  @override
  State<StrengthRecordsList> createState() => _StrengthRecordsListState();
}

class _StrengthRecordsListState extends State<StrengthRecordsList> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final q = _query.trim().toLowerCase();
    final matching = [
      for (final r in widget.records)
        if (q.isEmpty ||
            ExerciseLocaleHelper.exerciseName(
              loc,
              r.exerciseRow,
            ).toLowerCase().contains(q))
          r,
    ];

    final groups = <(Map<String, dynamic>?, String, List<StrengthRecord>)>[];
    final known = <String>{};
    for (final c in widget.categories) {
      final id = c['id'] as String;
      final rows = [
        for (final r in matching)
          if (r.categoryId == id) r,
      ];
      known.add(id);
      if (rows.isNotEmpty) {
        groups.add((c, strengthCategoryLabel(loc, c), rows));
      }
    }
    final orphans = [
      for (final r in matching)
        if (!known.contains(r.categoryId)) r,
    ];
    if (orphans.isNotEmpty) groups.add((null, '', orphans));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          decoration: InputDecoration(
            hintText: loc.strengthRecordsSearch,
            prefixIcon: const Icon(Icons.search_rounded),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(RunUi.tileRadius),
            ),
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: RunInsightsNote(loc.strengthRecordsNoResults)),
          ),
        for (final (category, name, rows) in groups) ...[
          if (category != null)
            RunSectionHeader(
              name,
              padding: const EdgeInsets.fromLTRB(4, 18, 0, 8),
              trailing: Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: Color((category['color'] as int?) ?? 0xFF757575),
                  shape: BoxShape.circle,
                ),
              ),
            )
          else
            const SizedBox(height: 12),
          RunSectionCard(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: RunDividedList(
              children: [
                for (final r in rows)
                  _RecordRow(record: r, onTap: () => widget.onOpen(r)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _RecordRow extends StatelessWidget {
  final StrengthRecord record;
  final VoidCallback onTap;

  const _RecordRow({required this.record, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final date = DateFormat('dd/MM/yy');
    final r = record;

    Widget metric(String label, String value, String caption) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
                fontFeatures: RunUi.tabular,
              ),
            ),
          ),
        ],
      ),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    ExerciseLocaleHelper.exerciseName(loc, r.exerciseRow),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                metric(
                  loc.strengthRecordsE1rm,
                  r.bestE1rm == null
                      ? '--'
                      : '${StrengthFormat.weight(r.bestE1rm!)} kg',
                  r.bestE1rm == null
                      ? ''
                      : '${StrengthFormat.weight(r.bestE1rmWeight!)} × ${r.bestE1rmReps} · ${date.format(r.bestE1rmDate!)}',
                ),
                const SizedBox(width: 8),
                metric(
                  loc.strengthRecordsMaxWeight,
                  '${StrengthFormat.weight(r.maxWeight)} kg',
                  '× ${r.maxWeightReps} · ${date.format(r.maxWeightDate)}',
                ),
                const SizedBox(width: 8),
                metric(
                  loc.strengthRecordsBestVolume,
                  StrengthFormat.volumeWithUnit(r.bestSessionVolume),
                  date.format(r.bestSessionVolumeDate),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
