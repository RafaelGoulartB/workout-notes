import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_gear.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Tappable "shoes used" row: name and total mileage, or a prompt when no
/// shoes are set. Shared by the run detail and the post-run review.
class RunGearRow extends StatelessWidget {
  final RunGearUsage? usage;
  final VoidCallback onTap;

  const RunGearRow({super.key, required this.usage, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final usage = this.usage;
    final warning = usage == null
        ? null
        : usage.needsReplacement
        ? loc.runGearReplaceNow
        : usage.nearingReplacement
        ? loc.runGearReplaceSoon
        : null;
    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: RunListRow(
        leading: RunIconBadge(
          Icons.directions_walk_rounded,
          color: usage == null ? colors.onSurfaceVariant : colors.primary,
        ),
        title: usage?.gear.name ?? loc.runDetailGearEmpty,
        subtitle: usage == null
            ? null
            : loc.runDetailGearTotal(
                RunFormatters.distanceWithUnit(usage.totalDistanceMeters),
              ),
        titleTrailing: warning == null
            ? null
            : RunPill(
                label: warning,
                color: usage!.needsReplacement ? colors.error : colors.tertiary,
              ),
        onTap: onTap,
      ),
    );
  }
}
