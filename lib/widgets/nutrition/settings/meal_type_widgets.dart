import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/meal_type.dart';
import 'package:workout_notes/widgets/settings/settings.dart';

/// Tappable meal-type row that opens the actions sheet (rename / delete /
/// move).
class MealTypeRow extends StatelessWidget {
  final MealTypeDefinition type;
  final VoidCallback onTap;

  const MealTypeRow({super.key, required this.type, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.restaurant_outlined,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                type.displayName(loc),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.more_horiz,
              color: theme.colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet that exposes the rename / move / delete actions for a
/// meal type. Replaces the inline row of action buttons previously used
/// in this screen.
class MealActionsSheet extends StatelessWidget {
  final MealTypeDefinition type;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final String titleOverride;

  const MealActionsSheet({
    super.key,
    required this.type,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onRename,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.titleOverride,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Row(
              children: [
                Icon(
                  Icons.restaurant_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    loc.nutritionSettingsMealActionsTitle(
                      type.displayName(loc),
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                titleOverride,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          const Divider(height: 1, thickness: 1),
          SettingsActionRow(
            icon: Icons.edit_outlined,
            label: loc.nutritionSettingsMealActionRename,
            onTap: () {
              Navigator.of(context).pop();
              onRename();
            },
          ),
          SettingsActionRow(
            icon: Icons.arrow_upward,
            label: loc.nutritionSettingsMealActionMoveUp,
            enabled: canMoveUp,
            onTap: () {
              Navigator.of(context).pop();
              onMoveUp();
            },
          ),
          SettingsActionRow(
            icon: Icons.arrow_downward,
            label: loc.nutritionSettingsMealActionMoveDown,
            enabled: canMoveDown,
            onTap: () {
              Navigator.of(context).pop();
              onMoveDown();
            },
          ),
          SettingsActionRow(
            icon: Icons.delete_outline,
            label: loc.nutritionSettingsMealActionDelete,
            destructive: true,
            onTap: () {
              Navigator.of(context).pop();
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

/// Dialog for typing a meal type name. Owns its [TextEditingController]
/// so it is disposed only when the route is fully unmounted — disposing
/// it right after `showDialog` returns would run while the exit
/// animation still has the field attached and crash with a framework
/// assertion.
class MealTypeNameDialog extends StatefulWidget {
  final String title;
  final String? initial;

  const MealTypeNameDialog({super.key, required this.title, this.initial});

  @override
  State<MealTypeNameDialog> createState() => _MealTypeNameDialogState();
}

class _MealTypeNameDialogState extends State<MealTypeNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.of(context).pop(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(widget.title),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          decoration: InputDecoration(
            labelText: loc.nutritionMealName,
            hintText: loc.nutritionMealNameHint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
          textInputAction: TextInputAction.done,
          validator: (value) => (value == null || value.trim().isEmpty)
              ? loc.nutritionMealNameRequired
              : null,
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(loc.nutritionCancel),
        ),
        FilledButton(onPressed: _submit, child: Text(loc.nutritionSave)),
      ],
    );
  }
}
