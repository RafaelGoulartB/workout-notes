import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:life_notes/l10n/app_localizations.dart';
import '../models/note.dart';

class NoteEditorScreen extends StatefulWidget {
  final Note? existingNote;

  const NoteEditorScreen({super.key, this.existingNote});

  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _titleController = TextEditingController();
  final _contentController = TextEditingController();
  final _uuid = const Uuid();
  bool _hasChanges = false;

  bool get _isEditing => widget.existingNote != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      _titleController.text = widget.existingNote!.title;
      _contentController.text = widget.existingNote!.content;
    }
    _titleController.addListener(_onChanged);
    _contentController.addListener(_onChanged);
  }

  void _onChanged() {
    if (!_hasChanges) {
      setState(() => _hasChanges = true);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  void _save() {
    final title = _titleController.text.trim();
    final content = _contentController.text.trim();

    if (title.isEmpty && content.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.noteEditorEmptyError)),
      );
      return;
    }

    final now = DateTime.now();
    final note = Note(
      id: _isEditing ? widget.existingNote!.id : _uuid.v4(),
      title: title,
      content: content,
      createdAt: _isEditing ? widget.existingNote!.createdAt : now,
      updatedAt: now,
    );

    Navigator.pop(context, note);
  }

  void _discard() {
    if (_hasChanges) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppLocalizations.of(context)!.noteEditorDiscardTitle),
          content: Text(AppLocalizations.of(context)!.noteEditorDiscardContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(AppLocalizations.of(context)!.noteEditorKeepEditing),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(AppLocalizations.of(context)!.noteEditorDiscard),
            ),
          ],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _discard();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isEditing ? AppLocalizations.of(context)!.noteEditorTitleEdit : AppLocalizations.of(context)!.noteEditorTitleNew),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _discard,
          ),
          actions: [
            TextButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.check),
              label: Text(AppLocalizations.of(context)!.noteEditorSave),
            ),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                decoration: InputDecoration(
                  hintText: AppLocalizations.of(context)!.noteEditorHintTitle,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                  isDense: true,
                ),
                maxLines: 1,
                textCapitalization: TextCapitalization.sentences,
              ),
              const Divider(),
              Expanded(
                child: TextField(
                  controller: _contentController,
                  style: Theme.of(context).textTheme.bodyLarge,
                  decoration: InputDecoration(
                    hintText: AppLocalizations.of(context)!.noteEditorHintContent,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                  ),
                  maxLines: null,
                  expands: true,
                  textAlignVertical: TextAlignVertical.top,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
