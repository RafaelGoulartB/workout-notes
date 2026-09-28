import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/services/run_week_balance.dart';

/// What the athlete chose when a move unbalances the week.
enum BalanceChoice { swap, better, anyway }

/// Explains why a move unbalances the week and offers the fixes a coach
/// would: swap with the session on that day, move to the nearest balanced
/// day, or keep the move. Null when cancelled.
Future<BalanceChoice?> showBalanceDialog(
  BuildContext context, {
  required RunMoveAdvice advice,
  required String Function(String sessionId) nameOf,
  required String Function(DateTime date) dayLabel,
}) {
  final loc = AppLocalizations.of(context)!;
  return showDialog<BalanceChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.balance_outlined),
      title: Text(loc.runPlanBalanceTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final issue in advice.issues)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(switch (issue.problem) {
                RunBalanceProblem.sameDay => loc.runPlanBalanceSameDay(
                  nameOf(issue.other.id),
                ),
                RunBalanceProblem.hardBackToBack =>
                  loc.runPlanBalanceBackToBack(nameOf(issue.other.id)),
              }),
            ),
        ],
      ),
      actionsOverflowDirection: VerticalDirection.down,
      actionsOverflowButtonSpacing: 4,
      actions: [
        if (advice.swapWith != null)
          FilledButton(
            onPressed: () => Navigator.pop(ctx, BalanceChoice.swap),
            child: Text(loc.runPlanBalanceSwap(nameOf(advice.swapWith!.id))),
          ),
        if (advice.betterDate != null)
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, BalanceChoice.better),
            child: Text(loc.runPlanBalanceBetter(dayLabel(advice.betterDate!))),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, BalanceChoice.anyway),
          child: Text(loc.runPlanBalanceAnyway),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
        ),
      ],
    ),
  );
}
