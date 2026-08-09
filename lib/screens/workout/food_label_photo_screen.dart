import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/nutrition/food.dart';
import 'package:workout_notes/models/nutrition/nutrition_selection.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/services/ai_food_label_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

import 'ai_settings_screen.dart';
import 'manual_food_screen.dart';

/// Photo flow for the nutrition module: the user takes/picks a photo
/// of a nutrition label, the AI Coach identifies the food and its
/// values, and the result is reviewed in [ManualFoodScreen] before
/// being persisted. Pops with a [NutritionSelection] on success.
class FoodLabelPhotoScreen extends StatefulWidget {
  final NutritionRepository repository;
  final AiSettingsNotifier? settings;

  const FoodLabelPhotoScreen({
    super.key,
    required this.repository,
    this.settings,
  });

  @override
  State<FoodLabelPhotoScreen> createState() => _FoodLabelPhotoScreenState();
}

class _FoodLabelPhotoScreenState extends State<FoodLabelPhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  late final AiFoodLabelService _service;
  Uint8List? _imageBytes;
  bool _isAnalyzing = false;

  @override
  void initState() {
    super.initState();
    _service = AiFoodLabelService(
      settings: widget.settings ?? WorkoutNotesApp.aiSettings,
    );
  }

  Future<void> _pick(ImageSource source) async {
    final loc = AppLocalizations.of(context)!;
    try {
      final file = await _picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() => _imageBytes = bytes);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionPhotoPickFailed)));
    }
  }

  Future<void> _analyze() async {
    final loc = AppLocalizations.of(context)!;
    final bytes = _imageBytes;
    if (bytes == null || _isAnalyzing) return;
    setState(() => _isAnalyzing = true);
    try {
      final draft = await _service.analyze(imageBytes: bytes);
      if (!mounted) return;
      final created = await Navigator.of(context).push<Food>(
        MaterialPageRoute(
          builder: (_) => ManualFoodScreen(
            repository: widget.repository,
            source: FoodSource.aiVision,
            initial: draft,
          ),
        ),
      );
      if (created == null || !mounted) return;
      final details = await widget.repository.getFoodWithDetails(created.id);
      if (!mounted) return;
      if (details == null || details.variants.isEmpty) {
        Navigator.of(context).pop();
        return;
      }
      final variant = details.variants.first;
      Navigator.of(context).pop(
        NutritionSelection(
          food: details.food,
          primaryVariant: variant,
          servings: details.servings[variant.id] ?? const [],
        ),
      );
    } on AiFoodLabelException catch (e) {
      if (!mounted) return;
      _showAnalysisError(e.code);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionPhotoError)));
    } finally {
      if (mounted) setState(() => _isAnalyzing = false);
    }
  }

  void _showAnalysisError(String code) {
    final loc = AppLocalizations.of(context)!;
    if (code == 'not_configured' || code == 'no_model') {
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(loc.nutritionPhotoNotConfigured),
          content: Text(loc.nutritionPhotoNotConfiguredBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(loc.nutritionCancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                );
              },
              child: Text(loc.nutritionPhotoOpenSettings),
            ),
          ],
        ),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          code == 'parse_failed' || code == 'no_content'
              ? loc.nutritionPhotoInvalid
              : loc.nutritionPhotoError,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(loc.nutritionPhotoTitle), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(
              loc.nutritionPhotoSelectHint,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (_imageBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _imageBytes!,
                  height: 260,
                  fit: BoxFit.cover,
                ),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.document_scanner_outlined,
                  size: 64,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isAnalyzing
                        ? null
                        : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(loc.nutritionPhotoTake),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isAnalyzing
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(loc.nutritionPhotoGallery),
                  ),
                ),
              ],
            ),
            if (_imageBytes != null) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isAnalyzing ? null : _analyze,
                icon: _isAnalyzing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _isAnalyzing
                      ? loc.nutritionPhotoAnalyzing
                      : loc.nutritionPhotoAnalyze,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
