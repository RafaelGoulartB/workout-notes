import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_notes/models/nutrition/ai_food_label_draft.dart';
import 'package:workout_notes/services/ai_food_label_service.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

class _StubAiService extends AiService {
  AiChatCompletion response;
  String? lastBaseUrl;
  String? lastToken;
  String? lastModel;
  List<Map<String, dynamic>>? lastMessages;

  _StubAiService(this.response);

  @override
  Future<AiChatCompletion> sendChat({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    double temperature = 0.3,
    String? reasoningEffort,
  }) async {
    lastBaseUrl = baseUrl;
    lastToken = token;
    lastModel = model;
    lastMessages = messages;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SharedPreferences prefs;
  late _StubAiService ai;
  late AiSettingsNotifier settings;
  late AiFoodLabelService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    ai = _StubAiService(AiChatCompletion(text: jsonEncode(_validJson())));
    settings = AiSettingsNotifier(prefs: prefs, service: ai);
    final provider = await settings.addProvider(
      name: 'Stub',
      baseUrl: 'https://api.stub/v1',
      token: 'secret-token',
    );
    await settings.setSelectedModel(provider.id, 'vision-model');
    service = AiFoodLabelService(settings: settings, service: ai);
  });

  group('AiFoodLabelService', () {
    test(
      'sends a vision message with the image and parses the draft',
      () async {
        final bytes = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10]);
        final draft = await service.analyze(imageBytes: bytes);

        expect(draft.name, 'Iogurte natural');
        expect(draft.brand, 'Marca Teste');
        expect(draft.barcode, '7891234567890');
        expect(draft.referenceAmount, 100);
        expect(draft.referenceUnit, 'g');
        expect(draft.values.calories, 64);
        expect(draft.values.proteinG, 5.5);
        expect(draft.values.carbsG, 7);
        expect(draft.values.fatG, 3.5);
        expect(draft.servings, hasLength(1));
        expect(draft.servings.first.gramsEquivalent, 170);

        expect(ai.lastModel, 'vision-model');
        expect(ai.lastToken, 'secret-token');
        expect(ai.lastBaseUrl, 'https://api.stub/v1');
        final userContent = ai.lastMessages!.last['content'] as List<dynamic>;
        final imagePart = userContent.cast<Map<String, dynamic>>().firstWhere(
          (part) => part['type'] == 'image_url',
        );
        final url =
            (imagePart['image_url'] as Map<String, dynamic>)['url'] as String;
        expect(url, startsWith('data:image/jpeg;base64,'));
        expect(url, contains(base64Encode(bytes)));
      },
    );

    test('sends multiple label images in the same vision request', () async {
      final first = Uint8List.fromList([1, 2, 3]);
      final second = Uint8List.fromList([4, 5, 6, 7]);

      final draft = await service.analyzeImages(
        images: [
          AiFoodLabelImage(bytes: first, mimeType: 'image/png'),
          AiFoodLabelImage(bytes: second, mimeType: 'image/webp'),
        ],
      );

      expect(draft.name, 'Iogurte natural');
      final userContent = ai.lastMessages!.last['content'] as List<dynamic>;
      final parts = userContent.cast<Map<String, dynamic>>();
      expect(parts.first['text'], contains('2 imagens'));
      final imageParts = parts
          .where((part) => part['type'] == 'image_url')
          .toList();
      expect(imageParts, hasLength(2));
      expect(
        (imageParts[0]['image_url'] as Map<String, dynamic>)['url'],
        'data:image/png;base64,${base64Encode(first)}',
      );
      expect(
        (imageParts[1]['image_url'] as Map<String, dynamic>)['url'],
        'data:image/webp;base64,${base64Encode(second)}',
      );
    });

    test('rejects an empty image list before contacting the provider', () {
      expect(
        () => service.analyzeImages(images: const []),
        throwsA(
          isA<AiFoodLabelException>().having(
            (error) => error.code,
            'code',
            'no_images',
          ),
        ),
      );
    });

    test('strips markdown fences around the JSON', () async {
      ai.response = AiChatCompletion(
        text: '```json\n${jsonEncode(_validJson())}\n```',
      );
      final draft = await service.analyze(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(draft.name, 'Iogurte natural');
    });

    test('extracts the JSON object embedded in extra prose', () async {
      ai.response = AiChatCompletion(
        text: 'Aqui está:\n${jsonEncode(_validJson())}\nEspero ter ajudado.',
      );
      final draft = await service.analyze(
        imageBytes: Uint8List.fromList([1, 2, 3]),
      );
      expect(draft.name, 'Iogurte natural');
    });

    test('throws not_configured when no provider exists', () async {
      final empty = AiSettingsNotifier(prefs: prefs, service: ai);
      final lonely = AiFoodLabelService(settings: empty, service: ai);
      expect(
        () => lonely.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'not_configured',
          ),
        ),
      );
    });

    test('throws no_model when the provider has no selected model', () async {
      final noModel = AiSettingsNotifier(prefs: prefs, service: ai);
      await noModel.addProvider(
        name: 'Sem modelo',
        baseUrl: 'https://api.stub/v1',
        token: 'tok',
      );
      final lonely = AiFoodLabelService(settings: noModel, service: ai);
      expect(
        () => lonely.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having((e) => e.code, 'code', 'no_model'),
        ),
      );
    });

    test('throws missing_token before sending the request', () async {
      await settings.setToken(settings.activeProvider!.id, null);

      expect(
        () => service.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'missing_token',
          ),
        ),
      );
    });

    test('preserves the AI service error code', () async {
      final failing = AiFoodLabelService(
        settings: settings,
        service: _FailingAiService(),
      );

      expect(
        () => failing.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'invalid_token',
          ),
        ),
      );
    });

    test('throws no_content for an empty completion', () async {
      ai.response = const AiChatCompletion(text: null);
      expect(
        () => service.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'no_content',
          ),
        ),
      );
    });

    test('throws parse_failed for non-JSON output', () async {
      ai.response = const AiChatCompletion(text: 'Não consigo ver a tabela.');
      expect(
        () => service.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'parse_failed',
          ),
        ),
      );
    });

    test('throws parse_failed when the JSON lacks a name', () async {
      ai.response = AiChatCompletion(text: jsonEncode({'brand': 'X'}));
      expect(
        () => service.analyze(imageBytes: Uint8List.fromList([1])),
        throwsA(
          isA<AiFoodLabelException>().having(
            (e) => e.code,
            'code',
            'parse_failed',
          ),
        ),
      );
    });
  });

  group('AiFoodLabelDraft', () {
    test('treats missing fields as null, never zero', () {
      final draft = AiFoodLabelDraft.fromJson({
        'name': 'Suco',
        'per': {'calories': 45, 'protein_g': 0},
      });
      expect(draft.values.calories, 45);
      expect(draft.values.proteinG, 0);
      expect(draft.values.carbsG, isNull);
      expect(draft.values.fatG, isNull);
      expect(draft.servings, isEmpty);
    });

    test('accepts numeric strings with comma decimal separator', () {
      final draft = AiFoodLabelDraft.fromJson({
        'name': 'Biscoito',
        'per': {'calories': '120,5', 'fat_g': '3,2'},
      });
      expect(draft.values.calories, closeTo(120.5, 0.001));
      expect(draft.values.fatG, closeTo(3.2, 0.001));
    });

    test('parses all supported fat subtypes independently', () {
      final draft = AiFoodLabelDraft.fromJson({
        'name': 'Pasta de amendoim',
        'per': {
          'fat_g': 50,
          'saturated_fat_g': 8,
          'monounsaturated_fat_g': 24,
          'polyunsaturated_fat_g': 15,
          'trans_fat_g': 0,
        },
      });
      expect(draft.values.fatG, 50);
      expect(draft.values.saturatedFatG, 8);
      expect(draft.values.monounsaturatedFatG, 24);
      expect(draft.values.polyunsaturatedFatG, 15);
      expect(draft.values.transFatG, 0);
    });

    test('parses the supported micronutrients and preserves their units', () {
      final draft = AiFoodLabelDraft.fromJson({
        'name': 'Multivitamínico',
        'per': {
          'potassium_mg': 350,
          'calcium_mg': 120,
          'iron_mg': '2,4',
          'magnesium_mg': 45,
          'zinc_mg': 1.1,
          'vitamin_a_ug': 90,
          'vitamin_c_mg': 12,
          'vitamin_d_ug': 2.5,
          'vitamin_b12_ug': 0.6,
        },
      });
      expect(draft.values.potassiumMg, 350);
      expect(draft.values.ironMg, 2.4);
      expect(draft.values.vitaminAUg, 90);
      expect(draft.values.vitaminCMg, 12);
      expect(draft.values.vitaminDUg, 2.5);
      expect(draft.values.vitaminB12Ug, 0.6);
    });

    test('round-trips AI food drafts including gram and ml servings', () {
      final original = AiFoodLabelDraft.fromJson({
        'name': 'Leite',
        'reference_amount': 100,
        'reference_unit': 'ml',
        'per': {'calories': 61, 'protein_g': 3.2},
        'servings': [
          {
            'label': '1 copo',
            'quantity': 1,
            'unit': 'copo',
            'grams_equivalent': 206,
            'ml_equivalent': 200,
          },
        ],
      });

      final decoded = AiFoodLabelDraft.fromJson(original.toJson());
      expect(decoded.referenceUnit, 'ml');
      expect(decoded.values.calories, 61);
      expect(decoded.servings.single.gramsEquivalent, 206);
      expect(decoded.servings.single.mlEquivalent, 200);
    });
  });
}

class _FailingAiService extends AiService {
  @override
  Future<AiChatCompletion> sendVision({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) {
    throw const AiServiceException(
      'Invalid or missing API token.',
      code: 'invalid_token',
    );
  }
}

Map<String, dynamic> _validJson() => {
  'name': 'Iogurte natural',
  'brand': 'Marca Teste',
  'barcode': '7891234567890',
  'reference_amount': 100,
  'reference_unit': 'g',
  'per': {
    'calories': 64,
    'protein_g': 5.5,
    'carbs_g': 7,
    'fat_g': 3.5,
    'fiber_g': null,
    'sugars_g': null,
    'sodium_mg': null,
  },
  'servings': [
    {
      'label': '1 pote',
      'quantity': 1,
      'unit': 'porção',
      'grams_equivalent': 170,
    },
  ],
};
