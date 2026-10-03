import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

/// Editor of the user's custom instructions (tone, focus, preferences added
/// on top of the coach's own rules). Save is enabled only when the trimmed
/// text differs from what is stored.
class AiCustomInstructionsSheet extends StatefulWidget {
  final AiSettingsNotifier notifier;

  const AiCustomInstructionsSheet({super.key, required this.notifier});

  @override
  State<AiCustomInstructionsSheet> createState() =>
      _AiCustomInstructionsSheetState();
}

class _AiCustomInstructionsSheetState extends State<AiCustomInstructionsSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.notifier.customInstructions,
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Compared by text, not by controller notifications: moving the cursor or
  /// typing and deleting the same character is not a change.
  bool get _dirty =>
      _controller.text.trim() != widget.notifier.customInstructions;

  Future<void> _save(String value) async {
    setState(() => _saving = true);
    await widget.notifier.setCustomInstructions(value);
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(SnackBar(content: Text(l10n.aiSettingsSaved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return FractionallySizedBox(
      heightFactor: .8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.aiSettingsCustomInstructions,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.aiSettingsCustomInstructionsHelp,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                maxLength: kMaxAiCustomInstructionsChars,
                textAlignVertical: TextAlignVertical.top,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  alignLabelWithHint: true,
                  hintText: l10n.aiSettingsCustomInstructionsHint,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.notifier.customInstructions.isNotEmpty)
                  TextButton(
                    onPressed: _saving ? null : () => _save(''),
                    child: Text(l10n.aiSettingsCustomInstructionsClear),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  child: Text(l10n.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: !_dirty || _saving
                      ? null
                      : () => _save(_controller.text),
                  child: Text(l10n.commonSave),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
