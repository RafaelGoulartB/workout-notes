import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../models/ai_chat_message.dart';
import '../models/ai_image_attachment.dart';
import '../models/ai_chat_state.dart';
import '../models/ai_chat_thread.dart';
import '../models/ai_message_role.dart';
import '../models/ai_provider.dart';
import '../models/ai_routine_proposal.dart';
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

const int kMaxToolRounds = 3;
const int kHistoryTokenBudget = 6000;
const int kTargetInputTokenBudget = 7000;
const int kMinHistoryTokenBudget = 1200;
const int kMaxInvalidAnswerRegenerations = 2;
const int kMaxMissingToolCallRetries = 1;
const String _dataGroundingPolicy = r'''# Consulta obrigatória aos dados do app
As ferramentas são a fonte primária para fatos pessoais do usuário. Quando a solicitação depender de treino, sono, nutrição, medidas, metas, rotinas ou qualquer outro dado registrado, consulte a ferramenta relevante neste turno antes de responder. Não substitua a consulta por conhecimento geral, inferência ou lembrança de uma resposta anterior.

Interprete continuações usando a conversa recente. Se o usuário mudar apenas o domínio, preserve os qualificadores ainda aplicáveis do pedido anterior, especialmente período, comparação e objetivo. Exemplo: depois de um resumo da última semana, "E o sono?" exige consultar o resumo de sono para o mesmo período. O usuário nunca precisa pedir explicitamente que você use uma tool.

Use `discover_app_capabilities` somente quando a ferramenta necessária não estiver entre as ferramentas diretas disponíveis. Se uma consulta falhar ou não tiver registros suficientes, informe isso; nunca complete a lacuna com dados inventados.''';
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
    await svc.refreshThreads();
    await svc._cleanupOrphanedImages();
    return svc;
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
  // THREAD MANAGEMENT
  // ===========================================================================

  // ===========================================================================
  // SENDING
  // ===========================================================================

  Future<bool> send(
    String text, {
    List<AiPendingImage> images = const [],
    List<AiImageAttachment> existingAttachments = const [],
    VoidCallback? onAccepted,
  }) async {
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
        phaseMessage: null,
      );
      notifyListeners();
      await _persistCurrentThread();
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
    final latestUserText =
        current.lastWhere((message) => message.isUser).content ?? '';
    final routineProposalFollowUp = _isRoutineProposalFollowUp(
      current,
      latestUserText,
    );
    var toolNames = _toolNamesForTurn(current, latestUserText);
    if (routineProposalFollowUp) {
      toolNames.addAll({
        'list_exercises',
        'list_routines',
        'get_routine_detail',
      });
    }
    var proposalAvailable = false;
    var routineCapabilityActive =
        routineProposalFollowUp ||
        toolNames.any(
          const {
            'list_routines',
            'get_routine_detail',
            'list_exercises',
          }.contains,
        );
    final requiresGroundedToolCall = _requiresGroundedToolCall(
      latestUserText,
      toolNames,
      routineProposalFollowUp: routineProposalFollowUp,
    );
    _context.invalidate();
    final contextJson = await _context.build(mode: contextMode);

    for (var round = 0; round < kMaxToolRounds + 1; round++) {
      final toolsSchema = _tools.openAiChatToolsSchema(
        names: toolNames,
        includeRoutineProposal: proposalAvailable,
      );
      final wire = _buildWireMessages(
        current,
        systemPrompt: systemPrompt,
        contextJson: contextJson,
        includeRoutinePolicy: routineCapabilityActive || proposalAvailable,
        visionMessageId: visionMessage.id,
        imageDataUrls: imageDataUrls,
        historyTokenBudget: _historyBudgetFor(
          systemPrompt: systemPrompt,
          contextJson: contextJson,
          toolsSchema: toolsSchema,
          includeRoutinePolicy: routineCapabilityActive || proposalAvailable,
        ),
      );

      _state = _state.copyWith(
        phase: round == 0 ? AiTurnPhase.sending : AiTurnPhase.executingReads,
        phaseMessage: round == 0 ? 'sending' : 'reading',
      );
      notifyListeners();

      final toolChoice = round == 0 && requiresGroundedToolCall
          ? _requiredToolChoice(toolNames)
          : 'auto';
      var completion = imageDataUrls.isEmpty
          ? await _service.sendChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
              tools: toolsSchema,
              toolChoice: toolChoice,
            )
          : await _service.sendMultimodalChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
              tools: toolsSchema,
              toolChoice: toolChoice,
            );

      if (round == 0 && requiresGroundedToolCall && !completion.hasToolCalls) {
        completion = await _retryMissingRequiredToolCall(
          firstCompletion: completion,
          wire: wire,
          baseUrl: baseUrl,
          token: token,
          model: model,
          toolsSchema: toolsSchema,
          toolChoice: toolChoice,
          hasImages: imageDataUrls.isNotEmpty,
        );
      }

      // Persist the assistant message (may be empty if only tool calls).
      final assistant = AiChatMessage(
        id: _uuid.v4(),
        threadId: _state.activeThreadId ?? '',
        role: AiMessageRole.assistant,
        content: _formatCompletion(completion, current),
        toolCalls: completion.toolCalls,
        createdAt: DateTime.now(),
      );
      current = [...current, assistant];
      _state = _state.copyWith(messages: current);
      notifyListeners();

      if (!completion.hasToolCalls) {
        final accepted = await _regenerateInvalidAnswer(
          completion: completion,
          current: current,
          baseUrl: baseUrl,
          token: token,
          model: model,
          systemPrompt: systemPrompt,
          contextJson: contextJson,
          includeRoutinePolicy: routineCapabilityActive || proposalAvailable,
          visionMessageId: visionMessage.id,
          imageDataUrls: imageDataUrls,
        );
        if (accepted != null) {
          current = [...current.sublist(0, current.length - 1), accepted];
          _state = _state.copyWith(messages: current);
        }
        // Done only after the answer has passed output validation.
        _state = _state.copyWith(phase: AiTurnPhase.idle, phaseMessage: null);
        notifyListeners();
        await _persistCurrentThread();
        return;
      }

      // Execute reads sequentially; tool-call order is preserved.
      final hasProposal = completion.toolCalls.any(
        (call) => call.name == 'propose_routine_change',
      );
      _state = _state.copyWith(
        phase: hasProposal
            ? AiTurnPhase.preparingProposal
            : AiTurnPhase.executingReads,
        phaseMessage: hasProposal ? 'preparing_proposal' : 'reading',
        phaseToolCount: completion.toolCalls.length,
      );
      notifyListeners();

      // Read-only calls are independent and can run concurrently. Proposal
      // preparation remains ordered and executes after all reads finish.
      final readResults = await Future.wait(
        completion.toolCalls.map((call) async {
          if (call.name == 'propose_routine_change') return null;
          return _tools.executeRead(toolName: call.name, args: call.arguments);
        }),
      );
      for (var i = 0; i < completion.toolCalls.length; i++) {
        final call = completion.toolCalls[i];
        final result = call.name == 'propose_routine_change'
            ? await _routineMutations.prepareProposal(
                threadId: _state.activeThreadId ?? '',
                toolCallId: call.id,
                args: call.arguments,
              )
            : readResults[i]!;
        if (call.name == 'propose_routine_change' && result.ok) {
          final data = result.data as Map?;
          final proposalId = data?['proposalId'] as String?;
          if (proposalId != null) {
            final proposal = await _routineMutations.getProposal(proposalId);
            if (proposal != null) _replaceProposal(proposal, notify: false);
          }
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

      final calledNames = completion.toolCalls.map((call) => call.name).toSet();
      final discoveredNames = <String>{};
      for (var i = 0; i < completion.toolCalls.length; i++) {
        if (completion.toolCalls[i].name != 'discover_app_capabilities') {
          continue;
        }
        final data = readResults[i]?.data;
        if (data is Map) {
          discoveredNames.addAll(
            (data['tools'] as List? ?? const []).whereType<String>(),
          );
        }
      }
      routineCapabilityActive =
          routineCapabilityActive ||
          discoveredNames.any(
            const {
              'list_routines',
              'get_routine_detail',
              'list_exercises',
              'propose_routine_change',
            }.contains,
          );
      final followUpNames = _tools.followUpToolNames(
        calledNames,
        routineIntent: routineCapabilityActive,
      );
      toolNames = {
        ...followUpNames,
        ...discoveredNames.where((name) => name != 'propose_routine_change'),
      };
      proposalAvailable =
          proposalAvailable ||
          discoveredNames.contains('propose_routine_change') ||
          (routineCapabilityActive &&
              calledNames.any(
                (name) =>
                    name == 'list_exercises' || name == 'get_routine_detail',
              ));
      if (calledNames.contains('propose_routine_change')) {
        proposalAvailable = false;
      }

      if (round == kMaxToolRounds) {
        // Force final answer with no tools.
        _state = _state.copyWith(
          phase: AiTurnPhase.sending,
          phaseMessage: 'finalising',
        );
        notifyListeners();
        final finalWire = _buildWireMessages(
          current,
          systemPrompt: systemPrompt,
          contextJson: contextJson,
          includeRoutinePolicy: routineCapabilityActive || proposalAvailable,
          visionMessageId: visionMessage.id,
          imageDataUrls: imageDataUrls,
        );
        final finalCompletion = imageDataUrls.isEmpty
            ? await _service.sendChat(
                baseUrl: baseUrl,
                token: token,
                model: model,
                messages: finalWire,
              )
            : await _service.sendMultimodalChat(
                baseUrl: baseUrl,
                token: token,
                model: model,
                messages: finalWire,
              );
        final candidate = AiChatMessage(
          id: _uuid.v4(),
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.assistant,
          content: finalCompletion.text,
          createdAt: DateTime.now(),
        );
        current = [...current, candidate];
        final accepted = await _regenerateInvalidAnswer(
          completion: finalCompletion,
          current: current,
          baseUrl: baseUrl,
          token: token,
          model: model,
          systemPrompt: systemPrompt,
          contextJson: contextJson,
          includeRoutinePolicy: routineCapabilityActive || proposalAvailable,
          visionMessageId: visionMessage.id,
          imageDataUrls: imageDataUrls,
        );
        final finalAssistant = AiChatMessage(
          id: accepted?.id ?? candidate.id,
          threadId: _state.activeThreadId ?? '',
          role: AiMessageRole.assistant,
          content: accepted?.content ?? finalCompletion.text,
          createdAt: DateTime.now(),
        );
        current = [...current.sublist(0, current.length - 1), finalAssistant];
        _state = _state.copyWith(
          messages: current,
          phase: AiTurnPhase.idle,
          phaseMessage: null,
        );
        notifyListeners();
        await _persistCurrentThread();
        return;
      }
    }
  }

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
      completion = hasImages
          ? await _service.sendMultimodalChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: retryWire,
              tools: toolsSchema,
              toolChoice: toolChoice,
            )
          : await _service.sendChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: retryWire,
              tools: toolsSchema,
              toolChoice: toolChoice,
            );
    }
    if (!completion.hasToolCalls) {
      throw const AiServiceException(
        'O provedor respondeu sem consultar os dados obrigatórios do app. '
        'Tente novamente ou use outro modelo com suporte a tool calls.',
        code: 'required_tool_call_missing',
      );
    }
    return completion;
  }

  Future<AiChatMessage?> _regenerateInvalidAnswer({
    required AiChatCompletion completion,
    required List<AiChatMessage> current,
    required String baseUrl,
    required String token,
    required String model,
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    required bool includeRoutinePolicy,
    String? visionMessageId,
    List<String> imageDataUrls = const [],
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
      final wire = _buildWireMessages(
        transcript,
        systemPrompt: systemPrompt,
        contextJson: contextJson,
        includeRoutinePolicy: includeRoutinePolicy,
        visionMessageId: visionMessageId,
        imageDataUrls: imageDataUrls,
      );
      final regenerated = imageDataUrls.isEmpty
          ? await _service.sendChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
            )
          : await _service.sendMultimodalChat(
              baseUrl: baseUrl,
              token: token,
              model: model,
              messages: wire,
            );
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
    // Do not silently erase placeholders or fabricate a local summary.
    throw const AiServiceException(
      'A IA não conseguiu preencher os dados retornados pelas ferramentas. '
      'Tente novamente.',
      code: 'invalid_grounded_answer',
    );
  }
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
  // PERSISTENCE
  // ===========================================================================
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

  String? _formatCompletion(
    AiChatCompletion completion,
    Iterable<AiChatMessage> messages,
  ) {
    return completion.text;
  }
}
