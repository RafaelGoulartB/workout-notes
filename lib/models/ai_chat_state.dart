import 'package:workout_notes/models/ai_chat_error_details.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_thread.dart';
import 'package:workout_notes/models/ai_proposal.dart';

/// What the running turn is doing right now.
enum AiTurnPhase {
  /// Request sent, nothing received yet.
  waiting,

  /// The model is reasoning (reasoning tokens streamed, no text yet).
  thinking,

  /// Answer text is streaming in ([AiTurnProgress.draftText]).
  writing,

  /// Tools are running locally ([AiTurnProgress.toolNames]).
  usingTools,

  /// Older messages are being folded into the conversation summary.
  compacting,
}

/// Live progress of the single turn that can run at a time.
class AiTurnProgress {
  final String threadId;
  final String userMessageId;
  final AiTurnPhase phase;
  final DateTime startedAt;

  /// 1-based provider round of this turn.
  final int round;

  /// Tool calls of the current step (names), shown as "Reading: …".
  final List<String> toolNames;

  /// Answer text streamed so far in the current round.
  final String draftText;

  /// True once the user asked to stop; the turn ends as soon as possible.
  final bool cancelling;

  const AiTurnProgress({
    required this.threadId,
    required this.userMessageId,
    required this.phase,
    required this.startedAt,
    this.round = 1,
    this.toolNames = const [],
    this.draftText = '',
    this.cancelling = false,
  });

  AiTurnProgress copyWith({
    AiTurnPhase? phase,
    int? round,
    List<String>? toolNames,
    String? draftText,
    bool? cancelling,
  }) => AiTurnProgress(
    threadId: threadId,
    userMessageId: userMessageId,
    phase: phase ?? this.phase,
    startedAt: startedAt,
    round: round ?? this.round,
    toolNames: toolNames ?? this.toolNames,
    draftText: draftText ?? this.draftText,
    cancelling: cancelling ?? this.cancelling,
  );
}

/// What the error banner's retry button does.
enum AiErrorAction {
  /// Nothing to retry (the banner can only be dismissed).
  none,

  /// Run the failed turn again.
  retryTurn,

  /// Approve the proposal again ([AiChatState.errorProposalId]).
  retryProposal,
}

/// Per-round numbers of the last turn (developer diagnostics only; nothing
/// is persisted or shown to regular users).
class AiRoundDiagnostics {
  final int round;
  final int requestChars;
  final int? promptTokens;
  final int? cachedTokens;
  final int? completionTokens;
  final int durationMs;
  final List<String> toolCalls;
  final bool streamed;

  const AiRoundDiagnostics({
    required this.round,
    required this.requestChars,
    required this.durationMs,
    this.promptTokens,
    this.cachedTokens,
    this.completionTokens,
    this.toolCalls = const [],
    this.streamed = false,
  });
}

class AiChatState {
  final List<AiChatThread> threads;
  final String? activeThreadId;
  final List<AiChatMessage> messages;

  /// The running turn (at most one, possibly in another conversation).
  final AiTurnProgress? turn;
  final String? error;
  final AiChatErrorDetails? errorDetails;
  final AiErrorAction errorAction;
  final String? errorProposalId;
  final List<AiProposal> proposals;
  final bool hasOlderMessages;
  final bool isLoadingOlderMessages;
  final bool hasOlderThreads;
  final bool isLoadingOlderThreads;

  /// Total stored conversations (not just the loaded pages); null until the
  /// first count arrives.
  final int? totalThreadCount;

  /// Proposal ids being approved/rejected right now (cards show a spinner).
  final Set<String> busyProposalIds;
  final List<AiRoundDiagnostics> lastTurnDiagnostics;

  const AiChatState({
    this.threads = const [],
    this.activeThreadId,
    this.messages = const [],
    this.turn,
    this.error,
    this.errorDetails,
    this.errorAction = AiErrorAction.none,
    this.errorProposalId,
    this.proposals = const [],
    this.hasOlderMessages = false,
    this.isLoadingOlderMessages = false,
    this.hasOlderThreads = false,
    this.isLoadingOlderThreads = false,
    this.totalThreadCount,
    this.busyProposalIds = const {},
    this.lastTurnDiagnostics = const [],
  });

  /// A turn is running somewhere.
  bool get isSending => turn != null;

  /// The running turn belongs to the conversation on screen.
  bool get isTurnInActiveThread =>
      turn != null && turn!.threadId == activeThreadId;

  /// A turn runs in another conversation: the composer waits for it.
  bool get isBusyElsewhere => turn != null && turn!.threadId != activeThreadId;

  AiProposal? proposalForToolCall(String toolCallId) {
    for (final proposal in proposals) {
      if (proposal.toolCallId == toolCallId) return proposal;
    }
    return null;
  }

  bool get isEmpty => messages.isEmpty;

  AiChatState copyWith({
    List<AiChatThread>? threads,
    String? activeThreadId,
    bool clearActiveThread = false,
    List<AiChatMessage>? messages,
    AiTurnProgress? turn,
    bool clearTurn = false,
    String? error,
    AiChatErrorDetails? errorDetails,
    AiErrorAction? errorAction,
    String? errorProposalId,
    bool clearError = false,
    List<AiProposal>? proposals,
    bool? hasOlderMessages,
    bool? isLoadingOlderMessages,
    bool? hasOlderThreads,
    bool? isLoadingOlderThreads,
    int? totalThreadCount,
    Set<String>? busyProposalIds,
    List<AiRoundDiagnostics>? lastTurnDiagnostics,
  }) {
    final clearing = clearError || error != null;
    return AiChatState(
      threads: threads ?? this.threads,
      activeThreadId: clearActiveThread
          ? null
          : (activeThreadId ?? this.activeThreadId),
      messages: messages ?? this.messages,
      turn: clearTurn ? null : (turn ?? this.turn),
      error: clearError ? null : (error ?? this.error),
      errorDetails: clearing ? errorDetails : this.errorDetails,
      errorAction: clearing
          ? (errorAction ?? AiErrorAction.none)
          : (errorAction ?? this.errorAction),
      errorProposalId: clearing ? errorProposalId : this.errorProposalId,
      proposals: proposals ?? this.proposals,
      hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
      isLoadingOlderMessages:
          isLoadingOlderMessages ?? this.isLoadingOlderMessages,
      hasOlderThreads: hasOlderThreads ?? this.hasOlderThreads,
      isLoadingOlderThreads:
          isLoadingOlderThreads ?? this.isLoadingOlderThreads,
      totalThreadCount: totalThreadCount ?? this.totalThreadCount,
      busyProposalIds: busyProposalIds ?? this.busyProposalIds,
      lastTurnDiagnostics: lastTurnDiagnostics ?? this.lastTurnDiagnostics,
    );
  }
}
