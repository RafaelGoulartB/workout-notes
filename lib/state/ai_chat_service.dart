import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_chat_error_details.dart';
import '../models/ai_image_attachment.dart';
import '../models/ai_chat_state.dart';
import '../models/ai_chat_thread.dart';
import '../models/ai_message_role.dart';
import '../models/ai_provider.dart';
import '../models/ai_routine_proposal.dart';
import '../models/ai_tool_call.dart';
import '../models/nutrition/ai_manual_food_proposal.dart';
import '../services/ai_context_service.dart';
import '../services/ai_image_attachment_store.dart';
import '../services/ai_routine_mutation_service.dart';
import '../services/ai_service.dart';
import '../services/ai_tool_registry.dart';
import '../utils/token_estimator.dart';
import '../utils/text_sanitizer.dart';
import 'ai_settings_notifier.dart';

part 'ai_chat_persistence.dart';
part 'ai_chat_threads.dart';
part 'ai_chat_wire.dart';

const _uuid = Uuid();

/// Upper bound on tool rounds per turn. The real limiter is
/// [kMaxTurnInputTokens]; this only stops a model that loops forever.
const int kMaxToolRounds = 8;

/// Once a request (history + tool results + schema) is estimated above this,
/// the next provider call is made without tools so the turn ends.
const int kMaxTurnInputTokens = 48000;

/// Prior conversation kept on the wire. Anything older is summarised.
const int kHistoryTokenBudget = 24000;
const int kTargetInputTokenBudget = 32000;
const int kMinHistoryTokenBudget = 4000;

/// A single tool result larger than this is cut on the wire (about 2.3k
/// tokens) with a marker telling the model to narrow the query. Several
/// rounds of analytics results add up fast, and slow providers time out on
/// requests past ~60k characters.
const int kMaxToolResultChars = 8000;
const int kMaxInvalidAnswerRegenerations = 2;
const int kMaxMissingToolCallRetries = 1;
const String _dataGroundingPolicy = r'''# Consulta obrigatória aos dados do app
As ferramentas são a fonte primária para fatos pessoais do usuário. Quando a solicitação depender de treino, sono, nutrição, medidas, metas, rotinas ou qualquer outro dado registrado, consulte a ferramenta relevante neste turno antes de responder. Não substitua a consulta por conhecimento geral, inferência ou lembrança de uma resposta anterior.

Interprete continuações usando a conversa recente. Se o usuário mudar apenas o domínio, preserve os qualificadores ainda aplicáveis do pedido anterior, especialmente período, comparação e objetivo. Exemplo: depois de um resumo da última semana, "E o sono?" exige consultar o resumo de sono para o mesmo período. O usuário nunca precisa pedir explicitamente que você use uma tool.

Todo o catálogo de ferramentas está sempre disponível; escolha pela descrição. Você pode chamar a mesma ferramenta mais de uma vez com parâmetros diferentes (outra página, outro período, outro identificador) e cruzar domínios no mesmo turno. Se um resultado vier marcado como truncado, refine a consulta em vez de deduzir o que faltou. Se uma consulta falhar ou não tiver registros suficientes, informe isso; nunca complete a lacuna com dados inventados.

Para alimentação, escolha a ferramenta mais específica: diário do dia para refeições e itens consumidos; histórico para totais por dia; micronutrientes para vitaminas, minerais, fibras, açúcares e sódio; biblioteca para alimentos cadastrados; refeições salvas para modelos; perfil para meta e tipos de refeição. Preserve `null` como dado não informado, nunca como zero.

Para treinos de força, escolha a ferramenta mais específica: histórico para localizar treinos por período ou status; detalhe para horários, rotina de origem, exercícios, supersets, descanso, notas e todas as séries; perfil do exercício para equipamento e configuração; histórico e recordes para desempenho específico; resumo do período para frequência, RPE, densidade, grupos e carga total. Para corrida e bicicleta, use histórico de atividades para localizar a sessão, detalhe para rota agregada e planejado versus realizado, progresso para tendências e comparação entre períodos, conquistas para recordes, e plano/agenda para aderência. Diferencie sempre `completed`, `in_progress` e `planned`. Ao descrever trabalho executado, use apenas dados concluídos e não apresente sessões planejadas como realizadas.

# Propostas de alimentos manuais (política fixa)
Quando o usuário pedir para criar ou cadastrar um alimento, use `propose_manual_food_creation`. Identifique a descrição com precisão e preencha o máximo possível dos dados suportados: nome, marca e código somente quando conhecidos, referência nutricional, calorias, macronutrientes, tipos de gordura, fibras, açúcares, sódio, micronutrientes e porções comuns.

Para alimentos genéricos, use valores típicos plausíveis e marque nas notas o preparo, a variedade ou a estimativa assumida. Para produtos de marca sem rótulo suficiente, não invente números exatos nem código de barras: use apenas o que o usuário forneceu e deixe os demais campos ausentes. Faça uma pergunta somente se a ambiguidade impedir uma prévia útil; caso contrário, gere a melhor prévia editável possível.

A ferramenta nunca salva o alimento. Explique que a prévia precisa ser aprovada e que a aprovação apenas abrirá o formulário manual preenchido; a criação só acontecerá quando o usuário revisar e tocar em Salvar nessa tela.''';
const String _routineMutationPolicy = r'''# Propostas de rotina (política fixa)
Você pode preparar uma proposta quando isso cumprir o pedido do usuário ou transformar uma recomendação relevante em uma prévia útil. Interprete a intenção pelo significado e pelo contexto da conversa, sem exigir palavras-chave ou uma formulação específica.

Quando houver esse pedido, você DEVE usar ferramentas; não responda dizendo que não consegue criar a rotina. Siga este fluxo:
1. Para criação, chame `list_exercises` para obter IDs reais dos exercícios necessários.
2. Para edição, chame `list_routines` e depois `get_routine_detail`; preserve os campos `source_*_id` retornados.
3. Seja proativo: se faltarem nome, divisão, séries, repetições ou descanso, NÃO peça uma lista de detalhes. Use a solicitação atual, a conversa anterior e os dados do app para decidir. Se o usuário disser “crie essa rotina”, a rotina mencionada/sugerida anteriormente na conversa é a especificação principal.
4. Na ausência de preferência explícita, escolha uma divisão equilibrada coerente com a frequência e os grupos musculares disponíveis, 3 séries de trabalho por exercício, faixas de 8–12 repetições para musculação e 90 segundos de descanso. Dê um nome descritivo à rotina. Essas escolhas são uma prévia segura porque o usuário ainda precisa aprovar.
5. Chame `propose_routine_change` com a árvore final completa. Campos opcionais podem ser omitidos; não escreva null se não precisar do campo.
6. Só faça uma pergunta em vez de propor se não houver exercício compatível na biblioteca ou se houver uma restrição de segurança relevante. Caso contrário, entregue a proposta para aprovação quando ela ajudar a concluir a tarefa.
7. Depois do resultado da ferramenta, explique que a prévia está disponível para aprovação.

`propose_routine_change` apenas prepara a prévia: ela não aplica nada. Nunca diga que criou ou editou uma rotina antes da aprovação e do resultado confirmado pelo app. Após uma aprovação, resuma somente os fatos retornados pelo app.''';
const String _manualFoodProposalPrompt =
    r'''Você prepara rascunhos de alimentos para revisão humana em um app de nutrição.

Quando solicitado, chame `propose_manual_food_creation` uma única vez. Identifique o alimento e preencha o máximo possível de: nome, marca e código de barras quando realmente conhecidos; referência em g ou ml; calorias; proteínas; carboidratos; gorduras e seus tipos; fibras; açúcares; sódio; potássio; cálcio; ferro; magnésio; zinco; vitaminas A, C, D e B12; e porções comuns.

Para alimentos genéricos, use valores típicos plausíveis e informe em `notes` o preparo ou variedade assumidos. Para produtos de marca sem rótulo suficiente, não invente valores exatos nem código de barras. Todos os nutrientes devem corresponder à quantidade de referência. A ferramenta só cria uma prévia: o usuário ainda revisará e salvará o formulário.''';
const String _manualFoodJsonFallbackPrompt =
    r'''Converta o pedido do usuário em um único objeto JSON, sem markdown nem comentários, usando exatamente esta estrutura:
{"name":"...","brand":"... opcional","barcode":"... opcional","reference_amount":100,"reference_unit":"g ou ml","per":{"calories":0,"protein_g":0,"carbs_g":0,"fat_g":0,"saturated_fat_g":0,"monounsaturated_fat_g":0,"polyunsaturated_fat_g":0,"trans_fat_g":0,"fiber_g":0,"sugars_g":0,"sodium_mg":0,"potassium_mg":0,"calcium_mg":0,"iron_mg":0,"magnesium_mg":0,"zinc_mg":0,"vitamin_a_ug":0,"vitamin_c_mg":0,"vitamin_d_ug":0,"vitamin_b12_ug":0},"servings":[{"label":"...","quantity":1,"unit":"...","grams_equivalent":0,"ml_equivalent":0}],"notes":"..."}

Omita campos opcionais ou nutrientes que não puder identificar com segurança; não escreva null. Para alimentos genéricos, use valores típicos plausíveis e descreva a hipótese em notes. Todos os nutrientes devem corresponder à quantidade de referência.''';
const String _threadSummaryPrompt =
    r'''Você mantém o resumo compacto de uma conversa entre um usuário e seu treinador de IA em um app de treino, sono e nutrição. Atualize o resumo incorporando as novas mensagens.

Preserve: objetivos, preferências e restrições do usuário; decisões tomadas; recomendações dadas; rotinas, planos ou alimentos propostos e se foram aprovados; períodos, métricas e números citados; pendências ou perguntas em aberto. Descarte cumprimentos e repetições.

Escreva em português brasileiro, em texto corrido ou lista curta, com no máximo 250 palavras. Não invente nada que não esteja nas mensagens ou no resumo atual. Responda somente com o resumo atualizado.''';

/// Singleton orchestrator for AI chat turns. Owns the chat state.
///
/// Uses [AiSettingsNotifier] for provider config, [AiService] for HTTP,
/// [AiContextService] for system-prompt context injection and
/// [AiToolRegistry] for read tool execution.
class AiChatService extends ChangeNotifier {
  static final AiChatService instance = AiChatService._();

  AiChatService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  AiService _service = AiService();
  AiToolRegistry _tools = AiToolRegistry();
  AiContextService _context = AiContextService();
  AiRoutineMutationService _routineMutations = AiRoutineMutationService();
  AiImageAttachmentStore _imageStore = AiImageAttachmentStore();
  AiSettingsNotifier? _settings;
  bool _isReady = false;
  Future<void>? _readyFuture;
  final Map<String, String> _persistedMessageSignatures = {};
  _AiTurnDiagnostics? _activeTurnDiagnostics;
  String? _activeReasoningEffort;

  /// Multiplier applied to the chars-per-token heuristic, learned from the
  /// `prompt_tokens` the provider reports. See `_calibrateTokenScale`.
  double _tokenScale = 1.0;

  AiChatState _state = const AiChatState();

  AiChatState get state => _state;
  bool get isSending => _state.isSending;

  void _emit() => notifyListeners();

  /// Replaces default collaborators (used in tests).
  void overrideForTest({
    AiService? service,
    AiToolRegistry? tools,
    AiContextService? context,
    AiRoutineMutationService? routineMutations,
    AiImageAttachmentStore? imageStore,
  }) {
    if (service != null) _service = service;
    if (tools != null) _tools = tools;
    if (context != null) _context = context;
    if (routineMutations != null) _routineMutations = routineMutations;
    if (imageStore != null) _imageStore = imageStore;
  }

  /// Wires the settings notifier. Must be called once at app boot
  /// (after `SharedPreferences.getInstance()`).
  static Future<AiChatService> bootstrap({
    required AiSettingsNotifier settings,
  }) async {
    final svc = AiChatService.instance;
    svc._settings = settings;
    return svc;
  }

  Future<void> ensureReady() async {
    if (_isReady) return;
    final pending = _readyFuture;
    if (pending != null) return pending;
    final future = _loadPersistentState();
    _readyFuture = future;
    try {
      await future;
      _isReady = true;
    } finally {
      if (identical(_readyFuture, future)) _readyFuture = null;
    }
  }

  Future<void> _loadPersistentState() async {
    await refreshThreads();
    unawaited(_cleanupOrphanedImages());
  }

  Future<void> _cleanupOrphanedImages() async {
    try {
      final db = await _db.database;
      final rows = await db.query(
        'ai_chat_messages',
        columns: ['attachments_json'],
        where: 'attachments_json IS NOT NULL',
      );
      final retained = <String>{};
      for (final row in rows) {
        final raw = row['attachments_json'] as String?;
        if (raw == null) continue;
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is Map && item['path'] is String) {
            retained.add(item['path'] as String);
          }
        }
      }
      await _imageStore.deleteOrphans(retained);
    } catch (_) {}
  }

  // ===========================================================================
  // SENDING
  // ===========================================================================

  Future<bool> send(
    String text, {
    List<AiPendingImage> images = const [],
    List<AiImageAttachment> existingAttachments = const [],
    VoidCallback? onAccepted,
  }) async {
    await ensureReady();
    final trimmed = text.trim();
    if (trimmed.isEmpty && images.isEmpty && existingAttachments.isEmpty) {
      return false;
    }
    if (images.length + existingAttachments.length >
        AiImageAttachmentStore.maxImagesPerMessage) {
      _state = _state.copyWith(error: 'ai_error:too_many_images');
      notifyListeners();
      return false;
    }
    if (isSending) return false;
    if (_settings == null || !_settings!.isConfigured) {
      _state = _state.copyWith(error: 'ai_error:missing_provider');
      notifyListeners();
      return false;
    }
    final provider = _settings!.activeProvider!;
    final token = await _settings!.getToken(provider.id);
    if (token == null || token.isEmpty) {
      _state = _state.copyWith(error: 'ai_error:missing_token');
      notifyListeners();
      return false;
    }
    if (provider.selectedModel.isEmpty) {
      _state = _state.copyWith(error: 'ai_error:missing_model');
      notifyListeners();
      return false;
    }

    final now = DateTime.now();
    List<AiImageAttachment> attachments;
    try {
      attachments = existingAttachments.isNotEmpty
          ? existingAttachments
          : await _imageStore.saveAll(images);
    } on AiImageAttachmentException catch (error) {
      _state = _state.copyWith(error: 'ai_error:${error.code}');
      notifyListeners();
      return false;
    }
    final fallbackText = attachments.isEmpty ? trimmed : 'Imagem enviada';
    late final String threadId;
    try {
      threadId = await _ensureThread(
        _state.messages,
        now,
        trimmed.isEmpty ? fallbackText : trimmed,
      );
    } catch (error) {
      if (existingAttachments.isEmpty) {
        await _imageStore.deleteAll(attachments);
      }
      _state = _state.copyWith(error: _readableError(error));
      notifyListeners();
      return false;
    }
    final userMsg = AiChatMessage(
      id: _uuid.v4(),
      threadId: threadId,
      role: AiMessageRole.user,
      content: trimmed,
      attachments: attachments,
      createdAt: now,
    );
    var messages = [..._state.messages, userMsg];

    _state = _state.copyWith(activeThreadId: threadId);

    _state = _state.copyWith(
      messages: messages,
      phase: AiTurnPhase.sending,
      clearError: true,
      phaseMessage: 'sending',
    );
    notifyListeners();
    onAccepted?.call();

    try {
      _activeReasoningEffort = provider.reasoningEffortFor().apiValue;
      _activeTurnDiagnostics = _AiTurnDiagnostics(
        stage: 'preparing_context',
        provider: provider.name,
        model: provider.selectedModel,
      );
      await _runTurn(
        messages: messages,
        baseUrl: provider.baseUrl,
        token: token,
        model: provider.selectedModel,
        systemPrompt: _settings!.effectiveSystemPrompt,
        contextMode: _settings!.contextMode,
      );
    } catch (e) {
      _state = _state.copyWith(
        phase: AiTurnPhase.failed,
        error: _readableError(e),
        errorDetails: _technicalErrorDetails(e),
        phaseMessage: null,
      );
      notifyListeners();
      await _persistCurrentThread();
    } finally {
      _activeTurnDiagnostics = null;
      _activeReasoningEffort = null;
    }
    return true;
  }

  Future<void> rejectRoutineProposal(String proposalId) async {
    try {
      final proposal = await _routineMutations.reject(proposalId);
      _replaceProposal(proposal);
      await _persistCurrentThread();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      notifyListeners();
    }
  }

  Future<void> approveRoutineProposal(String proposalId) async {
    if (isSending) return;
    _state = _state.copyWith(
      phase: AiTurnPhase.applyingProposal,
      phaseMessage: 'applying_proposal',
      clearError: true,
    );
    notifyListeners();
    try {
      final cachedProposal = _state.proposalById(proposalId);
      if (cachedProposal != null) {
        await _routineMutations.restorePendingProposal(cachedProposal);
      }
      final proposal = await _routineMutations.approve(proposalId);
      _replaceProposal(proposal, notify: false);
      await _persistCurrentThread();
      if (proposal.status != AiRoutineProposalStatus.applied) {
        _state = _state.copyWith(phase: AiTurnPhase.idle, phaseMessage: null);
        notifyListeners();
        return;
      }
      await _sendAppliedProposalSummary(proposal);
    } catch (e) {
      _state = _state.copyWith(
        phase: AiTurnPhase.failed,
        phaseMessage: null,
        error: e is AiRoutineMutationException
            ? 'ai_error:${e.code}:$proposalId'
            : _readableError(e),
      );
      notifyListeners();
    }
  }

  Future<void> retryAppliedProposalSummary(String proposalId) async {
    final proposal =
        _state.proposalById(proposalId) ??
        await _routineMutations.getProposal(proposalId);
    if (proposal?.status != AiRoutineProposalStatus.applied || isSending) {
      return;
    }
    await _sendAppliedProposalSummary(proposal!);
  }

  /// Records the outcome of a manual-food preview in the persisted chat.
  /// The actual food has already been saved by the manual-food form when this
  /// is called; this only prevents the preview card from looking pending after
  /// the user returns to the conversation.
  Future<void> completeManualFoodProposal({
    required String toolMessageId,
    required String foodId,
  }) => _updateManualFoodProposal(
    toolMessageId: toolMessageId,
    status: AiManualFoodProposalStatus.created,
    foodId: foodId,
  );

  Future<void> rejectManualFoodProposal(String toolMessageId) =>
      _updateManualFoodProposal(
        toolMessageId: toolMessageId,
        status: AiManualFoodProposalStatus.rejected,
      );

  Future<void> _updateManualFoodProposal({
    required String toolMessageId,
    required AiManualFoodProposalStatus status,
    String? foodId,
  }) async {
    final index = _state.messages.indexWhere(
      (message) =>
          message.id == toolMessageId &&
          message.toolName == 'propose_manual_food_creation',
    );
    if (index < 0) return;
    try {
      final decoded = jsonDecode(_state.messages[index].content ?? '');
      if (decoded is! Map) return;
      final resultMap = decoded.cast<String, dynamic>();
      final rawData = resultMap['data'];
      if (rawData is! Map) return;
      final proposal = AiManualFoodProposal.fromJson(
        rawData.cast<String, dynamic>(),
      ).copyWith(status: status, createdFoodId: foodId);
      resultMap['data'] = proposal.toJson();
      final result = AiToolResult.fromMap(resultMap);
      final messages = [..._state.messages];
      messages[index] = messages[index].copyWith(
        content: jsonEncode(_pruneNulls(result.toMap())),
        toolResult: result,
      );
      _state = _state.copyWith(messages: messages);
      notifyListeners();
      await _persistCurrentThread();
    } catch (_) {
      // A malformed historic tool result falls back to the generic tool card.
    }
  }

  /// Truncates messages after [fromIndex] and resends from that point.
  Future<void> retryFromMessage(int fromIndex) async {
    if (fromIndex < 0 || fromIndex >= _state.messages.length) return;
    var userIndex = fromIndex;
    while (userIndex >= 0 && !_state.messages[userIndex].isUser) {
      userIndex--;
    }
    if (userIndex < 0) {
      _state = _state.copyWith(error: 'ai_error:user_message_missing');
      notifyListeners();
      return;
    }
    final lastUser = _state.messages[userIndex];
    final remaining = _state.messages.sublist(0, userIndex);
    _state = _state.copyWith(
      messages: remaining,
      clearError: true,
      phase: AiTurnPhase.idle,
    );
    notifyListeners();
    await send(
      lastUser.content ?? '',
      existingAttachments: lastUser.attachments,
    );
  }

  Future<void> retryLastTurn() async {
    for (var i = _state.messages.length - 1; i >= 0; i--) {
      if (_state.messages[i].isUser) {
        await retryFromMessage(i);
        return;
      }
    }
  }
  // ===========================================================================
  // TURN LOOP
  // ===========================================================================

  Future<void> _runTurn({
    required List<AiChatMessage> messages,
    required String baseUrl,
    required String token,
    required String model,
    required String systemPrompt,
    required AiContextMode contextMode,
  }) async {
    var current = [...messages];
    final visionMessage = current.lastWhere((message) => message.isUser);
    final imageDataUrls = visionMessage.attachments.isEmpty
        ? const <String>[]
        : await _imageStore.readDataUrls(visionMessage.attachments);
    final latestUserText = visionMessage.content ?? '';
    final routineProposalFollowUp = _isRoutineProposalFollowUp(
      current,
      latestUserText,
    );
    final toolHints = _toolHintsForTurn(current, latestUserText);
    final manualFoodProposalTurn =
        toolHints.length == 1 &&
        toolHints.contains('propose_manual_food_creation');
    final manualFoodTextTurn = manualFoodProposalTurn && imageDataUrls.isEmpty;
    if (routineProposalFollowUp) {
      toolHints.addAll({
        'list_exercises',
        'list_routines',
        'get_routine_detail',
        'propose_routine_change',
      });
    }
    final requiresGroundedToolCall = _requiresGroundedToolCall(
      latestUserText,
      toolHints,
      routineProposalFollowUp: routineProposalFollowUp,
    );
    final contextJson = manualFoodTextTurn
        ? const <String, dynamic>{}
        : await _context.build(mode: contextMode);
    // One catalog for the whole turn: the model can pick any tool by
    // description, re-call one with new parameters and cross domains, and the
    // provider can cache the identical request prefix across rounds.
    final fullSchema = _tools.openAiChatToolsSchema();
    final manualFoodSchema = _tools.openAiChatToolsSchema(
      names: const {'propose_manual_food_creation'},
      includeRoutineProposal: false,
    );
    final historyBudget = _historyBudgetFor(
      systemPrompt: systemPrompt,
      contextJson: contextJson,
      toolsSchema: fullSchema,
    );
    final threadSummary = manualFoodTextTurn
        ? null
        : await _ensureThreadSummary(
            current: current,
            historyBudget: historyBudget,
            baseUrl: baseUrl,
            token: token,
            model: model,
          );
    final options = _TurnWireOptions(
      systemPrompt: systemPrompt,
      contextJson: contextJson,
      threadSummary: threadSummary,
      toolHints: toolHints.toList()..sort(),
      visionMessageId: visionMessage.id,
      imageDataUrls: imageDataUrls,
      historyTokenBudget: historyBudget,
    );

    int? lastPromptTokens;
    for (var round = 0; ; round++) {
      final manualFoodRound = manualFoodTextTurn && round == 0;
      final wire = manualFoodRound
          ? _buildManualFoodProposalWire(current)
          : _buildWireMessages(current, options);
      // Tools stay available while the request fits the turn budget. Beyond
      // that (or past the round cap) the model must answer with what it has.
      final inputExceeded =
          (lastPromptTokens ?? 0) > kMaxTurnInputTokens ||
          _estimateWireTokens(wire, fullSchema) > kMaxTurnInputTokens;
      final allowTools = round < kMaxToolRounds && !inputExceeded;
      final toolsSchema = !allowTools
          ? null
          : manualFoodRound
          ? manualFoodSchema
          : fullSchema;

      _state = _state.copyWith(
        phase: round == 0 ? AiTurnPhase.sending : AiTurnPhase.executingReads,
        phaseMessage: !allowTools
            ? 'finalising'
            : round == 0
            ? 'sending'
            : 'reading',
      );
      notifyListeners();

      final toolChoice = round == 0 && requiresGroundedToolCall && allowTools
          ? _requiredToolChoice()
          : 'auto';
      _activeTurnDiagnostics = _activeTurnDiagnostics?.copyWith(
        stage: !allowTools
            ? 'final_provider_request'
            : round == 0
            ? 'initial_provider_request'
            : 'followup_provider_request',
        round: round + 1,
        schemaToolCount: toolsSchema?.length ?? 0,
        requestCharacters: jsonEncode(wire).length,
        tools: toolsSchema == null
            ? const []
            : (toolsSchema
                  .map((tool) => (tool['function'] as Map)['name'] as String)
                  .toList()
                ..sort()),
      );
      var completion = manualFoodRound
          ? await _sendManualFoodProposalCompletion(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
              toolsSchema: manualFoodSchema,
              toolChoice: toolChoice,
            )
          : await _sendCompletion(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
              tools: toolsSchema,
              toolChoice: toolChoice,
              hasImages: imageDataUrls.isNotEmpty,
            );
      _calibrateTokenScale(
        wire: wire,
        toolsSchema: toolsSchema,
        promptTokens: completion.promptTokens,
      );
      lastPromptTokens = completion.promptTokens;

      if (round == 0 &&
          allowTools &&
          !manualFoodRound &&
          requiresGroundedToolCall &&
          !completion.hasToolCalls) {
        _activeTurnDiagnostics = _activeTurnDiagnostics?.copyWith(
          stage: 'required_tool_retry',
        );
        completion = await _retryMissingRequiredToolCall(
          firstCompletion: completion,
          wire: wire,
          baseUrl: baseUrl,
          token: token,
          model: model,
          toolsSchema: fullSchema,
          toolChoice: toolChoice,
          hasImages: imageDataUrls.isNotEmpty,
        );
      }

      // Persist the assistant message (may be empty if only tool calls).
      final assistant = AiChatMessage(
        id: _uuid.v4(),
        threadId: _state.activeThreadId ?? '',
        role: AiMessageRole.assistant,
        content: completion.text,
        toolCalls: completion.toolCalls,
        createdAt: DateTime.now(),
      );
      current = [...current, assistant];

      if (!completion.hasToolCalls) {
        final accepted = await _regenerateInvalidAnswer(
          completion: completion,
          current: current,
          baseUrl: baseUrl,
          token: token,
          model: model,
          options: options,
        );
        if (accepted != null) {
          current = [...current.sublist(0, current.length - 1), accepted];
        }
        // Done only after the answer has passed output validation.
        _state = _state.copyWith(
          messages: current,
          phase: AiTurnPhase.idle,
          phaseMessage: null,
          clearError: true,
        );
        notifyListeners();
        await _persistCurrentThread();
        return;
      }

      _state = _state.copyWith(messages: current);
      notifyListeners();

      final hasRoutineProposal = completion.toolCalls.any(
        (call) => call.name == 'propose_routine_change',
      );
      final hasFoodProposal = completion.toolCalls.any(
        (call) => call.name == 'propose_manual_food_creation',
      );
      final hasProposal = hasRoutineProposal || hasFoodProposal;
      _state = _state.copyWith(
        phase: hasProposal
            ? AiTurnPhase.preparingProposal
            : AiTurnPhase.executingReads,
        phaseMessage: hasFoodProposal
            ? 'preparing_food_proposal'
            : hasRoutineProposal
            ? 'preparing_proposal'
            : 'reading',
        phaseToolCount: completion.toolCalls.length,
      );
      notifyListeners();

      // Read-only calls are independent and can run concurrently. Proposal
      // preparation remains ordered and executes after all reads finish.
      final readResults = await Future.wait(
        completion.toolCalls.map((call) async {
          if (call.argumentsError != null) {
            return AiToolResult(
              ok: false,
              code: 'invalid_arguments_json',
              message:
                  '${call.argumentsError} Reenvie a chamada com um objeto '
                  'JSON válido.',
            );
          }
          if (call.name == 'propose_routine_change') return null;
          return _tools.executeRead(toolName: call.name, args: call.arguments);
        }),
      );
      var preparedManualFood = false;
      for (var i = 0; i < completion.toolCalls.length; i++) {
        final call = completion.toolCalls[i];
        final result =
            readResults[i] ??
            await _routineMutations.prepareProposal(
              threadId: _state.activeThreadId ?? '',
              toolCallId: call.id,
              args: call.arguments,
            );
        if (call.name == 'propose_routine_change' && result.ok) {
          final data = result.data as Map?;
          final proposalId = data?['proposalId'] as String?;
          if (proposalId != null) {
            final proposal = await _routineMutations.getProposal(proposalId);
            if (proposal != null) _replaceProposal(proposal, notify: false);
          }
        }
        if (call.name == 'propose_manual_food_creation' && result.ok) {
          preparedManualFood = true;
        }
        final toolMsg = AiChatMessage(
          id: _uuid.v4(),
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.tool,
          content: _encodeToolResult(result),
          toolCallId: call.id,
          toolName: call.name,
          toolResult: result,
          createdAt: DateTime.now(),
        );
        current = [...current, toolMsg];
      }
      _state = _state.copyWith(messages: current);
      notifyListeners();

      // The preview card is the final product of this turn. A second provider
      // request adds no value and several OpenAI-compatible backends reject
      // the assistant/tool transcript even after accepting the first call.
      if (preparedManualFood) {
        _state = _state.copyWith(phase: AiTurnPhase.idle, phaseMessage: null);
        notifyListeners();
        await _persistCurrentThread();
        return;
      }
    }
  }

  Future<AiChatCompletion> _sendCompletion({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    Object? toolChoice,
    required bool hasImages,
  }) {
    if (hasImages) {
      return _service.sendMultimodalChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        reasoningEffort: _activeReasoningEffort,
        messages: messages,
        tools: tools,
        toolChoice: toolChoice,
      );
    }
    return _service.sendChat(
      baseUrl: baseUrl,
      token: token,
      model: model,
      reasoningEffort: _activeReasoningEffort,
      messages: messages,
      tools: tools,
      toolChoice: toolChoice,
    );
  }

  // ===========================================================================
  // ROLLING THREAD SUMMARY
  // ===========================================================================

  /// Returns the summary of the part of [current] that no longer fits the
  /// history budget, refreshing it with one extra provider call when new
  /// messages fell out of the window. Failures degrade to the last summary.
  Future<String?> _ensureThreadSummary({
    required List<AiChatMessage> current,
    required int historyBudget,
    required String baseUrl,
    required String token,
    required String model,
  }) async {
    final threadId = _state.activeThreadId;
    if (threadId == null) return null;
    Map<String, dynamic>? existing;
    try {
      existing = await _db.getAiChatThreadSummary(threadId);
    } catch (_) {}
    final existingSummary = existing?['summary'] as String?;
    final existingThrough = existing?['through_message_id'] as String?;

    final dropped = _compactHistoryDetailed(
      current,
      tokenBudget: historyBudget,
    ).dropped;
    if (dropped.isEmpty || existingThrough == dropped.last.id) {
      return existingSummary;
    }
    var deltaStart = 0;
    if (existingThrough != null) {
      final index = dropped.indexWhere((m) => m.id == existingThrough);
      if (index >= 0) deltaStart = index + 1;
    }
    final delta = dropped.sublist(deltaStart);
    if (delta.isEmpty) return existingSummary;

    _state = _state.copyWith(phaseMessage: 'compacting');
    notifyListeners();
    _activeTurnDiagnostics = _activeTurnDiagnostics?.copyWith(
      stage: 'thread_summary',
    );
    try {
      final request = StringBuffer();
      if (existingSummary != null && existingSummary.trim().isNotEmpty) {
        request.write('Resumo atual:\n$existingSummary\n\n');
      }
      request.write(
        'Novas mensagens a incorporar:\n${_transcriptForSummary(delta)}',
      );
      final completion = await _service.sendChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        reasoningEffort: _activeReasoningEffort,
        messages: [
          const {'role': 'system', 'content': _threadSummaryPrompt},
          {'role': 'user', 'content': request.toString()},
        ],
      );
      final text = completion.text?.trim();
      if (text == null || text.isEmpty) return existingSummary;
      final summary = TextSanitizer.sanitize(text).trim();
      if (summary.isEmpty) return existingSummary;
      await _db.upsertAiChatThreadSummary(
        threadId: threadId,
        summary: summary,
        throughMessageId: dropped.last.id,
      );
      return summary;
    } catch (_) {
      return existingSummary;
    }
  }

  String _transcriptForSummary(List<AiChatMessage> messages) {
    const perMessage = 1500;
    const total = 24000;
    final buffer = StringBuffer();
    for (final message in messages) {
      final content = message.content?.trim();
      if (content == null || content.isEmpty) continue;
      final compact = content.length <= perMessage
          ? content
          : '${content.substring(0, perMessage)}…';
      final line = '${message.isUser ? 'Usuário' : 'Treinador'}: $compact\n';
      if (buffer.length + line.length > total) {
        buffer.write('[mensagens restantes omitidas por tamanho]\n');
        break;
      }
      buffer.write(line);
    }
    return buffer.toString();
  }

  @visibleForTesting
  String transcriptForSummaryForTest(List<AiChatMessage> messages) =>
      _transcriptForSummary(messages);

  // ===========================================================================
  // MANUAL FOOD FLOW
  // ===========================================================================

  List<Map<String, dynamic>> _buildManualFoodProposalWire(
    List<AiChatMessage> messages,
  ) {
    final recent = <Map<String, dynamic>>[];
    var characters = 0;
    for (var i = messages.length - 1; i >= 0 && recent.length < 6; i--) {
      final message = messages[i];
      if (!message.isUser && !message.isAssistant) continue;
      final content = message.content?.trim();
      if (content == null || content.isEmpty) continue;
      final remaining = 4000 - characters;
      if (remaining <= 0) break;
      final compact = content.length <= remaining
          ? content
          : content.substring(content.length - remaining);
      recent.insert(0, {
        'role': message.isUser ? 'user' : 'assistant',
        'content': compact,
      });
      characters += compact.length;
    }
    return [
      const {'role': 'system', 'content': _manualFoodProposalPrompt},
      ...recent,
    ];
  }

  Future<AiChatCompletion> _sendManualFoodProposalCompletion({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
    required List<Map<String, dynamic>> toolsSchema,
    required Object toolChoice,
  }) async {
    try {
      final completion = await _service.sendChat(
        baseUrl: baseUrl,
        token: token,
        model: model,
        reasoningEffort: _activeReasoningEffort,
        messages: messages,
        tools: toolsSchema,
        toolChoice: toolChoice,
      );
      if (completion.hasToolCalls) return completion;
      if (kDebugMode) {
        debugPrint(
          'AiChatService: provider ignored the required manual-food tool; '
          'retrying with JSON fallback.',
        );
      }
      return await _sendManualFoodJsonFallback(
        baseUrl: baseUrl,
        token: token,
        model: model,
        messages: messages,
      );
    } on AiServiceException catch (error) {
      if (error.code != 'http_error') rethrow;
      if (kDebugMode) {
        debugPrint(
          'AiChatService: provider rejected manual-food tool schema; '
          'retrying with JSON fallback. $error',
        );
      }
      return _sendManualFoodJsonFallback(
        baseUrl: baseUrl,
        token: token,
        model: model,
        messages: messages,
      );
    }
  }

  Future<AiChatCompletion> _sendManualFoodJsonFallback({
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> messages,
  }) async {
    final fallback = await _service.sendChat(
      baseUrl: baseUrl,
      token: token,
      model: model,
      reasoningEffort: _activeReasoningEffort,
      messages: [
        const {'role': 'system', 'content': _manualFoodJsonFallbackPrompt},
        ...messages.where((message) => message['role'] != 'system'),
      ],
    );
    final text = fallback.text?.trim();
    if (text == null || text.isEmpty) {
      throw const AiServiceException(
        'The provider returned no manual-food draft.',
        code: 'invalid_response',
      );
    }
    final arguments = _parseJsonObject(text);
    return AiChatCompletion(
      toolCalls: [
        AiToolCall(
          id: 'food_${_uuid.v4()}',
          name: 'propose_manual_food_creation',
          arguments: arguments,
        ),
      ],
      promptTokens: fallback.promptTokens,
      completionTokens: fallback.completionTokens,
    );
  }

  Map<String, dynamic> _parseJsonObject(String raw) {
    var cleaned = raw.trim();
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(cleaned);
    if (fenced != null) cleaned = fenced.group(1)!.trim();
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      cleaned = cleaned.substring(start, end + 1);
    }
    try {
      final decoded = jsonDecode(cleaned);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.cast<String, dynamic>();
    } catch (_) {}
    throw const AiServiceException(
      'The provider returned an invalid manual-food draft.',
      code: 'invalid_response',
    );
  }

  // ===========================================================================
  // ANSWER VALIDATION
  // ===========================================================================

  /// Asks once more for a tool call when a grounded turn came back without
  /// one. If the model still answers directly, that answer is accepted: a
  /// possibly less grounded reply beats failing the whole turn.
  Future<AiChatCompletion> _retryMissingRequiredToolCall({
    required AiChatCompletion firstCompletion,
    required List<Map<String, dynamic>> wire,
    required String baseUrl,
    required String token,
    required String model,
    required List<Map<String, dynamic>> toolsSchema,
    required Object toolChoice,
    required bool hasImages,
  }) async {
    var completion = firstCompletion;
    for (
      var attempt = 0;
      attempt < kMaxMissingToolCallRetries && !completion.hasToolCalls;
      attempt++
    ) {
      final retryWire = [...wire];
      final firstConversationMessage = retryWire.indexWhere(
        (message) => message['role'] != 'system',
      );
      retryWire.insert(
        firstConversationMessage < 0
            ? retryWire.length
            : firstConversationMessage,
        const {
          'role': 'system',
          'content':
              'A solicitação atual depende de dados pessoais do app. A '
              'resposta sem consulta foi rejeitada. Chame agora uma das '
              'ferramentas fornecidas e só responda depois do resultado.',
        },
      );
      try {
        completion = await _sendCompletion(
          baseUrl: baseUrl,
          token: token,
          model: model,
          messages: retryWire,
          tools: toolsSchema,
          toolChoice: toolChoice,
          hasImages: hasImages,
        );
      } catch (_) {
        break;
      }
    }
    if (!completion.hasToolCalls && kDebugMode) {
      debugPrint(
        'AiChatService: provider answered a grounded turn without tools; '
        'accepting the direct answer.',
      );
    }
    return completion.text == null && !completion.hasToolCalls
        ? firstCompletion
        : completion;
  }

  Future<AiChatMessage?> _regenerateInvalidAnswer({
    required AiChatCompletion completion,
    required List<AiChatMessage> current,
    required String baseUrl,
    required String token,
    required String model,
    required _TurnWireOptions options,
  }) async {
    var text = completion.text;
    if (text == null || !TextSanitizer.containsReferencePlaceholder(text)) {
      return null;
    }

    // The rejected answer remains in the wire transcript so the model can see
    // exactly what it must rewrite. Tool messages are also preserved in full.
    var transcript = [...current];
    for (var attempt = 0; attempt < kMaxInvalidAnswerRegenerations; attempt++) {
      transcript = [
        ...transcript,
        AiChatMessage(
          id: _uuid.v4(),
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.user,
          content:
              'A resposta anterior foi rejeitada porque deixou marcadores '
              'no lugar de valores reais. Reescreva a resposta completa agora. '
              'Copie literalmente dos resultados das ferramentas os nomes, '
              'datas e números correspondentes. Não explique a correção e não '
              'use marcadores de referência.',
          createdAt: DateTime.now(),
        ),
      ];
      final wire = _buildWireMessages(transcript, options);
      _activeTurnDiagnostics = _activeTurnDiagnostics?.copyWith(
        stage: 'answer_validation_retry',
        round: attempt + 1,
        schemaToolCount: 0,
        requestCharacters: jsonEncode(wire).length,
        tools: const [],
      );
      AiChatCompletion regenerated;
      try {
        regenerated = await _sendCompletion(
          baseUrl: baseUrl,
          token: token,
          model: model,
          messages: wire,
          hasImages: options.imageDataUrls.isNotEmpty,
        );
      } catch (_) {
        break;
      }
      text = regenerated.text;
      if (text != null && !TextSanitizer.containsReferencePlaceholder(text)) {
        return AiChatMessage(
          id: _uuid.v4(),
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.assistant,
          content: text,
          createdAt: DateTime.now(),
        );
      }
      transcript = [
        ...transcript,
        AiChatMessage(
          id: _uuid.v4(),
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.assistant,
          content: text,
          createdAt: DateTime.now(),
        ),
      ];
    }
    // Some compatible providers repeat citation placeholders even after a
    // rewrite request or throttle the rewrite itself. The narrow sanitizer is
    // the final safety net: it removes only those markers and preserves the
    // factual answer already grounded in the tool result.
    final fallback = _sanitizedAnswerFallback(completion.text);
    if (fallback != null) {
      return AiChatMessage(
        id: _uuid.v4(),
        threadId: _state.activeThreadId ?? '',
        role: AiMessageRole.assistant,
        content: fallback,
        createdAt: DateTime.now(),
      );
    }
    throw const AiServiceException(
      'A IA retornou uma resposta vazia após a validação.',
      code: 'invalid_grounded_answer',
    );
  }

  String? _sanitizedAnswerFallback(String? text) {
    if (text == null) return null;
    final sanitized = TextSanitizer.sanitize(text).trim();
    return sanitized.isEmpty ? null : sanitized;
  }

  @visibleForTesting
  String? sanitizedAnswerFallbackForTest(String? text) =>
      _sanitizedAnswerFallback(text);
  // ===========================================================================
  // INTERRUPTED-TURN RECOVERY
  // ===========================================================================

  void _recoverInterruptedTurn(List<AiChatMessage> messages) {
    // Find the last assistant message with tool_calls and check whether all
    // of them have a matching tool response.
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (!m.isAssistant || m.toolCalls.isEmpty) continue;
      final answeredIds = <String>{};
      for (var j = i + 1; j < messages.length; j++) {
        final n = messages[j];
        if (n.isTool && n.toolCallId != null) answeredIds.add(n.toolCallId!);
        if (n.isAssistant) break;
      }
      final missing = m.toolCalls
          .where((c) => !answeredIds.contains(c.id))
          .toList();
      if (missing.isEmpty) continue;
      // Synthesize interrupted responses and append.
      final synth = <AiChatMessage>[];
      for (final call in missing) {
        synth.add(
          AiChatMessage(
            id: _uuid.v4(),
            threadId: m.threadId,
            role: AiMessageRole.tool,
            content: jsonEncode({
              'ok': false,
              'code': 'interrupted',
              'message': 'Turno interrompido; resposta perdida.',
            }),
            toolCallId: call.id,
            toolName: call.name,
            createdAt: DateTime.now(),
          ),
        );
      }
      _state = _state.copyWith(messages: [..._state.messages, ...synth]);
      return;
    }
  }

  // ===========================================================================
  // ERRORS
  // ===========================================================================

  String _readableError(Object e) {
    if (e is TimeoutException) return 'ai_error:timeout';
    if (e is AiImageAttachmentException) return 'ai_error:${e.code}';
    if (e is AiServiceException) {
      return 'ai_error:${e.code ?? 'generic'}';
    }
    if (e is AiRoutineMutationException) return 'ai_error:${e.code}';
    return 'ai_error:generic';
  }

  AiChatErrorDetails _technicalErrorDetails(Object error) {
    final diagnostics = _activeTurnDiagnostics;
    final serviceError = error is AiServiceException ? error : null;
    return AiChatErrorDetails(
      code:
          serviceError?.code ??
          (error is TimeoutException ? 'timeout' : 'generic'),
      stage: diagnostics?.stage ?? 'unknown',
      message: _safeTechnicalMessage(serviceError?.message ?? error.toString()),
      httpStatus: serviceError?.statusCode,
      endpoint: _safeEndpoint(serviceError?.endpoint),
      provider: diagnostics?.provider,
      model: diagnostics?.model,
      round: diagnostics?.round,
      schemaToolCount: diagnostics?.schemaToolCount,
      requestCharacters: diagnostics?.requestCharacters,
      tools: diagnostics?.tools ?? const [],
      providerAttempts: serviceError?.attemptCount,
      compatibilityAdjustments:
          serviceError?.compatibilityAdjustments ?? const [],
    );
  }

  String _safeTechnicalMessage(String message) {
    var safe = message
        .replaceAll(
          RegExp(
            r'(bearer|api[_-]?key|token)\s*[:=]?\s*[^\s,;]+',
            caseSensitive: false,
          ),
          r'$1 [oculto]',
        )
        .replaceAll(
          RegExp(r'sk-[a-z0-9_-]+', caseSensitive: false),
          '[chave oculta]',
        )
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .trim();
    if (safe.length > 360) safe = '${safe.substring(0, 357)}…';
    return safe;
  }

  String? _safeEndpoint(String? endpoint) {
    if (endpoint == null) return null;
    final uri = Uri.tryParse(endpoint);
    if (uri == null) return null;
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}${uri.path}';
  }
}

class _AiTurnDiagnostics {
  final String stage;
  final String provider;
  final String model;
  final int? round;
  final int? schemaToolCount;
  final int? requestCharacters;
  final List<String> tools;

  const _AiTurnDiagnostics({
    required this.stage,
    required this.provider,
    required this.model,
    this.round,
    this.schemaToolCount,
    this.requestCharacters,
    this.tools = const [],
  });

  _AiTurnDiagnostics copyWith({
    String? stage,
    int? round,
    int? schemaToolCount,
    int? requestCharacters,
    List<String>? tools,
  }) => _AiTurnDiagnostics(
    stage: stage ?? this.stage,
    provider: provider,
    model: model,
    round: round ?? this.round,
    schemaToolCount: schemaToolCount ?? this.schemaToolCount,
    requestCharacters: requestCharacters ?? this.requestCharacters,
    tools: tools ?? this.tools,
  );
}
