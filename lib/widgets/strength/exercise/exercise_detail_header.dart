import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/strength/exercise/exercise_equipment_label.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Muscle group, equipment and notes of the exercise.
class ExerciseDetailHeader extends StatelessWidget {
  final String name;
  final String categoryName;
  final Color categoryColor;
  final String? equipment;
  final String? notes;
  final int sessions;

  const ExerciseDetailHeader({
    super.key,
    required this.name,
    required this.categoryName,
    required this.categoryColor,
    required this.equipment,
    required this.notes,
    required this.sessions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final equipmentLabel = (equipment ?? '').trim().isEmpty
        ? null
        : exerciseEquipmentLabel(loc, equipment!);

    return AppHeroCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIconBadge(
            Icons.fitness_center_rounded,
            color: categoryColor,
            size: 44,
            iconSize: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    AppPill(label: categoryName, color: categoryColor),
                    if (equipmentLabel != null)
                      AppPill(
                        label: equipmentLabel,
                        icon: Icons.build_outlined,
                        color: colors.onSurfaceVariant,
                      ),
                    if (sessions > 0)
                      AppPill(
                        label: loc.exerciseDetailSessionsSubtitle(sessions),
                        icon: Icons.history_rounded,
                        color: colors.onSurfaceVariant,
                      ),
                  ],
                ),
                if (notes != null && notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    notes!.trim(),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Best estimated 1RM, heaviest weight and best session volume.
class ExerciseRecordsRow extends StatelessWidget {
  final StrengthRecord? record;

  const ExerciseRecordsRow({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final date = DateFormat('dd/MM/yy');
    final r = record;

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: r == null
          ? Center(
              child: Text(
                loc.exerciseDetailNoRecords,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppStatRow(
                  children: [
                    AppStatTile(
                      icon: Icons.emoji_events_rounded,
                      color: Theme.of(context).colorScheme.tertiary,
                      label: loc.exerciseDetailBestE1rm,
                      value: r.bestE1rm == null
                          ? '--'
                          : StrengthFormat.weight(r.bestE1rm!),
                      unit: r.bestE1rm == null ? null : 'kg',
                    ),
                    AppStatTile(
                      label: loc.exerciseDetailMaxWeightShort,
                      value: StrengthFormat.weight(r.maxWeight),
                      unit: 'kg',
                    ),
                    AppStatTile(
                      label: loc.exerciseDetailBestVolume,
                      value: StrengthFormat.volume(r.bestSessionVolume),
                      unit: StrengthFormat.volumeUnit(r.bestSessionVolume),
                    ),
                  ],
                ),
                if (r.bestE1rm != null) ...[
                  const SizedBox(height: 10),
                  Center(
                    child: Text(
                      '${StrengthFormat.weight(r.bestE1rmWeight!)} kg × ${r.bestE1rmReps} · ${date.format(r.bestE1rmDate!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
