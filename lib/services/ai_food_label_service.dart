import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

/// Thrown when the label extraction cannot be completed.
class AiFoodLabelException implements Exception {
  final String code;
  final String message;

  const AiFoodLabelException(this.code, this.message);

  @override
  String toString() => 'AiFoodLabelException($code): $message';
}

/// Identifies a food from a nutrition label photo using the AI
/// provider already configured in the AI Coach (active provider +
/// selected model + stored token). It sends a single vision request
/// and parses the structured JSON answer.
class AiFoodLabelService {
  final AiSettingsNotifier settings;
  final AiService service;

  AiFoodLabelService({required this.settings, AiService? service})
    : service = service ?? AiService();

  static const String _systemPrompt = r'''
Você é um extrator de tabelas nutricionais. Analise a foto enviada e extraia os dados dela.
Responda APENAS com JSON válido, sem markdown, sem comentários, exatamente neste formato:
{
  "name": "nome do produto (obrigatório; em pt-BR quando legível)",
  "brand": "marca ou null",
  "barcode": "código de barras ou null",
  "reference_amount": 100,
  "reference_unit": "g",
  "per": {
    "calories": null,
    "protein_g": null,
    "carbs_g": null,
    "fat_g": null,
    "fiber_g": null,
    "sugars_g": null,
    "sodium_mg": null
  },
  "servings": []
}
Regras:
- "per" contém os valores POR 100 g ou 100 ml da tabela. Se a tabela só mostrar valores "por porção", converta para 100 g/ml usando o peso da porção; se a conversão não for possível, use os valores por porção e adicione uma serving com quantity 1, unit "porção" e grams_equivalent com o peso da porção.
- Use null para valores ilegíveis; nunca invente números.
- "servings" é uma lista opcional de porções com {label, quantity, unit, grams_equivalent}.
- Responda somente o JSON.''';

  /// Analyzes [imageBytes] and returns the extracted food data.
  ///
  /// Throws [AiFoodLabelException] with codes:
  /// `not_configured` (no AI provider), `missing_token`, `no_model`,
  /// `no_content`, `parse_failed` or an error code from [AiService].
  Future<AiFoodLabelDraft> analyze({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final provider = settings.activeProvider;
    if (provider == null) {
      throw const AiFoodLabelException(
        'not_configured',
        'No AI provider configured',
      );
    }
    final model = provider.selectedModel.trim();
    if (model.isEmpty) {
      throw const AiFoodLabelException('no_model', 'No model selected');
    }
    final token = await settings.getToken(provider.id) ?? '';
    // Keep this flow consistent with AiChatService. Without this check a
    // secure-storage read failure became an unauthenticated request and the
    // screen hid the resulting 401 behind a generic label-analysis error.
    if (token.isEmpty) {
      throw const AiFoodLabelException('missing_token', 'Missing API token');
    }

    final base64 = base64Encode(imageBytes);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': 'Extraia os dados desta tabela nutricional.',
          },
          {
            'type': 'image_url',
            'image_url': {'url': 'data:$mimeType;base64,$base64'},
          },
        ],
      },
    ];

    if (kDebugMode) {
      debugPrint(
        'AiFoodLabelService: sending vision request '
        '(provider=${provider.name}, model=$model, mimeType=$mimeType, '
        'imageBytes=${imageBytes.length})',
      );
    }

    late final AiChatCompletion completion;
    try {
      completion = await service.sendVision(
        baseUrl: provider.baseUrl,
        token: token,
        model: model,
        messages: messages,
      );
    } on AiServiceException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('AiFoodLabelService: request failed: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      throw AiFoodLabelException(error.code ?? 'request_failed', error.message);
    } on TimeoutException catch (error, stackTrace) {
      if (kDebugMode) {
        debugPrint('AiFoodLabelService: request timed out: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
      throw const AiFoodLabelException('timeout', 'AI request timed out');
    }
    if (kDebugMode) {
      debugPrint('AiFoodLabelService: vision response received');
    }
    final text = completion.text;
    if (text == null || text.trim().isEmpty) {
      throw const AiFoodLabelException('no_content', 'Empty AI response');
    }
    try {
      return AiFoodLabelDraft.fromJson(_parseJson(text));
    } on AiFoodLabelException {
      rethrow;
    } on FormatException {
      throw const AiFoodLabelException(
        'parse_failed',
        'Invalid label JSON in response',
      );
    } on TypeError {
      throw const AiFoodLabelException(
        'parse_failed',
        'Invalid label JSON in response',
      );
    }
  }

  static Map<String, dynamic> _parseJson(String raw) {
    var cleaned = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(cleaned);
    if (fence != null) cleaned = fence.group(1)!.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
      throw const AiFoodLabelException(
        'parse_failed',
        'Response is not a JSON object',
      );
    } on AiFoodLabelException {
      rethrow;
    } on FormatException {
      throw const AiFoodLabelException(
        'parse_failed',
        'Invalid JSON in response',
      );
    } on TypeError {
      throw const AiFoodLabelException(
        'parse_failed',
        'Invalid JSON in response',
      );
    }
  }
}
