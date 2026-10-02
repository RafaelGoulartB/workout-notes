import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/models/ai_settings.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_prompts.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/utils/app_locale.dart';

const _kPrefsProviders = 'ai_providers_v1';
const _kPrefsActiveId = 'ai_active_provider_id_v1';
const _kPrefsCustomInstructions = 'ai_custom_instructions_v1';
const _kPrefsResponseStyle = 'ai_response_style_v1';
const _kPrefsShowMessageTimestamps = 'ai_show_message_timestamps_v1';
const _kPrefsDisabledDomains = 'ai_disabled_domains_v1';
const _kPrefsDataSharingAccepted = 'ai_data_sharing_accepted_v1';
const _kPrefsDeveloperMode = 'ai_developer_mode_v1';
const _kPrefsCompatibility = 'ai_compatibility_v1';
const _kTokenPrefix = 'ai_token:';
const _kLegacyTokenKey = 'ai_token';

// Keys of the v1 coach (whole editable prompt, context mode).
const _kLegacyPrefsSystemPrompt = 'ai_system_prompt_v1';
const _kLegacyPrefsContextMode = 'ai_context_mode_v1';
const _kLegacyPrefsAutoExpandToolDetails = 'ai_auto_expand_tool_details_v1';

/// Set once the pre-multi-provider token key has been looked at, so later
/// launches skip the (slow) secure-storage read.
const _kPrefsLegacyTokenMigrated = 'ai_legacy_token_migrated_v1';

/// Longest custom-instructions text accepted (about 600 tokens).
const int kMaxAiCustomInstructionsChars = 2000;

class AiSettingsNotifier extends ChangeNotifier {
  final SharedPreferences prefs;
  final FlutterSecureStorage secure;
  final AiService service;

  AiSettings _settings = const AiSettings();
  bool _loaded = false;

  AiSettingsNotifier({
    required this.prefs,
    FlutterSecureStorage? secure,
    AiService? service,
  }) : secure = secure ?? const FlutterSecureStorage(),
       service = service ?? AiService.shared;

  AiSettings get settings => _settings;

  /// The app language the user picked in Settings (`pt` or `en`); the same
  /// preference that drives the UI locale. It also sets the reply language.
  String get appLanguageCode =>
      AppLocale.languageCode(prefs.getString('app_locale'));
  bool get isLoaded => _loaded;
  bool get isConfigured => _settings.isConfigured;
  AiProvider? get activeProvider => _settings.activeProvider;
  String get customInstructions => _settings.customInstructions;
  Set<AiToolDomain> get effectiveDomains => _settings.effectiveDomains;

  /// The full static system message for the current settings.
  String get systemMessage => AiPrompts.system(
    languageCode: appLanguageCode,
    style: _settings.responseStyle,
    customInstructions: _settings.customInstructions,
  );

  /// Loads from SharedPreferences + FlutterSecureStorage.
  Future<void> load() async {
    service.attachCompatibilityStore(_PrefsCompatibilityStore(prefs));
    final providersJson = prefs.getString(_kPrefsProviders);
    final providers = <AiProvider>[];
    if (providersJson != null && providersJson.isNotEmpty) {
      try {
        final list = jsonDecode(providersJson) as List;
        for (final raw in list) {
          if (raw is Map) {
            providers.add(AiProvider.fromMap(raw.cast<String, dynamic>()));
          }
        }
      } catch (error) {
        debugPrint('Reading the saved AI providers failed: $error');
      }
    }

    final disabled = <AiToolDomain>{
      for (final key in prefs.getStringList(_kPrefsDisabledDomains) ?? [])
        ?AiToolDomain.fromStorageKey(key),
    };
    _settings = AiSettings(
      providers: providers,
      activeProviderId: prefs.getString(_kPrefsActiveId),
      customInstructions: await _loadCustomInstructions(),
      responseStyle: AiResponseStyleX.fromStorageKey(
        prefs.getString(_kPrefsResponseStyle),
      ),
      showMessageTimestamps:
          prefs.getBool(_kPrefsShowMessageTimestamps) ?? true,
      enabledDomains: {
        for (final domain in AiToolDomain.values)
          if (!disabled.contains(domain)) domain,
      },
      dataSharingAccepted: await _loadDataSharingAccepted(providers),
      developerMode: prefs.getBool(_kPrefsDeveloperMode) ?? false,
    );

    await _migrateLegacyToken(providers);
    _loaded = true;
    notifyListeners();
  }

  /// Whether the user accepted sending data to the provider. Decided once and
  /// stored on the first launch of this version: someone who already had a
  /// provider configured was using the previous coach (and its data sharing),
  /// so they are not interrupted; everyone else, including a new user who
  /// adds a provider later, sees the notice before their first message.
  Future<bool> _loadDataSharingAccepted(List<AiProvider> providers) async {
    final stored = prefs.getBool(_kPrefsDataSharingAccepted);
    if (stored != null) return stored;
    final upgraded = providers.isNotEmpty;
    await prefs.setBool(_kPrefsDataSharingAccepted, upgraded);
    return upgraded;
  }

  /// Custom instructions, migrating the v1 "whole prompt" setting: a stored
  /// copy of a shipped default becomes "no personalisation"; a prompt the
  /// user really wrote is kept as their custom instructions.
  Future<String> _loadCustomInstructions() async {
    final current = prefs.getString(_kPrefsCustomInstructions);
    if (current != null) return current;
    final legacy = prefs.getString(_kLegacyPrefsSystemPrompt)?.trim() ?? '';
    final isShippedDefault =
        legacy.contains('Treinador do Workout Notes') ||
        legacy.contains('# Identidade e missão') ||
        legacy.contains('FORMATAÇÃO (IMPORTANTE):') ||
        legacy.contains('Você é o "Treinador') ||
        legacy.contains('discover_app_capabilities');
    var migrated = isShippedDefault ? '' : legacy;
    if (migrated.length > kMaxAiCustomInstructionsChars) {
      migrated = migrated.substring(0, kMaxAiCustomInstructionsChars);
    }
    await prefs.setString(_kPrefsCustomInstructions, migrated);
    for (final key in const [
      _kLegacyPrefsSystemPrompt,
      _kLegacyPrefsContextMode,
      _kLegacyPrefsAutoExpandToolDetails,
    ]) {
      await prefs.remove(key);
    }
    return migrated;
  }

  Future<void> _migrateLegacyToken(List<AiProvider> providers) async {
    if (providers.isEmpty ||
        (prefs.getBool(_kPrefsLegacyTokenMigrated) ?? false)) {
      return;
    }
    try {
      final legacyToken = await secure.read(key: _kLegacyTokenKey);
      if (legacyToken != null && legacyToken.isNotEmpty) {
        final active = _settings.activeProvider;
        if (active != null) {
          await secure.write(
            key: '$_kTokenPrefix${active.id}',
            value: legacyToken,
          );
        }
        await secure.delete(key: _kLegacyTokenKey);
      }
      await prefs.setBool(_kPrefsLegacyTokenMigrated, true);
    } catch (error) {
      debugPrint('Migrating the legacy AI token failed: ${error.runtimeType}');
    }
  }

  // ===========================================================================
  // PROVIDERS
  // ===========================================================================

  Future<AiProvider> addProvider({
    required String name,
    required String baseUrl,
    String? token,
    String? model,
  }) async {
    final p = AiProvider.create(
      name: name,
      baseUrl: AiService.normalizeBaseUri(baseUrl),
      selectedModel: model?.trim() ?? '',
    );
    _settings = _settings.copyWith(
      providers: [..._settings.providers, p],
      activeProviderId: _settings.activeProviderId ?? p.id,
    );
    await _persistProviders();
    if (token != null && token.isNotEmpty) {
      await setToken(p.id, token);
    }
    notifyListeners();
    return p;
  }

  Future<void> updateProvider(AiProvider updated, {String? token}) async {
    final previous = _providerById(updated.id);
    final normalized = updated.copyWith(
      baseUrl: AiService.normalizeBaseUri(updated.baseUrl),
      clearLastCheck:
          previous != null &&
          (previous.baseUrl != updated.baseUrl ||
              previous.selectedModel != updated.selectedModel),
    );
    _replaceProvider(normalized);
    await _persistProviders();
    if (previous != null && previous.baseUrl != normalized.baseUrl) {
      await service.resetCompatibility(
        previous.baseUrl,
        previous.selectedModel,
      );
    }
    if (token != null) {
      await setToken(updated.id, token.isEmpty ? null : token);
    }
    notifyListeners();
  }

  Future<void> deleteProvider(String id) async {
    final list = _settings.providers.where((p) => p.id != id).toList();
    var newActive = _settings.activeProviderId;
    if (newActive == id) {
      newActive = list.isNotEmpty ? list.first.id : null;
    }
    _settings = _settings.copyWith(
      providers: list,
      activeProviderId: newActive,
      clearActiveProvider: newActive == null,
    );
    await _persistProviders();
    try {
      await secure.delete(key: '$_kTokenPrefix$id');
    } catch (error) {
      debugPrint('Deleting the AI provider token failed: ${error.runtimeType}');
    }
    notifyListeners();
  }

  Future<void> setActiveProvider(String id) async {
    _settings = _settings.copyWith(activeProviderId: id);
    await prefs.setString(_kPrefsActiveId, id);
    notifyListeners();
  }

  /// Selects [model] (typed by hand or picked from the fetched list).
  Future<void> setSelectedModel(String providerId, String model) async {
    final provider = _providerById(providerId);
    if (provider == null) return;
    _replaceProvider(
      provider.copyWith(
        selectedModel: model.trim(),
        clearLastCheck: provider.selectedModel != model.trim(),
      ),
    );
    await _persistProviders();
    notifyListeners();
  }

  Future<void> setReasoningEffort(
    String providerId,
    String model,
    AiReasoningEffort effort,
  ) async {
    final provider = _providerById(providerId);
    if (provider == null) return;
    final efforts = Map<String, AiReasoningEffort>.from(
      provider.reasoningEffortByModel,
    );
    if (effort == AiReasoningEffort.automatic) {
      efforts.remove(model);
    } else {
      efforts[model] = effort;
    }
    _replaceProvider(provider.copyWith(reasoningEffortByModel: efforts));
    await _persistProviders();
    notifyListeners();
  }

  Future<void> setProviderModels(String providerId, List<String> models) async {
    final provider = _providerById(providerId);
    if (provider == null) return;
    _replaceProvider(provider.copyWith(availableModels: models));
    await _persistProviders();
    notifyListeners();
  }

  Future<String?> getToken(String providerId) async {
    try {
      return await secure.read(key: '$_kTokenPrefix$providerId');
    } catch (error) {
      debugPrint('Reading the AI provider token failed: ${error.runtimeType}');
      return null;
    }
  }

  Future<void> setToken(String providerId, String? token) async {
    try {
      if (token == null || token.isEmpty) {
        await secure.delete(key: '$_kTokenPrefix$providerId');
      } else {
        await secure.write(key: '$_kTokenPrefix$providerId', value: token);
      }
    } catch (error) {
      debugPrint('Saving the AI provider token failed: ${error.runtimeType}');
    }
  }

  /// Fetches the provider's model list. Local servers without a token are
  /// allowed (an empty token sends no Authorization header).
  Future<List<String>> fetchModels(String providerId) async {
    final p = _providerById(providerId);
    if (p == null) return const [];
    final token = await getToken(providerId) ?? '';
    final models = await service.listModels(baseUrl: p.baseUrl, token: token);
    await setProviderModels(providerId, models);
    return models;
  }

  /// Runs a short streamed tool-call request against the selected model and
  /// stores what worked on the provider.
  Future<AiProviderCheck> testConnection(String providerId) async {
    final p = _providerById(providerId);
    if (p == null || p.selectedModel.isEmpty) {
      return AiProviderCheck(
        model: p?.selectedModel ?? '',
        ok: false,
        toolsSupported: false,
        streamingSupported: false,
        latencyMs: 0,
        checkedAt: DateTime.now(),
        errorCode: 'missing_model',
      );
    }
    final token = await getToken(providerId) ?? '';
    final result = await service.probe(
      baseUrl: p.baseUrl,
      token: token,
      model: p.selectedModel,
      apiStyle: p.apiStyle,
    );
    final check = AiProviderCheck(
      model: p.selectedModel,
      ok: result.ok,
      toolsSupported: result.toolsSupported,
      streamingSupported: result.streamingSupported,
      latencyMs: result.latencyMs,
      errorCode: result.errorCode,
      checkedAt: DateTime.now(),
    );
    final current = _providerById(providerId);
    if (current != null) {
      _replaceProvider(current.copyWith(lastCheck: check));
      await _persistProviders();
      notifyListeners();
    }
    return check;
  }

  // ===========================================================================
  // COACH BEHAVIOUR
  // ===========================================================================

  Future<void> setCustomInstructions(String value) async {
    var text = value.trim();
    if (text.length > kMaxAiCustomInstructionsChars) {
      text = text.substring(0, kMaxAiCustomInstructionsChars);
    }
    _settings = _settings.copyWith(customInstructions: text);
    await prefs.setString(_kPrefsCustomInstructions, text);
    notifyListeners();
  }

  Future<void> setResponseStyle(AiResponseStyle style) async {
    _settings = _settings.copyWith(responseStyle: style);
    await prefs.setString(_kPrefsResponseStyle, style.storageKey);
    notifyListeners();
  }

  Future<void> setShowMessageTimestamps(bool enabled) async {
    _settings = _settings.copyWith(showMessageTimestamps: enabled);
    await prefs.setBool(_kPrefsShowMessageTimestamps, enabled);
    notifyListeners();
  }

  /// Switches a data domain on or off for the coach (privacy and catalog
  /// size). [AiToolDomain.core] cannot be switched off.
  Future<void> setDomainEnabled(AiToolDomain domain, bool enabled) async {
    if (domain == AiToolDomain.core) return;
    final domains = {..._settings.enabledDomains};
    enabled ? domains.add(domain) : domains.remove(domain);
    _settings = _settings.copyWith(enabledDomains: domains);
    await prefs.setStringList(_kPrefsDisabledDomains, [
      for (final d in AiToolDomain.optional)
        if (!domains.contains(d)) d.storageKey,
    ]);
    notifyListeners();
  }

  Future<void> setDataSharingAccepted(bool accepted) async {
    _settings = _settings.copyWith(dataSharingAccepted: accepted);
    await prefs.setBool(_kPrefsDataSharingAccepted, accepted);
    notifyListeners();
  }

  Future<void> setDeveloperMode(bool enabled) async {
    _settings = _settings.copyWith(developerMode: enabled);
    await prefs.setBool(_kPrefsDeveloperMode, enabled);
    notifyListeners();
  }

  // ===========================================================================

  AiProvider? _providerById(String id) {
    for (final p in _settings.providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  void _replaceProvider(AiProvider updated) {
    _settings = _settings.copyWith(
      providers: [
        for (final p in _settings.providers) p.id == updated.id ? updated : p,
      ],
    );
  }

  Future<void> _persistProviders() async {
    final json = jsonEncode(_settings.providers.map((p) => p.toMap()).toList());
    await prefs.setString(_kPrefsProviders, json);
    if (_settings.activeProviderId != null) {
      await prefs.setString(_kPrefsActiveId, _settings.activeProviderId!);
    } else {
      await prefs.remove(_kPrefsActiveId);
    }
  }
}

/// Persists what [AiService] learned about each endpoint+model.
class _PrefsCompatibilityStore implements AiCompatibilityStore {
  final SharedPreferences prefs;
  const _PrefsCompatibilityStore(this.prefs);

  @override
  Map<String, Map<String, dynamic>> load() {
    final raw = prefs.getString(_kPrefsCompatibility);
    if (raw == null || raw.isEmpty) return const {};
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return const {};
    return {
      for (final entry in decoded.entries)
        if (entry.value is Map)
          '${entry.key}': (entry.value as Map).cast<String, dynamic>(),
    };
  }

  @override
  Future<void> save(Map<String, Map<String, dynamic>> value) =>
      prefs.setString(_kPrefsCompatibility, jsonEncode(value));
}
