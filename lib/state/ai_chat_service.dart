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

const _uuid = Uuid();

const int kMaxToolRounds = 3;
const int kHistoryTokenBudget = 6000;
const int kTargetInputTokenBudget = 7000;
const int kMinHistoryTokenBudget = 1200;
const int kMaxInvalidAnswerRegenerations = 2;
const String _routineMutationPolicy = r'''# Propostas de rotina (política fixa)
Você pode preparar uma proposta de rotina somente quando o usuário pedir explicitamente para criar, montar, editar, alterar, adicionar ou remover conteúdo de uma rotina. Nunca proponha alterações apenas por sugestão, análise ou pergunta hipotética.

Quando houver esse pedido, você DEVE usar ferramentas; não responda dizendo que não consegue criar a rotina. Siga este fluxo:
1. Para criação, chame `list_exercises` para obter IDs reais dos exercícios necessários.
2. Para edição, chame `list_routines` e depois `get_routine_detail`; preserve os campos `source_*_id` retornados.
3. Seja proativo: se faltarem nome, divisão, séries, repetições ou descanso, NÃO peça uma lista de detalhes. Use a solicitação atual, a conversa anterior e os dados do app para decidir. Se o usuário disser “crie essa rotina”, a rotina mencionada/sugerida anteriormente na conversa é a especificação principal.
4. Na ausência de preferência explícita, escolha uma divisão equilibrada coerente com a frequência e os grupos musculares disponíveis, 3 séries de trabalho por exercício, faixas de 8–12 repetições para musculação e 90 segundos de descanso. Dê um nome descritivo à rotina. Essas escolhas são uma prévia segura porque o usuário ainda precisa aprovar.
5. Chame `propose_routine_change` com a árvore final completa. Campos opcionais podem ser omitidos; não escreva null se não precisar do campo.
6. Só faça uma pergunta em vez de propor se não houver exercício compatível na biblioteca ou se houver uma restrição de segurança relevante. Caso contrário, sempre entregue a proposta para aprovação.
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

  Future<void> refreshThreads({bool notify = true}) async {
    try {
      final rows = await _db.getAiChatThreads();
      _state = _state.copyWith(
        threads: rows.map(AiChatThread.fromRow).toList(),
      );
      if (notify) notifyListeners();
    } catch (_) {}
  }

  Future<void> newChat() async {
    if (_state.activeThreadId == null && _state.messages.isEmpty) return;
    _state = _state.copyWith(
      clearActiveThread: true,
      messages: const [],
      clearError: true,
      phase: AiTurnPhase.idle,
    );
    notifyListeners();
  }

  Future<void> openThread(String threadId) async {
    if (_state.activeThreadId == threadId) return;
    try {
      final rows = await _db.getAiChatMessagesThread(threadId);
      final messages = rows.map(AiChatMessage.fromRow).toList();
      final proposals = await _routineMutations.getThreadProposals(threadId);
      _state = _state.copyWith(
        activeThreadId: threadId,
        messages: messages,
        clearError: true,
        phase: AiTurnPhase.idle,
        routineProposals: proposals,
      );
      _recoverInterruptedTurn(messages);
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      notifyListeners();
    }
  }

  Future<void> deleteThread(String threadId) async {
    var attachments = <AiImageAttachment>[];
    try {
      final rows = await _db.getAiChatMessagesThread(threadId);
      attachments = rows
          .map(AiChatMessage.fromRow)
          .expand((message) => message.attachments)
          .toList();
    } catch (_) {}
    try {
      await _db.deleteAiChatThread(threadId);
      await _imageStore.deleteAll(attachments);
      final threads = _state.threads.where((t) => t.id != threadId).toList();
      final clearActive = _state.activeThreadId == threadId;
      _state = _state.copyWith(
        threads: threads,
        clearActiveThread: clearActive,
        messages: clearActive ? const [] : _state.messages,
      );
      notifyListeners();
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      notifyListeners();
    }
  }

  Future<bool> renameThread(String threadId, String title) async {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return false;
    try {
      await _db.renameAiChatThread(threadId, trimmed);
      await refreshThreads(notify: false);
      _state = _state.copyWith(clearError: true);
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      notifyListeners();
      return false;
    }
  }

  Future<bool> setThreadPinned(String threadId, bool isPinned) async {
    try {
      await _db.setAiChatThreadPinned(threadId, isPinned);
      await refreshThreads(notify: false);
      _state = _state.copyWith(clearError: true);
      notifyListeners();
      return true;
    } catch (e) {
      _state = _state.copyWith(error: _readableError(e));
      notifyListeners();
      return false;
    }
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
        error: _readableError(e),
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
    final explicitRoutineTurn = _hasExplicitRoutineIntent(current);
    final latestUserText =
        current.lastWhere((message) => message.isUser).content ?? '';
    var toolNames = _tools.toolNamesForQuery(
      _routingQuery(current, latestUserText),
    );
    var proposalAvailable = false;
    _context.invalidate();
    final contextJson = await _context.build(mode: contextMode);

    for (var round = 0; round < kMaxToolRounds + 1; round++) {
      final toolsSchema = _tools.openAiChatToolsSchema(
        names: toolNames,
        includeRoutineProposal: explicitRoutineTurn && proposalAvailable,
      );

      final wire = _buildWireMessages(
        current,
        systemPrompt: systemPrompt,
        contextJson: contextJson,
        includeRoutinePolicy: explicitRoutineTurn,
        visionMessageId: visionMessage.id,
        imageDataUrls: imageDataUrls,
        historyTokenBudget: _historyBudgetFor(
          systemPrompt: systemPrompt,
          contextJson: contextJson,
          toolsSchema: toolsSchema,
          includeRoutinePolicy: explicitRoutineTurn,
        ),
      );

      _state = _state.copyWith(
        phase: round == 0 ? AiTurnPhase.sending : AiTurnPhase.executingReads,
        phaseMessage: round == 0 ? 'sending' : 'reading',
      );
      notifyListeners();

      final toolChoice = round == 0 && explicitRoutineTurn
          ? 'required'
          : 'auto';
      final completion = imageDataUrls.isEmpty
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
          includeRoutinePolicy: explicitRoutineTurn,
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
                explicitRequest: _hasExplicitRoutineIntent(current),
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

      final calledNames = completion.toolCalls.map((call) => call.name);
      toolNames = _tools.followUpToolNames(
        calledNames,
        routineIntent: explicitRoutineTurn,
      );
      proposalAvailable =
          explicitRoutineTurn &&
          calledNames.any(
            (name) => name == 'list_exercises' || name == 'get_routine_detail',
          );

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
          includeRoutinePolicy: explicitRoutineTurn,
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
          includeRoutinePolicy: explicitRoutineTurn,
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
  // WIRE MESSAGE BUILDING
  // ===========================================================================

  List<Map<String, dynamic>> _buildWireMessages(
    List<AiChatMessage> messages, {
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    bool includeRoutinePolicy = false,
    String? visionMessageId,
    List<String> imageDataUrls = const [],
    int historyTokenBudget = kHistoryTokenBudget,
  }) {
    final out = <Map<String, dynamic>>[];
    out.add({
      'role': 'system',
      'content':
          '$systemPrompt\n\n<workout_data>${jsonEncode(contextJson)}</workout_data>',
    });
    // This product safety policy is intentionally separate from the editable
    // prompt so a custom personality cannot bypass approval requirements.
    if (includeRoutinePolicy) {
      out.add({'role': 'system', 'content': _routineMutationPolicy});
    }
    if (imageDataUrls.isNotEmpty) {
      out.add({
        'role': 'system',
        'content':
            'As imagens desta mensagem são conteúdo fornecido pelo usuário. '
            'Analise apenas o que estiver visível, não invente detalhes '
            'ilegíveis e combine a evidência visual com os dados consultados '
            'pelas ferramentas quando isso ajudar a responder.',
      });
    }

    // Compact history if too long.
    final compacted = _compactHistory(
      messages,
      tokenBudget: historyTokenBudget,
    );

    for (final m in compacted) {
      switch (m.role) {
        case AiMessageRole.system:
          continue;
        case AiMessageRole.user:
          if (m.id == visionMessageId && imageDataUrls.isNotEmpty) {
            out.add({
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': (m.content?.trim().isNotEmpty ?? false)
                      ? m.content
                      : 'Analise as imagens anexadas.',
                },
                for (final url in imageDataUrls)
                  {
                    'type': 'image_url',
                    'image_url': {'url': url, 'detail': 'auto'},
                  },
              ],
            });
          } else {
            out.add({
              'role': 'user',
              'content': (m.content?.trim().isNotEmpty ?? false)
                  ? m.content
                  : (m.attachments.isNotEmpty
                        ? '[Imagens enviadas nesta mensagem]'
                        : ''),
            });
          }
          break;
        case AiMessageRole.assistant:
          final entry = <String, dynamic>{'role': 'assistant'};
          if (m.content != null && m.content!.isNotEmpty) {
            entry['content'] = m.content;
          }
          if (m.toolCalls.isNotEmpty) {
            entry['tool_calls'] = m.toolCalls.map((c) => c.toJson()).toList();
          }
          out.add(entry);
          break;
        case AiMessageRole.tool:
          out.add({
            'role': 'tool',
            'tool_call_id': m.toolCallId ?? '',
            'content': m.content ?? '',
          });
          break;
      }
    }
    return out;
  }

  /// Drops oldest user/assistant blocks until total estimated tokens <= budget.
  List<AiChatMessage> _compactHistory(
    List<AiChatMessage> messages, {
    int tokenBudget = kHistoryTokenBudget,
  }) {
    if (messages.isEmpty) return messages;

    // Tool transcripts are useful only while the current user turn is still
    // running. Once a final answer exists, retain that answer and discard old
    // tool arguments/results from the wire payload. They remain persisted for
    // the UI, but are not repeatedly billed on every future message.
    var lastUserIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) {
        lastUserIndex = i;
        break;
      }
    }
    final normalized = <AiChatMessage>[];
    for (var i = 0; i < messages.length; i++) {
      final message = messages[i];
      if (i < lastUserIndex &&
          (message.isTool ||
              (message.isAssistant && message.toolCalls.isNotEmpty))) {
        continue;
      }
      normalized.add(message);
    }

    final total = _estimateTokens(normalized);
    if (total <= tokenBudget) return normalized;

    // Compact whole user turns. A tool result without its preceding assistant
    // tool_call is an invalid transcript and prevents the model from reliably
    // grounding its answer in that result.
    final turns = <List<AiChatMessage>>[];
    List<AiChatMessage>? turn;
    for (final message in normalized) {
      if (message.isUser) {
        turn = <AiChatMessage>[];
        turns.add(turn);
      }
      turn?.add(message);
    }
    if (turns.isEmpty) return normalized;

    final keep = <AiChatMessage>[];
    var running = 0;
    for (var i = turns.length - 1; i >= 0; i--) {
      final candidate = turns[i];
      final est = _estimateTokens(candidate);
      if (running + est > tokenBudget && keep.isNotEmpty) break;
      keep.insertAll(0, candidate);
      running += est;
    }
    return keep;
  }

  @visibleForTesting
  List<AiChatMessage> compactHistoryForTest(List<AiChatMessage> messages) =>
      _compactHistory(messages);

  @visibleForTesting
  List<Map<String, dynamic>> buildWireMessagesForTest(
    List<AiChatMessage> messages, {
    bool includeRoutinePolicy = false,
    String? visionMessageId,
    List<String> imageDataUrls = const [],
  }) => _buildWireMessages(
    messages,
    systemPrompt: 'system',
    contextJson: const {},
    includeRoutinePolicy: includeRoutinePolicy,
    visionMessageId: visionMessageId,
    imageDataUrls: imageDataUrls,
  );

  int _estimateTokens(List<AiChatMessage> messages) {
    var total = 0;
    for (final m in messages) {
      total += _estimateMessageTokens(m);
    }
    return total;
  }

  int _estimateMessageTokens(AiChatMessage m) {
    return TokenEstimator.estimateMessage(
      role: m.role.wireValue,
      content: m.content,
      toolName: m.toolName,
      toolCallArguments: m.toolCalls.isEmpty
          ? null
          : jsonEncode(m.toolCalls.map((c) => c.arguments).toList()),
    );
  }

  int _historyBudgetFor({
    required String systemPrompt,
    required Map<String, dynamic> contextJson,
    required List<Map<String, dynamic>> toolsSchema,
    required bool includeRoutinePolicy,
  }) {
    final fixedTokens =
        TokenEstimator.estimateText(systemPrompt) +
        (includeRoutinePolicy
            ? TokenEstimator.estimateText(_routineMutationPolicy)
            : 0) +
        TokenEstimator.estimateText(jsonEncode(contextJson)) +
        TokenEstimator.estimateText(jsonEncode(toolsSchema)) +
        80;
    return (kTargetInputTokenBudget - fixedTokens).clamp(
      kMinHistoryTokenBudget,
      kHistoryTokenBudget,
    );
  }

  String _routingQuery(List<AiChatMessage> messages, String latestUserText) {
    final normalized = latestUserText.trim().toLowerCase();
    final looksLikeFollowUp =
        normalized.length <= 80 &&
        (normalized.startsWith('e ') ||
            normalized.contains('isso') ||
            normalized.contains('essa') ||
            normalized.contains('esse') ||
            normalized.contains('agora') ||
            normalized.contains('esta semana') ||
            normalized.contains('última semana'));
    if (!looksLikeFollowUp) return latestUserText;
    for (var i = messages.length - 2; i >= 0; i--) {
      final message = messages[i];
      if (message.isUser && (message.content?.trim().isNotEmpty ?? false)) {
        return '${message.content}\n$latestUserText';
      }
    }
    return latestUserText;
  }

  String _encodeToolResult(AiToolResult result) =>
      jsonEncode(_pruneNulls(result.toMap()));

  dynamic _pruneNulls(dynamic value) {
    if (value is Map) {
      return {
        for (final entry in value.entries)
          if (entry.value != null) '${entry.key}': _pruneNulls(entry.value),
      };
    }
    if (value is List) return value.map(_pruneNulls).toList();
    return value;
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

  Future<String> _ensureThread(
    List<AiChatMessage> messages,
    DateTime now,
    String firstUserText,
  ) async {
    if (_state.activeThreadId != null) return _state.activeThreadId!;
    final id = _uuid.v4();
    final title = firstUserText.length > 48
        ? '${firstUserText.substring(0, 45)}…'
        : firstUserText;
    final resolvedTitle = title.isEmpty ? 'Nova conversa' : title;
    final preview = firstUserText.length > 96
        ? '${firstUserText.substring(0, 93)}…'
        : firstUserText;
    await _db.upsertAiChatThread(
      id: id,
      title: resolvedTitle,
      createdAt: now,
      updatedAt: now,
      lastMessagePreview: preview,
      isPinned: false,
    );
    // Keep the just-created thread in memory before the first turn is
    // persisted. Otherwise `_persistCurrentThread` cannot resolve it and
    // overwrites its descriptive title with the generic fallback "Conversa".
    _state = _state.copyWith(
      threads: [
        AiChatThread(
          id: id,
          title: resolvedTitle,
          createdAt: now,
          updatedAt: now,
          lastMessagePreview: preview,
        ),
        ..._state.threads,
      ],
    );
    return id;
  }

  Future<void> _persistCurrentThread() async {
    final id = _state.activeThreadId;
    if (id == null) return;
    try {
      final preview = _lastUserOrAssistantPreview();
      await _db.upsertAiChatThread(
        id: id,
        title: _state.activeThread?.title ?? 'Conversa',
        createdAt: _state.activeThread?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
        lastMessagePreview: preview,
        isPinned: _state.activeThread?.isPinned ?? false,
      );
      final rows = _state.messages
          .where((m) => m.role != AiMessageRole.system)
          .map((m) => m.toRow()..['thread_id'] = id)
          .toList();
      await _db.replaceAiChatMessages(id, rows);
      await refreshThreads();
    } catch (_) {}
  }

  bool _hasExplicitRoutineIntent(List<AiChatMessage> messages) {
    AiChatMessage? lastUser;
    for (final message in messages.reversed) {
      if (message.isUser) {
        lastUser = message;
        break;
      }
    }
    if (lastUser == null) return false;
    final text = (lastUser.content ?? '').toLowerCase();
    if (!RegExp(
      r'\b(rotina|routine|treino)\b',
      caseSensitive: false,
    ).hasMatch(text)) {
      return false;
    }
    return RegExp(
      r'\b(cria|crie|criar|monta|monte|montar|edita|edite|editar|altera|altere|alterar|adiciona|adicione|adicionar|remove|remova|remover|troca|troque|substitua|faça|faca|make|create|edit|change|add)\b',
      caseSensitive: false,
    ).hasMatch(text);
  }

  void _replaceProposal(AiRoutineProposal proposal, {bool notify = true}) {
    final proposals = [..._state.routineProposals];
    final index = proposals.indexWhere((item) => item.id == proposal.id);
    if (index == -1) {
      proposals.add(proposal);
    } else {
      proposals[index] = proposal;
    }
    _state = _state.copyWith(routineProposals: proposals);
    if (notify) notifyListeners();
  }

  Future<void> _sendAppliedProposalSummary(AiRoutineProposal proposal) async {
    if (_settings == null || !_settings!.isConfigured) return;
    final provider = _settings!.activeProvider!;
    final token = await _settings!.getToken(provider.id);
    if (token == null || token.isEmpty || provider.selectedModel.isEmpty) {
      return;
    }
    _state = _state.copyWith(
      phase: AiTurnPhase.sending,
      phaseMessage: 'finalising',
      clearError: true,
    );
    notifyListeners();
    try {
      final context = await _context.build(mode: _settings!.contextMode);
      final wire = _buildWireMessages(
        _state.messages,
        systemPrompt: _settings!.effectiveSystemPrompt,
        contextJson: context,
      );
      wire.add({
        'role': 'user',
        'content':
            'EVENTO INTERNO DO APP: a proposta foi aplicada com sucesso. Responda agora, em português brasileiro, com um resumo breve e factual do que foi feito. Não use ferramentas e não diga que houve aprovação pendente. Dados confirmados: ${jsonEncode({'action': proposal.action.storageValue, 'routineName': proposal.routineName, 'routineId': proposal.appliedRoutineId, 'diff': proposal.diff})}',
      });
      final completion = await _service.sendChat(
        baseUrl: provider.baseUrl,
        token: token,
        model: provider.selectedModel,
        messages: wire,
      );
      final text = completion.text?.trim();
      if (text == null || text.isEmpty) {
        throw const AiServiceException(
          'Resumo vazio.',
          code: 'invalid_response',
        );
      }
      final summary = AiChatMessage(
        id: _uuid.v4(),
        threadId: _state.activeThreadId ?? '',
        role: AiMessageRole.assistant,
        content: text,
        createdAt: DateTime.now(),
      );
      _state = _state.copyWith(
        messages: [..._state.messages, summary],
        phase: AiTurnPhase.idle,
        phaseMessage: null,
      );
      await _db.updateAiRoutineProposal(proposal.id, {
        'error_code': null,
        'error_message': null,
      });
      final refreshed = await _routineMutations.getProposal(proposal.id);
      if (refreshed != null) _replaceProposal(refreshed, notify: false);
      notifyListeners();
      await _persistCurrentThread();
    } catch (_) {
      // The routine is already committed. Keep it applied and expose a retry
      // on the proposal card instead of risking a second mutation.
      await _db.updateAiRoutineProposal(proposal.id, {
        'error_code': 'summary_pending',
        'error_message': 'Resumo da IA pendente.',
      });
      final refreshed = await _routineMutations.getProposal(proposal.id);
      if (refreshed != null) _replaceProposal(refreshed, notify: false);
      _state = _state.copyWith(phase: AiTurnPhase.idle, phaseMessage: null);
      notifyListeners();
    }
  }

  String? _lastUserOrAssistantPreview() {
    for (var i = _state.messages.length - 1; i >= 0; i--) {
      final m = _state.messages[i];
      if (m.isUser || m.isAssistant) {
        final text = m.content;
        if (text == null || text.isEmpty) continue;
        return text.length > 96 ? '${text.substring(0, 93)}…' : text;
      }
    }
    return null;
  }

  // ===========================================================================

  String _readableError(Object e) {
    if (e is TimeoutException) return 'ai_error:timeout';
    if (e is AiImageAttachmentException) return 'ai_error:${e.code}';
    if (e is AiServiceException) {
      return 'ai_error:${e.code ?? 'generic'}';
    }
    return 'ai_error:generic';
  }

  String? _formatCompletion(
    AiChatCompletion completion,
    Iterable<AiChatMessage> messages,
  ) {
    return completion.text;
  }
}
