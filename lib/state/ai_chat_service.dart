import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_chat_error_details.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_state.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/models/ai_provider.dart';
import 'package:workout_notes/models/ai_tool_call.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/services/ai_context_service.dart';
import 'package:workout_notes/services/ai_image_attachment_store.dart';
import 'package:workout_notes/services/ai_memory_service.dart';
import 'package:workout_notes/services/ai_prompts.dart';
import 'package:workout_notes/services/ai_proposal_service.dart';
import 'package:workout_notes/services/ai_service.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/utils/ai_endpoint_policy.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/utils/text_sanitizer.dart';
import 'package:workout_notes/utils/token_estimator.dart';

part 'ai_chat_persistence.dart';
part 'ai_chat_threads.dart';
part 'ai_chat_turn.dart';
part 'ai_chat_wire.dart';

const _uuid = Uuid();

/// Upper bound on provider rounds per turn. The real limiter is
/// [kMaxTurnInputTokens]; this only stops a model that loops forever.
const int kMaxToolRounds = 10;

/// Once a request is estimated (or reported) above this, the next round is
/// the final one: same tools, `tool_choice: none`, the model must answer.
const int kMaxTurnInputTokens = 60000;

/// Target size of a request at the start of a turn (static prompt + tools +
/// summary + history). History beyond it is folded into the summary.
const int kTargetInputTokens = 36000;
const int kMaxHistoryTokens = 28000;
const int kMinHistoryTokens = 6000;

/// Compaction hysteresis: compact when history passes [kCompactHighWater] of
/// its budget, down to [kCompactLowWater]. Between two compactions the
/// history prefix is byte-identical, so providers serve it from cache, and
/// the summary call happens once every several turns instead of every turn.
const double kCompactHighWater = 0.9;
const double kCompactLowWater = 0.5;

/// A tool result larger than this is shortened on the wire (valid JSON with
/// a note asking the model to narrow the query). Tools already cap their own
/// output well below it; this is a safety net.
const int kMaxToolResultChars = 12000;

/// Largest transcript one summary call folds in; longer dropped ranges are
/// folded in several successive calls.
const int kSummaryChunkChars = 24000;

/// Singleton orchestrator for AI chat turns. Owns the chat state.
///
/// A turn is bound to the conversation it started in ([_TurnContext]): it
/// keeps running and persisting there even if the user opens another
/// conversation, starts a new one or leaves the screen. Only one turn runs at
/// a time; [cancelTurn] stops it for real (the HTTP request is aborted).
class AiChatService extends ChangeNotifier {
  static final AiChatService instance = AiChatService._();

  AiChatService._();

  final DatabaseHelper _db = DatabaseHelper.instance;
  AiService _service = AiService.shared;
  AiToolRegistry? _toolsOverride;
  AiToolRegistry? _toolsInstance;
  AiProposalService? _proposalsInstance;
  AiMemoryService _memory = AiMemoryService.instance;
  AiContextService _context = AiContextService();
  AiImageAttachmentStore _imageStore = const AiImageAttachmentStore();
  DateTime Function() _clock = DateTime.now;
  AiSettingsNotifier? _settings;
  bool _isReady = false;
  Future<void>? _readyFuture;

  AiToolRegistry get _tools =>
      _toolsOverride ?? (_toolsInstance ??= AiToolRegistry());
  AiProposalService get _proposals =>
      _proposalsInstance ??= AiProposalService();

  /// Last persisted instance per message id: an identical instance is
  /// known-clean and is not written again.
  final Map<String, AiChatMessage> _persistedMessages = {};

  _TurnContext? _turn;
  DateTime _lastTimestamp = DateTime.fromMillisecondsSinceEpoch(0);

  /// Multiplier applied to the chars-per-token heuristic, learned from the
  /// `prompt_tokens` the provider reports. Kept in memory only.
  double _tokenScale = 1.0;

  /// Encoded tool schema and its length per enabled-domain set.
  final Map<String, ({List<Map<String, dynamic>> schema, int chars})>
  _schemaCache = {};

  AiChatState _state = const AiChatState();

  AiChatState get state => _state;
  bool get isSending => _state.isSending;

  void _emit() => notifyListeners();

  /// Replaces default collaborators (used in tests).
  void overrideForTest({
    AiService? service,
    AiToolRegistry? tools,
    AiProposalService? proposals,
    AiMemoryService? memory,
    AiContextService? context,
    AiImageAttachmentStore? imageStore,
    DateTime Function()? clock,
    AiSettingsNotifier? settings,
  }) {
    if (service != null) _service = service;
    if (tools != null) _toolsOverride = tools;
    if (proposals != null) _proposalsInstance = proposals;
    if (memory != null) _memory = memory;
    if (context != null) _context = context;
    if (imageStore != null) _imageStore = imageStore;
    if (clock != null) _clock = clock;
    if (settings != null) _settings = settings;
    _schemaCache.clear();
  }

  /// Forgets every in-memory conversation state (tests, and after a backup
  /// restore replaced the AI tables).
  void reset() {
    _turn?.cancel();
    _turn = null;
    _state = const AiChatState();
    _persistedMessages.clear();
    _schemaCache.clear();
    _tokenScale = 1.0;
    _toolsInstance = null;
    _isReady = false;
    _readyFuture = null;
    _context.invalidate();
    _emit();
  }

  /// Wires the settings notifier. Must be called once at app boot.
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
      final retained = <String>{};
      for (final raw in await _db.aiChatRepo.getAllAttachmentsJson()) {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is Map && item['path'] is String) {
            retained.add(item['path'] as String);
          }
        }
      }
      // A message being written right now is not in the table yet.
      for (final message in [..._state.messages, ...?_turn?.messages]) {
        for (final attachment in message.attachments) {
          retained.add(attachment.path);
        }
      }
      await _imageStore.deleteOrphans(retained);
    } catch (error) {
      // Orphan image cleanup is best-effort; retried on the next launch.
      debugPrint('AI image cleanup failed: $error');
    }
  }

  /// Strictly increasing message timestamps (millisecond precision), so the
  /// `(created_at, id)` order always matches the order of the conversation.
  DateTime _nextTimestamp() {
    var now = _clock();
    now = DateTime.fromMillisecondsSinceEpoch(now.millisecondsSinceEpoch);
    if (!now.isAfter(_lastTimestamp)) {
      now = _lastTimestamp.add(const Duration(milliseconds: 1));
    }
    _lastTimestamp = now;
    return now;
  }

  /// The catalog for [domains]: read tools, proposal tools and memory tools,
  /// in a stable order. Encoded once per domain set: the catalog only changes
  /// when the user changes the enabled domains.
  ({List<Map<String, dynamic>> schema, int chars}) _toolSchema(
    Set<AiToolDomain> domains,
  ) {
    final key = (domains.map((d) => d.name).toList()..sort()).join(',');
    return _schemaCache[key] ??= () {
      final schema = [
        ..._tools.readToolsSchema(domains: domains),
        for (final spec in _proposals.toolSpecs())
          if (domains.contains(spec.domain)) spec.schema,
        for (final spec in _memory.toolSpecs()) spec.schema,
      ];
      return (schema: schema, chars: jsonEncode(schema).length);
    }();
  }

  /// Names of the tools in the catalog for [domains] (what may run).
  Set<String> _allowedToolNames(Set<AiToolDomain> domains) => {
    for (final tool in _toolSchema(domains).schema)
      (tool['function'] as Map)['name'] as String,
  };

  /// Arguments with sorted keys (to compare two calls).
  static Object? _sortedArgs(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((k) => '$k').toList()..sort();
      return {for (final k in keys) k: _sortedArgs(value[k])};
    }
    if (value is List) return value.map(_sortedArgs).toList();
    return value;
  }

  /// Size of the catalog for the current settings (diagnostics, tests).
  int toolCatalogChars() => _toolSchema(
    _settings?.effectiveDomains ?? {...AiToolDomain.values},
  ).chars;

  // ===========================================================================
  // SENDING
  // ===========================================================================

  /// Starts a turn with a new user message. Returns false when nothing was
  /// sent (empty input, a turn already running, missing configuration).
  Future<bool> send(
    String text, {
    List<AiPendingImage> images = const [],
    VoidCallback? onAccepted,
  }) async {
    // Synchronous guard: a double tap must not start two turns.
    if (_turn != null || _sendInFlight) return false;
    _sendInFlight = true;
    try {
      await ensureReady();
      final trimmed = text.trim();
      if (trimmed.isEmpty && images.isEmpty) return false;
      if (images.length > AiImageAttachmentStore.maxImagesPerMessage) {
        _setError('ai_error:too_many_images');
        return false;
      }
      final setup = await _turnSetup();
      if (setup == null) return false;

      List<AiImageAttachment> attachments;
      try {
        attachments = await _imageStore.saveAll(images);
      } on AiImageAttachmentException catch (error) {
        _setError('ai_error:${error.code}');
        return false;
      }
      final now = _nextTimestamp();
      late final String threadId;
      try {
        threadId = await _ensureThread(now, trimmed);
      } catch (error) {
        await _imageStore.deleteAll(attachments);
        _setError(_readableError(error));
        return false;
      }
      final userMsg = AiChatMessage(
        id: _uuid.v4(),
        threadId: threadId,
        role: AiMessageRole.user,
        content: trimmed,
        attachments: attachments,
        createdAt: now,
        turnStatus: AiTurnStatus.running,
      );
      // Write-ahead: the message survives the app being killed mid-turn.
      await _persistMessages(threadId, [userMsg]);
      if (_state.activeThreadId == threadId) {
        _state = _state.copyWith(
          messages: [..._state.messages, userMsg],
          clearError: true,
        );
      }
      final ctx = _startTurn(setup, threadId, userMsg);
      onAccepted?.call();
      unawaited(_runTurn(ctx));
      return true;
    } finally {
      _sendInFlight = false;
    }
  }

  bool _sendInFlight = false;

  /// Provider, token and settings for a new turn, or null (with an error in
  /// the state) when the coach is not ready to send.
  Future<_TurnSetup?> _turnSetup() async {
    final settings = _settings;
    if (settings == null || !settings.isConfigured) {
      _setError('ai_error:missing_provider');
      return null;
    }
    if (!settings.settings.dataSharingAccepted) {
      _setError('ai_error:consent_required');
      return null;
    }
    final provider = settings.activeProvider!;
    if (provider.selectedModel.isEmpty) {
      _setError('ai_error:missing_model');
      return null;
    }
    final token = await settings.getToken(provider.id) ?? '';
    if (token.isEmpty && !AiEndpointPolicy.isLocalEndpoint(provider.baseUrl)) {
      _setError('ai_error:missing_token');
      return null;
    }
    return _TurnSetup(
      provider: provider,
      token: token,
      systemPrompt: settings.systemMessage,
      languageCode: settings.appLanguageCode,
      domains: settings.effectiveDomains,
    );
  }

  _TurnContext _startTurn(
    _TurnSetup setup,
    String threadId,
    AiChatMessage userMsg,
  ) {
    final ctx = _TurnContext(
      setup: setup,
      threadId: threadId,
      userMessage: userMsg,
      startedAt: _clock(),
    );
    _turn = ctx;
    _state = _state.copyWith(
      turn: AiTurnProgress(
        threadId: threadId,
        userMessageId: userMsg.id,
        phase: AiTurnPhase.waiting,
        startedAt: ctx.startedAt,
      ),
    );
    _emit();
    return ctx;
  }

  /// Stops the running turn: aborts the request in flight, keeps what was
  /// already done (the user message, finished tool steps) and marks the turn
  /// cancelled.
  void cancelTurn() {
    final ctx = _turn;
    if (ctx == null || ctx.cancelled) return;
    ctx.cancel();
    final turn = _state.turn;
    if (turn != null) {
      _state = _state.copyWith(turn: turn.copyWith(cancelling: true));
      _emit();
    }
  }

  /// Runs the turn of [userMessageId] again: everything after it is deleted
  /// (messages and pending proposals) and the same message is answered anew.
  /// Refused (with an explanation) when a later message holds a proposal the
  /// user already approved or rejected.
  Future<void> retryTurn(String userMessageId) async {
    if (_turn != null || _sendInFlight) return;
    _sendInFlight = true;
    try {
      final threadId = _state.activeThreadId;
      if (threadId == null) return;
      final setup = await _turnSetup();
      if (setup == null) return;
      final row = await _db.aiChatRepo.getAiChatMessage(userMessageId);
      if (row == null) return;
      final userMsg = AiChatMessage.fromRow(row);
      if (!userMsg.isUser || userMsg.threadId != threadId) return;
      final later = (await _db.aiChatRepo.getAiChatMessagesAfter(
        threadId,
        afterCreatedAt: row['created_at'] as String,
        afterId: userMsg.id,
      )).map(AiChatMessage.fromRow).toList();
      // A change the user already approved or rejected cannot be taken back
      // by deleting its messages: the model would no longer know it happened
      // and could propose (and the user approve) the same change again.
      final laterCallIds = {
        for (final m in later)
          for (final call in m.toolCalls) call.id,
      };
      if (laterCallIds.isNotEmpty) {
        final proposals = await _proposals.forThread(threadId);
        final decided = proposals.any(
          (p) =>
              laterCallIds.contains(p.toolCallId) &&
              (p.status == AiProposalStatus.applied ||
                  p.status == AiProposalStatus.rejected),
        );
        if (decided) {
          _setError('ai_error:retry_resolved_proposal');
          return;
        }
      }
      await _db.aiChatRepo.deleteAiChatMessages(
        threadId,
        [for (final m in later) m.id],
        toolCallIds: [
          for (final m in later)
            for (final call in m.toolCalls) call.id,
        ],
      );
      for (final m in later) {
        _persistedMessages.remove(m.id);
      }
      await _resetSummaryIfCutDeleted(threadId);
      final restarted = userMsg.copyWith(turnStatus: AiTurnStatus.running);
      await _persistMessages(threadId, [restarted]);
      final laterIds = {for (final m in later) m.id};
      _state = _state.copyWith(
        messages: [
          for (final m in _state.messages)
            if (!laterIds.contains(m.id)) m.id == restarted.id ? restarted : m,
        ],
        proposals: [
          for (final p in _state.proposals)
            if (!later.any((m) => m.toolCalls.any((c) => c.id == p.toolCallId)))
              p,
        ],
        clearError: true,
      );
      final ctx = _startTurn(setup, threadId, restarted);
      unawaited(_runTurn(ctx));
    } finally {
      _sendInFlight = false;
    }
  }

  /// Retries the last user message of the open conversation.
  Future<void> retryLastTurn() async {
    for (var i = _state.messages.length - 1; i >= 0; i--) {
      if (_state.messages[i].isUser) {
        await retryTurn(_state.messages[i].id);
        return;
      }
    }
  }

  void dismissError() {
    if (_state.error == null) return;
    _state = _state.copyWith(clearError: true);
    _emit();
  }

  void _setError(
    String code, {
    AiChatErrorDetails? details,
    AiErrorAction action = AiErrorAction.none,
    String? proposalId,
  }) {
    _state = _state.copyWith(
      error: code,
      errorDetails: details,
      errorAction: action,
      errorProposalId: proposalId,
    );
    _emit();
  }

  // ===========================================================================
  // PROPOSALS
  // ===========================================================================

  /// How approving [proposal] works: transactional kinds are applied by
  /// [approveProposal]; user-confirmed kinds open a form first (the UI calls
  /// [completeUserConfirmedProposal] when the user saved it).
  AiProposalApplyMode proposalApplyMode(AiProposal proposal) =>
      _proposals.applyModeOf(proposal);

  Future<void> approveProposal(String proposalId) async {
    if (_state.busyProposalIds.contains(proposalId)) return;
    _setProposalBusy(proposalId, true);
    try {
      final before = await _proposals.get(proposalId);
      if (before == null || !before.isPending) {
        // Already resolved (applied, rejected, failed, stale…): nothing to
        // apply again and no new event; just show its real state.
        if (before != null) _replaceProposal(before);
        if (_state.errorProposalId == proposalId) {
          _state = _state.copyWith(clearError: true);
        }
        return;
      }
      final proposal = await _proposals.approve(proposalId);
      _replaceProposal(proposal);
      if (proposal.status != AiProposalStatus.awaiting) {
        await _appendProposalEvent(proposal);
      }
      if (proposal.status == AiProposalStatus.failed) {
        // Terminal: the apply was rolled back and the proposal cannot run
        // again. No retry; the user can ask the coach for a new one.
        _setError('ai_error:proposal_${proposal.errorCode ?? 'failed'}');
      } else if (_state.errorProposalId == proposalId) {
        _state = _state.copyWith(clearError: true);
      }
      _context.invalidate();
    } catch (error) {
      // The approval itself broke (nothing committed): the proposal is still
      // awaiting, so approving again is meaningful.
      _setError(
        'ai_error:proposal_failed',
        action: AiErrorAction.retryProposal,
        proposalId: proposalId,
        details: _technicalErrorDetails(error, stage: 'apply_proposal'),
      );
    } finally {
      _setProposalBusy(proposalId, false);
    }
  }

  Future<void> rejectProposal(String proposalId) async {
    if (_state.busyProposalIds.contains(proposalId)) return;
    _setProposalBusy(proposalId, true);
    try {
      final before = await _proposals.get(proposalId);
      if (before == null || !before.isPending) {
        if (before != null) _replaceProposal(before);
        return;
      }
      final proposal = await _proposals.reject(proposalId);
      _replaceProposal(proposal);
      await _appendProposalEvent(proposal);
    } catch (error) {
      _setError(_readableError(error));
    } finally {
      _setProposalBusy(proposalId, false);
    }
  }

  /// A user-confirmed proposal (a pre-filled form) was saved by the user.
  Future<void> completeUserConfirmedProposal(
    String proposalId, {
    Map<String, dynamic>? result,
  }) async {
    try {
      final before = await _proposals.get(proposalId);
      if (before == null || !before.isPending) {
        if (before != null) _replaceProposal(before);
        return;
      }
      final proposal = await _proposals.markApplied(proposalId, result: result);
      _replaceProposal(proposal);
      await _appendProposalEvent(proposal);
      _context.invalidate();
    } catch (error) {
      _setError(_readableError(error));
    }
  }

  void _setProposalBusy(String id, bool busy) {
    final ids = {..._state.busyProposalIds};
    busy ? ids.add(id) : ids.remove(id);
    _state = _state.copyWith(busyProposalIds: ids);
    _emit();
  }

  void _replaceProposal(AiProposal proposal) {
    if (_state.activeThreadId != proposal.threadId) return;
    final proposals = [..._state.proposals];
    final index = proposals.indexWhere((item) => item.id == proposal.id);
    if (index == -1) {
      proposals.add(proposal);
    } else {
      proposals[index] = proposal;
    }
    _state = _state.copyWith(proposals: proposals);
    _emit();
  }

  /// Records the outcome of a proposal in its conversation so the model
  /// learns what happened on the next turn, without an extra provider call.
  Future<void> _appendProposalEvent(AiProposal proposal) => _appendEvent(
    proposal.threadId,
    {'type': 'proposal_outcome', ..._proposals.outcomeFacts(proposal)},
  );

  // ===========================================================================
  // MEMORY
  // ===========================================================================

  /// Reverts the memory change a `save_memory` / `delete_memory` tool result
  /// made, and tells the model through an app event.
  Future<void> undoMemoryChange(String toolMessageId) async {
    final index = _state.messages.indexWhere((m) => m.id == toolMessageId);
    if (index < 0) return;
    final message = _state.messages[index];
    final decoded = _decodeToolContent(message.content);
    final data = decoded?['data'];
    if (data is! Map || data['undone'] == true) return;
    final memoryId = data['memory_id'] as String?;
    if (memoryId == null) return;
    try {
      switch (data['status']) {
        case 'saved':
          await _memory.remove(memoryId);
        case 'updated':
          final current = await _memory.byId(memoryId);
          if (current != null) {
            await _memory.update(
              current.copyWith(
                content: data['previous_content'] as String?,
                category: AiMemoryCategory.fromStorage(
                  data['previous_category'] as String?,
                ),
              ),
            );
          }
        case 'deleted':
          final now = _clock();
          await _memory.restore(
            AiMemory(
              id: memoryId,
              content: '${data['content'] ?? ''}',
              category: AiMemoryCategory.fromStorage(
                data['category'] as String?,
              ),
              createdAt: DateTime.tryParse('${data['created_at']}') ?? now,
              updatedAt: now,
              sourceThreadId: message.threadId,
            ),
          );
        default:
          return;
      }
      final updated = message.copyWith(
        content: jsonEncode({
          ...decoded!,
          'data': {...data, 'undone': true},
        }),
      );
      await _persistMessages(message.threadId, [updated]);
      _replaceMessageInState(updated);
      await _appendEvent(message.threadId, {
        'type': 'memory_change_undone',
        'memory_id': memoryId.substring(0, 8),
        'undone_status': data['status'],
        'content': data['content'],
      });
    } catch (error) {
      _setError(_readableError(error));
    }
  }

  // ===========================================================================
  // ERRORS
  // ===========================================================================

  String _readableError(Object e) {
    if (e is TimeoutException) return 'ai_error:timeout';
    if (e is AiImageAttachmentException) return 'ai_error:${e.code}';
    if (e is AiServiceException) return 'ai_error:${e.code ?? 'generic'}';
    return 'ai_error:generic';
  }

  AiChatErrorDetails _technicalErrorDetails(
    Object error, {
    required String stage,
    _TurnContext? ctx,
  }) {
    final serviceError = error is AiServiceException ? error : null;
    return AiChatErrorDetails(
      code:
          serviceError?.code ??
          (error is TimeoutException ? 'timeout' : 'generic'),
      stage: stage,
      message: safeTechnicalMessage(serviceError?.message ?? error.toString()),
      httpStatus: serviceError?.statusCode,
      endpoint: _safeEndpoint(serviceError?.endpoint),
      provider: ctx?.setup.provider.name,
      model: ctx?.setup.provider.selectedModel,
      round: ctx?.round,
      requestCharacters: ctx?.lastRequestChars,
      providerAttempts: serviceError?.attemptCount,
      compatibilityAdjustments:
          serviceError?.compatibilityAdjustments ?? const [],
    );
  }

  /// Redacts credentials from a provider message while keeping it readable
  /// (e.g. "maximum context length is 8192 tokens" stays intact).
  @visibleForTesting
  static String safeTechnicalMessage(String message) {
    var safe = message
        .replaceAllMapped(
          RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false),
          (m) => '${m.group(1)}***',
        )
        .replaceAllMapped(
          RegExp(
            r'''((?:api[_-]?key|access[_-]?token|secret)["']?\s*[:=]\s*["']?)[^\s"',;]+''',
            caseSensitive: false,
          ),
          (m) => '${m.group(1)}***',
        )
        .replaceAll(RegExp(r'\bsk-[A-Za-z0-9_-]{8,}'), 'sk-***')
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

  static Map<String, dynamic>? _decodeToolContent(String? content) {
    if (content == null || content.isEmpty) return null;
    try {
      final decoded = jsonDecode(content);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } on FormatException {
      return null;
    }
  }
}

/// Provider, credentials and settings captured when a turn starts.
class _TurnSetup {
  final AiProvider provider;
  final String token;
  final String systemPrompt;
  final String languageCode;
  final Set<AiToolDomain> domains;

  const _TurnSetup({
    required this.provider,
    required this.token,
    required this.systemPrompt,
    required this.languageCode,
    required this.domains,
  });

  String? get reasoningEffort => provider.reasoningEffortFor().apiValue;
}

/// One running turn, bound to the conversation it started in.
class _TurnContext {
  final _TurnSetup setup;
  final String threadId;
  final AiChatMessage userMessage;
  final DateTime startedAt;
  final Completer<void> _abort = Completer<void>();

  /// Messages produced in this turn (assistant steps, tool results), in order.
  final List<AiChatMessage> messages = [];
  final List<AiRoundDiagnostics> diagnostics = [];
  bool cancelled = false;
  int round = 0;
  int? lastRequestChars;

  _TurnContext({
    required this.setup,
    required this.threadId,
    required this.userMessage,
    required this.startedAt,
  });

  Future<void> get abortTrigger => _abort.future;

  void cancel() {
    cancelled = true;
    if (!_abort.isCompleted) _abort.complete();
  }
}
