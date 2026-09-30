import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';

import 'periodization_checkin_screen.dart';
import 'periodization_phase_editor_screen.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Weekly review followed by what the decision implies: nothing (keep
/// going), opening the phase editor (adjust) or ending the phase at the end
/// of this week (the following phases move earlier).
abstract final class PeriodizationCheckinFlow {
  /// Returns true when anything was saved.
  static Future<bool> run({
    required BuildContext context,
    required PeriodizationPlan plan,
    required PeriodizationPhase phase,
    DateTime? weekStart,
  }) async {
    final decision = await Navigator.push<PeriodizationDecision>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PeriodizationCheckinScreen(phase: phase, weekStart: weekStart),
      ),
    );
    if (decision == null || !context.mounted) return false;
    final loc = AppLocalizations.of(context)!;

    switch (decision) {
      case PeriodizationDecision.maintain:
        final monday = mondayOf(DateTime.now());
        final next = DateFormat.MMMd(
          Intl.defaultLocale,
        ).format(monday.add(const Duration(days: 7)));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(loc.periodizationNextReview(next))),
        );
      case PeriodizationDecision.adjust:
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PeriodizationPhaseEditorScreen(plan: plan, phase: phase),
          ),
        );
      case PeriodizationDecision.endPhase:
        final confirmed = await showConfirmDialog(
          context,
          title: loc.planningEndPhaseTitle,
          message: loc.planningEndPhaseBody,
          confirmLabel: loc.planningEndPhaseConfirm,
        );
        if (confirmed == true) {
          await DatabaseHelper.instance.periodizationRepo.endPhaseThisWeek(phase.id);
        }
    }
    return true;
  }
}
