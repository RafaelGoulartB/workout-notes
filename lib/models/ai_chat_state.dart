import 'ai_chat_message.dart';
import 'ai_chat_thread.dart';

enum AiTurnPhase {
  idle,
  sending,
  executingReads,
  failed,
}

class AiChatState {
  final List<AiChatThread> threads;
  final String? activeThreadId;
  final List<AiChatMessage> messages;
  final AiTurnPhase phase;
  final String? error;
  final String? phaseMessage;

  const AiChatState({
    this.threads = const [],
    this.activeThreadId,
    this.messages = const [],
    this.phase = AiTurnPhase.idle,
    this.error,
    this.phaseMessage,
  });

  bool get isSending => phase == AiTurnPhase.sending || phase == AiTurnPhase.executingReads;
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
    bool clearError = false,
    String? phaseMessage,
    bool clearPhaseMessage = false,
  }) {
    return AiChatState(
      threads: threads ?? this.threads,
      activeThreadId: clearActiveThread ? null : (activeThreadId ?? this.activeThreadId),
      messages: messages ?? this.messages,
      phase: phase ?? this.phase,
      error: clearError ? null : (error ?? this.error),
      phaseMessage: clearPhaseMessage ? null : (phaseMessage ?? this.phaseMessage),
    );
  }
}
