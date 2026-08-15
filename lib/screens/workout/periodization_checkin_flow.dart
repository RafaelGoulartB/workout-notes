import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_checkin.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/models/periodization_plan.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';

import 'periodization_checkin_screen.dart';
import 'periodization_phase_form_screen.dart';

abstract final class PeriodizationCheckinFlow {
  static Future<bool> run({
    required BuildContext context,
    required PeriodizationPlan plan,
    required PeriodizationPhase phase,
  }) async {
    final decision = await Navigator.push<PeriodizationDecision>(
      context,
      MaterialPageRoute(
        builder: (_) => PeriodizationCheckinScreen(phase: phase),
      ),
    );
    if (decision == null || !context.mounted) return false;

    switch (decision) {
      case PeriodizationDecision.maintain:
        final today = DateTime.now();
        final weekStart = DateTime(
          today.year,
          today.month,
          today.day,
        ).subtract(Duration(days: today.weekday - DateTime.monday));
        final nextReview = weekStart.add(const Duration(days: 7));
        final date = DateFormat.MMMd(Intl.defaultLocale).format(nextReview);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(context)!.periodizationNextReview(date),
            ),
          ),
        );
        return true;
      case PeriodizationDecision.adjust:
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                PeriodizationPhaseFormScreen(plan: plan, phase: phase),
          ),
        );
        return true;
      case PeriodizationDecision.endPhase:
        final action = await _confirmEarlyEnd(context);
        if (action == null || !context.mounted) return true;
        try {
          await PeriodizationRepository().endPhaseEarly(
            phase.id,
            DateTime.now(),
            shiftFollowingPhases: action,
          );
        } catch (error) {
          if (!context.mounted) return true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.periodizationSaveError('$error'),
              ),
            ),
          );
        }
        return true;
    }
  }

  static Future<bool?> _confirmEarlyEnd(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.periodizationEndPhaseConfirmTitle),
        content: Text(loc.periodizationEndPhaseConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(loc.periodizationKeepFollowingDates),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(loc.periodizationShiftFollowing),
          ),
        ],
      ),
    );
  }
}
