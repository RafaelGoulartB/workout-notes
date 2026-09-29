import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/screens/run/run_plan_customize_screen.dart';
import 'package:workout_notes/services/run_plan_templates.dart';
import 'package:workout_notes/widgets/run/plans/run_plan_template_picker.dart';

/// Picks a template (or a blank plan) and creates the plan: templates open the
/// coach wizard, blank plans only need a name. Null when cancelled.
Future<RunPlan?> startNewRunPlan(
  BuildContext context,
  RunPlanRepository repo,
) async {
  final choice = await showRunPlanTemplatePicker(context);
  if (choice == null || !context.mounted) return null;
  if (choice is RunPlanTemplate) {
    return Navigator.push<RunPlan>(
      context,
      MaterialPageRoute(
        builder: (_) => RunPlanCustomizeScreen(template: choice),
      ),
    );
  }
  final name = await promptRunPlanName(context);
  if (name == null) return null;
  return repo.createPlan(name: name);
}

/// Asks for a plan name. Null when cancelled.
Future<String?> promptRunPlanName(BuildContext context, {String initial = ''}) {
  final loc = AppLocalizations.of(context)!;
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(loc.runPlansNew),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: loc.runPlanName,
          hintText: loc.runPlanNameHint,
          border: const OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(loc.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final value = controller.text.trim();
            if (value.isEmpty) return;
            Navigator.pop(ctx, value);
          },
          child: Text(loc.commonSave),
        ),
      ],
    ),
  );
}
