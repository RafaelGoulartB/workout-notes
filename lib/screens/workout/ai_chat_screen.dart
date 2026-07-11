import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../navigation/ai_coach_navigation.dart';
import '../../models/ai_chat_message.dart';
import '../../models/ai_chat_state.dart';
import '../../services/ai_tool_registry.dart';
import '../../state/ai_chat_service.dart';
import '../../state/ai_settings_notifier.dart';
import '../../widgets/ai/ai_chat_input_bar.dart';
import '../../widgets/ai/ai_empty_state.dart';
import '../../widgets/ai/ai_message_bubble.dart';
import '../../widgets/ai/ai_provider_picker_sheet.dart';
import '../../widgets/ai/ai_tool_result_bubble.dart';
import 'ai_chat_history_screen.dart';
import 'ai_settings_screen.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final AiSettingsNotifier _settings;
  late final AiToolRegistry _toolLabels;

  @override
  void initState() {
    super.initState();
    _settings = WorkoutNotesApp.aiSettings;
    _toolLabels = AiToolRegistry();
    AiChatService.instance.addListener(_onChange);
    _settings.addListener(_onChange);
  }

  @override
  void dispose() {
    AiChatService.instance.removeListener(_onChange);
    _settings.removeListener(_onChange);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _controller.text;
    _controller.clear();
    await AiChatService.instance.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = AiChatService.instance.state;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final configured = _settings.isConfigured;

    return Scaffold(
      backgroundColor: theme.brightness == Brightness.dark
          ? const Color(0xFF0D0E12)
          : theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.brightness == Brightness.dark
            ? const Color(0xFF17181F)
            : theme.colorScheme.surface,
        title: const SizedBox.shrink(),
        actions: [
          IconButton(
            tooltip: 'Nova conversa',
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: state.isSending
                ? null
                : () => AiChatService.instance.newChat(),
          ),
          IconButton(
            tooltip: 'Histórico',
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push(
                AiCoachNavigation.route(
                  kind: AiCoachRouteKind.aiFlow,
                  builder: (_) => const AiChatHistoryScreen(),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'settings':
                  Navigator.of(context).push(
                    AiCoachNavigation.route(
                      kind: AiCoachRouteKind.aiFlow,
                      builder: (_) => const AiSettingsScreen(),
                    ),
                  );
                  break;
                case 'provider':
                  _showProviderSheet();
                  break;
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'provider', child: Text('Trocar provedor')),
              PopupMenuItem(value: 'settings', child: Text('Configurações')),
            ],
          ),
        ],
      ),
      body: !configured
          ? const AiEmptyState(
              title: 'Configure um provedor de IA',
              subtitle:
                  'Adicione um endpoint OpenAI-compatible (OpenAI, Ollama, OpenRouter…) para começar a usar o Treinador IA.',
            )
          : Column(
              children: [
                if (state.phase != AiTurnPhase.idle)
                  _buildPhaseBanner(theme, state),
                Expanded(
                  child: state.messages.isEmpty
                      ? _buildWelcome(theme)
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: state.messages.length,
                          itemBuilder: (_, i) {
                            return _buildMessageTile(
                              state.messages[i],
                              i,
                              l10n,
                            );
                          },
                        ),
                ),
                if (state.error != null) _buildErrorBanner(theme, state.error!),
                AiChatInputBar(
                  controller: _controller,
                  enabled: configured,
                  sending: state.isSending,
                  providerName: _settings.activeProvider?.name,
                  modelName: _settings.activeProvider?.selectedModel,
                  onChooseProvider: _showProviderSheet,
                  onSend: _send,
                ),
              ],
            ),
    );
  }

  // Kept as a compatibility helper for callers using the older chat layout.
  // ignore: unused_element
  Widget _buildProviderHeader(ThemeData theme) {
    final active = _settings.activeProvider;
    if (active == null) return const SizedBox.shrink();
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: InkWell(
        onTap: _showProviderSheet,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(
                Icons.cloud_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${active.name} • ${active.selectedModel.isEmpty ? "(sem modelo)" : active.selectedModel}',
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.swap_horiz_rounded, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhaseBanner(ThemeData theme, AiChatState state) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.secondaryContainer,
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.phaseMessage ?? 'Processando…',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcome(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.fitness_center_rounded,
              size: 64,
              color: theme.colorScheme.primary.withAlpha(120),
            ),
            const SizedBox(height: 16),
            Text(
              'Olá! Sou o seu Treinador IA.',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Pergunte sobre seu progresso, peça uma análise do seu treino, ou peça sugestões de progressão.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBanner(ThemeData theme, String error) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageTile(AiChatMessage m, int index, AppLocalizations l10n) {
    if (m.isUser) {
      return AiMessageBubble(
        message: m,
        onCopy: () => MessageCopyAction.copy(context, m.content ?? ''),
      );
    }
    if (m.isAssistant) {
      // Build list with assistant bubble + tool result bubbles after it
      final children = <Widget>[];
      final hasVisibleText = m.content?.trim().isNotEmpty == true;
      if (hasVisibleText || m.toolCalls.isEmpty) {
        children.add(
          AiMessageBubble(
            message: m,
            onCopy: () => MessageCopyAction.copy(context, m.content ?? ''),
            onRetry: hasVisibleText
                ? () => AiChatService.instance.retryFromMessage(index - 1)
                : null,
          ),
        );
      }
      // Find consecutive tool messages that answer this assistant's tool calls
      var j = index + 1;
      while (j < AiChatService.instance.state.messages.length) {
        final n = AiChatService.instance.state.messages[j];
        if (n.isTool) {
          children.add(
            AiToolResultBubble(
              message: n,
              toolLabel: _toolLabels.humanLabel(n.toolName ?? ''),
            ),
          );
          j++;
        } else {
          break;
        }
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      );
    }
    if (m.isTool) {
      // Already rendered below the assistant that requested this tool.
      return const SizedBox.shrink();
    }
    return const SizedBox.shrink();
  }

  void _showProviderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiProviderPickerSheet(notifier: _settings),
    );
  }
}
