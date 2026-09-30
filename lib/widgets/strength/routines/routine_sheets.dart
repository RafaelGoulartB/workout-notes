import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Name (and optional description) typed in [showRoutineDetailsSheet].
class RoutineDetails {
  final String name;
  final String notes;

  const RoutineDetails({required this.name, required this.notes});
}

/// Bottom sheet that collects a name and, optionally, a description. Used for
/// creating / renaming routines and routine days so the screens do not carry
/// their own dialogs.
Future<RoutineDetails?> showRoutineDetailsSheet(
  BuildContext context, {
  required String title,
  required String nameLabel,
  required String submitLabel,
  String? nameHint,
  String initialName = '',
  bool withNotes = false,
  String initialNotes = '',
  String? notesLabel,
  String? notesHint,
}) {
  return showModalBottomSheet<RoutineDetails>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (ctx) => _RoutineDetailsSheet(
      title: title,
      nameLabel: nameLabel,
      nameHint: nameHint,
      submitLabel: submitLabel,
      initialName: initialName,
      withNotes: withNotes,
      initialNotes: initialNotes,
      notesLabel: notesLabel,
      notesHint: notesHint,
    ),
  );
}

class _RoutineDetailsSheet extends StatefulWidget {
  final String title;
  final String nameLabel;
  final String? nameHint;
  final String submitLabel;
  final String initialName;
  final bool withNotes;
  final String initialNotes;
  final String? notesLabel;
  final String? notesHint;

  const _RoutineDetailsSheet({
    required this.title,
    required this.nameLabel,
    required this.nameHint,
    required this.submitLabel,
    required this.initialName,
    required this.withNotes,
    required this.initialNotes,
    required this.notesLabel,
    required this.notesHint,
  });

  @override
  State<_RoutineDetailsSheet> createState() => _RoutineDetailsSheetState();
}

class _RoutineDetailsSheetState extends State<_RoutineDetailsSheet> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initialName,
  );
  late final TextEditingController _notes = TextEditingController(
    text: widget.initialNotes,
  );

  @override
  void dispose() {
    _name.dispose();
    _notes.dispose();
    super.dispose();
  }

  bool get _canSubmit => _name.text.trim().isNotEmpty;

  void _submit() {
    if (!_canSubmit) return;
    Navigator.pop(
      context,
      RoutineDetails(name: _name.text.trim(), notes: _notes.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              textInputAction: widget.withNotes
                  ? TextInputAction.next
                  : TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: widget.withNotes ? null : (_) => _submit(),
              decoration: InputDecoration(
                labelText: widget.nameLabel,
                hintText: widget.nameHint,
                border: const OutlineInputBorder(),
              ),
            ),
            if (widget.withNotes) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _notes,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: widget.notesLabel,
                  hintText: widget.notesHint,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(loc.commonCancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: _canSubmit ? _submit : null,
                    child: Text(widget.submitLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog for destructive actions; true when confirmed.
Future<bool> confirmRoutineDestructive(
  BuildContext context, {
  required String title,
  required String content,
  String? confirmLabel,
}) async {
  final loc = AppLocalizations.of(context)!;
  final result = await showConfirmDialog(
    context,
    title: title,
    message: content,
    confirmLabel: confirmLabel ?? loc.commonDelete,
    destructive: true,
  );
  return result == true;
}
