import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/utils/ai_endpoint_policy.dart';
import 'package:workout_notes/utils/ai_json.dart';
import 'package:workout_notes/utils/base64_encoder.dart';

/// Thrown when the label extraction cannot be completed.
class AiFoodLabelException implements Exception {
  final String code;
  final String message;

  const AiFoodLabelException(this.code, this.message);

  @override
  String toString() => 'AiFoodLabelException($code): $message';
}

/// One nutrition-label image included in a vision extraction request.
class AiFoodLabelImage {
  final Uint8List bytes;
  final String mimeType;

  const AiFoodLabelImage({required this.bytes, this.mimeType = 'image/jpeg'});
}

/// Identifies a food from a nutrition label photo using the AI
/// provider already configured in the AI Coach (active provider +
/// selected model + stored token). It sends a single vision request
/// and parses the structured JSON answer.
class AiFoodLabelService {
  final AiSettingsNotifier settings;
  final AiService service;

  AiFoodLabelService({required this.settings, AiService? service})
      : service = service ?? AiService.shared;

  /// Extraction prompt. The nutrient list is generated from the same keys the
  /// parser reads ([AiFoodLabelDraft.nutrientKeys]), so a new nutrient is added
  /// in one place.
  static final String _systemPrompt = _buildSystemPrompt();

  static String _buildSystemPrompt() {
    final perBlock = AiFoodLabelDraft.nutrientKeys
        .map((key) => '    "$key": null')
        .join(',\n');
    return '''
Você é um extrator de tabelas nutricionais. Analise todas as imagens enviadas e extraia os dados delas.
Responda APENAS com JSON válido, sem markdown, sem comentários, exatamente neste formato:
{
  "name": "nome do produto (obrigatório; em pt-BR quando legível)",
  "brand": "marca ou null",
  "barcode": "código de barras ou null",
  "reference_amount": 100,
  "reference_unit": "g",
  "per": {
$perBlock
  },
  "servings": []
}
Regras:
- Todas as imagens pertencem ao mesmo alimento. Elas podem mostrar partes diferentes da mesma tabela, embalagem ou rótulo.
- Combine as informações complementares das imagens em um único alimento. Não some nem duplique valores repetidos; quando o mesmo campo aparecer mais de uma vez, use a imagem mais nítida e consistente.
- "per" contém os valores POR 100 g ou 100 ml da tabela. Se a tabela só mostrar valores "por porção", converta para 100 g/ml usando o peso da porção; se a conversão não for possível, use os valores por porção, informe em reference_amount/reference_unit o peso ou volume da porção e adicione uma serving com quantity 1, unit "porção" e grams_equivalent com o peso da porção.
- "reference_amount" e "reference_unit" são obrigatórios e nunca devem ser omitidos nem presumidos.
- Use null para valores ilegíveis; nunca invente números e nunca escreva a palavra "null" entre aspas.
- Gordura total e cada subtipo são campos independentes. Não calcule um subtipo ausente por diferença e não use gordura total como gordura saturada.
- Preserve as unidades do formato: minerais em mg, vitamina A/D/B12 em µg e vitamina C em mg. Converta quando o rótulo usar outra unidade.
- "servings" é uma lista opcional de porções com {label, quantity, unit, grams_equivalent}.
- Responda somente o JSON.''';
  }

  /// Analyzes [imageBytes] and returns the extracted food data.
  ///
  /// Throws [AiFoodLabelException] with codes:
  /// `not_configured` (no AI provider), `missing_token`, `no_model`,
  /// `no_content`, `parse_failed` or an error code from [AiService].
  Future<AiFoodLabelDraft> analyze({
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) =>
      analyzeImages(
        images: [AiFoodLabelImage(bytes: imageBytes, mimeType: mimeType)],
      );

  /// Analyzes multiple photos of different parts of the same food label.
  Future<AiFoodLabelDraft> analyzeImages({
    required List<AiFoodLabelImage> images,
  }) async {
    if (images.isEmpty) {
      throw const AiFoodLabelException('no_images', 'No images selected');
    }
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
    // Same consent rule as the coach: nothing is sent before the user allows
    // sharing data with the provider.
    if (!settings.settings.dataSharingAccepted) {
      throw const AiFoodLabelException(
        'consent_required',
        'Data sharing with the AI provider is not allowed',
      );
    }
    final token = await settings.getToken(provider.id) ?? '';
    // Keep this flow consistent with AiChatService. Without this check a
    // secure-storage read failure became an unauthenticated request and the
    // screen hid the resulting 401 behind a generic label-analysis error.
    // Local endpoints (a LAN Ollama) work without a token, as in the chat.
    if (token.isEmpty && !AiEndpointPolicy.isLocalEndpoint(provider.baseUrl)) {
      throw const AiFoodLabelException('missing_token', 'Missing API token');
    }

    final encodedImages = await Future.wait(
      images.map((image) => encodeBase64OffMain(image.bytes)),
    );
    final imageParts = <Map<String, dynamic>>[
      for (var index = 0; index < images.length; index++)
        <String, dynamic>{
          'type': 'image_url',
          'image_url': {
            'url':
                'data:${images[index].mimeType};base64,${encodedImages[index]}',
          },
        },
    ];
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': _systemPrompt},
      {
        'role': 'user',
        'content': [
          {
            'type': 'text',
            'text': images.length == 1
                ? 'Extraia os dados desta tabela nutricional.'
                : 'Estas ${images.length} imagens são do mesmo alimento e mostram partes complementares do rótulo. Combine-as e extraia uma única tabela nutricional.',
          },
          ...imageParts,
        ],
      },
    ];

    if (kDebugMode) {
      debugPrint(
        'AiFoodLabelService: sending vision request '
        '(provider=${provider.name}, model=$model, images=${images.length}, '
        'imageBytes=${images.fold<int>(0, (sum, image) => sum + image.bytes.length)})',
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
      return AiFoodLabelDraft.fromJson(AiJson.parseObject(text));
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
}
