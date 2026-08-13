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
import 'package:workout_notes/utils/ai_error_localizer.dart';

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
  static const int _maxImages = 5;

  final ImagePicker _picker = ImagePicker();
  late final AiFoodLabelService _service;
  final List<AiFoodLabelImage> _images = [];
  bool _isPicking = false;
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
    final remaining = _maxImages - _images.length;
    if (remaining <= 0 || _isPicking) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionPhotoLimitReached)));
      return;
    }
    setState(() => _isPicking = true);
    try {
      final List<XFile> files;
      if (source == ImageSource.camera) {
        final file = await _picker.pickImage(
          source: source,
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 85,
          requestFullMetadata: false,
        );
        files = file == null ? const [] : [file];
      } else {
        files = await _picker.pickMultiImage(
          maxWidth: 1280,
          maxHeight: 1280,
          imageQuality: 85,
          limit: remaining,
          requestFullMetadata: false,
        );
      }
      final selected = <AiFoodLabelImage>[];
      for (final file in files.take(remaining)) {
        final bytes = await file.readAsBytes();
        selected.add(
          AiFoodLabelImage(
            bytes: bytes,
            mimeType: _supportedImageMimeType(file.mimeType, bytes),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _images.addAll(selected));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(loc.nutritionPhotoPickFailed)));
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _removeImage(int index) {
    if (_isAnalyzing) return;
    setState(() => _images.removeAt(index));
  }

  Future<void> _analyze() async {
    final loc = AppLocalizations.of(context)!;
    if (_images.isEmpty || _isAnalyzing) return;
    setState(() => _isAnalyzing = true);
    try {
      final draft = await _service.analyzeImages(images: List.of(_images));
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
    } catch (error, stackTrace) {
      debugPrint('FoodLabelPhotoScreen: unexpected analysis error: $error');
      debugPrintStack(stackTrace: stackTrace);
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
              : localizeAiError('ai_error:$code', loc),
        ),
      ),
    );
  }

  static String _supportedImageMimeType(
    String? reportedMimeType,
    Uint8List bytes,
  ) {
    const supported = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
    final normalized = reportedMimeType?.trim().toLowerCase();
    if (normalized != null && supported.contains(normalized)) {
      return normalized;
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
      return 'image/gif';
    }
    // image_picker applies JPEG compression on supported mobile sources. Keep
    // JPEG as the compatibility fallback when the platform omits a MIME type.
    return 'image/jpeg';
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
            if (_images.isNotEmpty)
              _SelectedImagesPreview(
                images: _images,
                onRemove: _removeImage,
                removeTooltip: loc.nutritionPhotoRemove,
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
            if (_images.isNotEmpty) ...[
              Text(
                loc.nutritionPhotoSelectedCount(_images.length, _maxImages),
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _isAnalyzing || _isPicking
                        ? null
                        : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: Text(loc.nutritionPhotoTake),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isAnalyzing || _isPicking
                        ? null
                        : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: Text(loc.nutritionPhotoGallery),
                  ),
                ),
              ],
            ),
            if (_images.isNotEmpty) ...[
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

class _SelectedImagesPreview extends StatelessWidget {
  final List<AiFoodLabelImage> images;
  final ValueChanged<int> onRemove;
  final String removeTooltip;

  const _SelectedImagesPreview({
    required this.images,
    required this.onRemove,
    required this.removeTooltip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        height: 220,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: images.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (context, index) => SizedBox(
            width: images.length == 1 ? constraints.maxWidth : 180,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(images[index].bytes, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.scrim.withAlpha(170),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filled(
                    tooltip: removeTooltip,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => onRemove(index),
                    icon: const Icon(Icons.close_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
