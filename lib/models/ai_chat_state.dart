import 'ai_chat_message.dart';
import 'ai_chat_error_details.dart';
import 'ai_chat_thread.dart';
import 'ai_routine_proposal.dart';

enum AiTurnPhase {
  idle,
  sending,
  executingReads,
  preparingProposal,
  applyingProposal,
  failed,
}

class AiChatState {
  final List<AiChatThread> threads;
  final String? activeThreadId;
  final List<AiChatMessage> messages;
  final AiTurnPhase phase;
  final String? error;
  final AiChatErrorDetails? errorDetails;
  final String? phaseMessage;
  final int? phaseToolCount;
  final List<AiRoutineProposal> routineProposals;
  final bool hasOlderMessages;
  final bool isLoadingOlderMessages;
  final bool hasOlderThreads;
  final bool isLoadingOlderThreads;

  const AiChatState({
    this.threads = const [],
    this.activeThreadId,
    this.messages = const [],
    this.phase = AiTurnPhase.idle,
    this.error,
    this.errorDetails,
    this.phaseMessage,
    this.phaseToolCount,
    this.routineProposals = const [],
    this.hasOlderMessages = false,
    this.isLoadingOlderMessages = false,
    this.hasOlderThreads = false,
    this.isLoadingOlderThreads = false,
  });

  bool get isSending =>
      phase == AiTurnPhase.sending ||
      phase == AiTurnPhase.executingReads ||
      phase == AiTurnPhase.preparingProposal ||
      phase == AiTurnPhase.applyingProposal;
  AiRoutineProposal? proposalById(String id) {
    for (final proposal in routineProposals) {
      if (proposal.id == id) return proposal;
    }
    return null;
  }

  bool get isEmpty => messages.isEmpty;
  AiChatThread? get activeThread {
    if (activeThreadId == null) return null;
    for (final t in threads) {
      if (t.id == activeThreadId) return t;
    }
    return null;
  }

  AiChatState copyWith({
    List<AiChatThread>? threads,
    String? activeThreadId,
    bool clearActiveThread = false,
    List<AiChatMessage>? messages,
    AiTurnPhase? phase,
    String? error,
    AiChatErrorDetails? errorDetails,
    bool clearError = false,
    String? phaseMessage,
    bool clearPhaseMessage = false,
    int? phaseToolCount,
    List<AiRoutineProposal>? routineProposals,
    bool? hasOlderMessages,
    bool? isLoadingOlderMessages,
    bool? hasOlderThreads,
    bool? isLoadingOlderThreads,
  }) {
    return AiChatState(
      threads: threads ?? this.threads,
      activeThreadId:
          clearActiveThread ? null : (activeThreadId ?? this.activeThreadId),
      messages: messages ?? this.messages,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      errorDetails: clearError
          ? null
          : (errorDetails ?? (error != null ? null : this.errorDetails)),
      phaseMessage:
          clearPhaseMessage ? null : (phaseMessage ?? this.phaseMessage),
      phaseToolCount: phaseToolCount ?? this.phaseToolCount,
      routineProposals: routineProposals ?? this.routineProposals,
      hasOlderMessages: hasOlderMessages ?? this.hasOlderMessages,
      isLoadingOlderMessages:
          isLoadingOlderMessages ?? this.isLoadingOlderMessages,
      hasOlderThreads: hasOlderThreads ?? this.hasOlderThreads,
      isLoadingOlderThreads:
          isLoadingOlderThreads ?? this.isLoadingOlderThreads,
    );
  }
}
