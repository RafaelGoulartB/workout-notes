import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../database/database_helper.dart';
import '../../l10n/app_localizations.dart';
import '../../main.dart';
import '../../navigation/ai_coach_navigation.dart';
import '../../models/ai_chat_message.dart';
import '../../models/ai_chat_error_details.dart';
import '../../models/ai_image_attachment.dart';
import '../../models/ai_chat_state.dart';
import '../../models/nutrition/ai_manual_food_proposal.dart';
import '../../models/nutrition/food.dart';
import '../../services/ai_tool_registry.dart';
import '../../services/ai_image_attachment_store.dart';
import '../../state/ai_chat_service.dart';
import '../../state/ai_settings_notifier.dart';
import '../../utils/ai_error_localizer.dart';
import '../../widgets/ai/ai_chat_input_bar.dart';
import '../../widgets/ai/ai_empty_state.dart';
import '../../widgets/ai/ai_message_bubble.dart';
import '../../widgets/ai/ai_manual_food_proposal_card.dart';
import '../../widgets/ai/ai_provider_picker_sheet.dart';
import '../../widgets/ai/ai_routine_proposal_card.dart';
import '../../widgets/ai/ai_tool_result_bubble.dart';
import 'ai_chat_history_screen.dart';
import 'ai_settings_screen.dart';
import 'manual_food_screen.dart';
import 'routines_screen.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  String? _lastActiveThreadId;
  late final AiSettingsNotifier _settings;
  late final AiToolRegistry _toolLabels;
  final ImagePicker _imagePicker = ImagePicker();
  final List<AiPendingImage> _pendingImages = [];
  bool _pickingImages = false;

  @override
  void initState() {
    super.initState();
    _settings = WorkoutNotesApp.aiSettings;
    _toolLabels = AiToolRegistry();
    AiChatService.instance.addListener(_onChange);
    _settings.addListener(_onChange);
    // The FAB can open this screen while an existing thread is already
    // active, so no service notification is emitted to trigger the scroll.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottomAfterLayout(animated: false),
    );
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
    final activeThreadId = AiChatService.instance.state.activeThreadId;
    final openedThread = activeThreadId != _lastActiveThreadId;
    _lastActiveThreadId = activeThreadId;
    if (mounted) setState(() {});
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _scrollToBottomAfterLayout(animated: !openedThread),
    );
  }

  Future<void> _scrollToBottomAfterLayout({required bool animated}) async {
    // The first frame may not include the final height of every message
    // bubble. Reposition again after the next frame so opening a thread is
    // always exactly at the end of the list.
    _scrollToBottom(animated: animated);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    _scrollToBottom(animated: false);
  }

  void _scrollToBottom({required bool animated}) {
    if (!_scroll.hasClients) return;
    final offset = _scroll.position.maxScrollExtent;
    if (!animated) {
      _scroll.jumpTo(offset);
      return;
    }
    _scroll.animateTo(
      offset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    final text = _controller.text;
    final images = List<AiPendingImage>.of(_pendingImages);
    await AiChatService.instance.send(
      text,
      images: images,
      onAccepted: () {
        if (!mounted) return;
        _controller.clear();
        setState(_pendingImages.clear);
      },
    );
  }

  Future<void> _showImageSourcePicker() async {
    if (_pendingImages.length >= kMaxAiChatImages || _pickingImages) return;
    final l10n = AppLocalizations.of(context)!;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(l10n.aiChatChooseGallery),
              subtitle: Text(l10n.aiChatImageLimitHelp),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
            if (!kIsWeb &&
                (defaultTargetPlatform == TargetPlatform.android ||
                    defaultTargetPlatform == TargetPlatform.iOS))
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: Text(l10n.aiChatTakePhoto),
                onTap: () => Navigator.pop(context, ImageSource.camera),
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    await _pickImages(source);
  }

  Future<void> _pickImages(ImageSource source) async {
    final l10n = AppLocalizations.of(context)!;
    final remaining = kMaxAiChatImages - _pendingImages.length;
    setState(() => _pickingImages = true);
    try {
      final List<XFile> files;
      if (source == ImageSource.camera) {
        final file = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82,
          requestFullMetadata: false,
        );
        files = file == null ? [] : [file];
      } else {
        files = await _imagePicker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 82,
          limit: remaining,
          requestFullMetadata: false,
        );
      }
      final selected = files.take(remaining);
      final pending = <AiPendingImage>[];
      for (final file in selected) {
        final bytes = await file.readAsBytes();
        if (bytes.length > kMaxAiChatImageBytes) {
          throw const AiImageAttachmentException('image_too_large');
        }
        final mimeType = _detectImageMimeType(file.mimeType, bytes);
        if (mimeType == null) {
          throw const AiImageAttachmentException('unsupported_image');
        }
        pending.add(
          AiPendingImage(bytes: bytes, mimeType: mimeType, fileName: file.name),
        );
      }
      if (!mounted) return;
      setState(() => _pendingImages.addAll(pending));
      if (files.length > remaining) {
        _showImageSnack(l10n.aiChatTooManyImages);
      }
    } on AiImageAttachmentException catch (error) {
      if (!mounted) return;
      _showImageSnack(
        error.code == 'image_too_large'
            ? l10n.aiChatImageTooLarge
            : l10n.aiChatUnsupportedImage,
      );
    } catch (_) {
      if (mounted) _showImageSnack(l10n.aiChatImagePickFailed);
    } finally {
      if (mounted) setState(() => _pickingImages = false);
    }
  }

  void _showImageSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _detectImageMimeType(String? reported, List<int> bytes) {
    const supported = {'image/jpeg', 'image/png', 'image/webp', 'image/gif'};
    final normalized = reported?.toLowerCase();
    if (normalized != null && supported.contains(normalized)) return normalized;
    if (bytes.length >= 3 &&
        bytes[0] == 0xff &&
        bytes[1] == 0xd8 &&
        bytes[2] == 0xff) {
      return 'image/jpeg';
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47) {
      return 'image/png';
    }
    if (bytes.length >= 12 &&
        String.fromCharCodes(bytes.sublist(0, 4)) == 'RIFF' &&
        String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
    if (bytes.length >= 6 &&
        String.fromCharCodes(bytes.sublist(0, 3)) == 'GIF') {
      return 'image/gif';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final state = AiChatService.instance.state;
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final configured = _settings.isConfigured;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        titleSpacing: 0,
        title: _buildChatHeader(theme, l10n),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.outlineVariant.withAlpha(120),
          ),
        ),
        actions: [
          IconButton(
            tooltip: l10n.aiChatNewChat,
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: state.isSending
                ? null
                : () => AiChatService.instance.newChat(),
          ),
          IconButton(
            tooltip: l10n.aiChatHistory,
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
            tooltip: l10n.aiChatMoreOptions,
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
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'settings',
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(l10n.aiChatSettings),
                ),
              ),
            ],
          ),
        ],
      ),
      body: !configured
          ? AiEmptyState(
              title: l10n.aiEmptyTitle,
              subtitle: l10n.aiEmptySubtitle,
            )
          : Column(
              children: [
                Expanded(
                  child: state.messages.isEmpty
                      ? _buildWelcome(theme, l10n)
                      : ListView.builder(
                          controller: _scroll,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
                          itemCount:
                              state.messages.length +
                              (_showActivity(state) ? 1 : 0),
                          itemBuilder: (_, i) {
                            if (i == state.messages.length) {
                              return _buildActivityIndicator(
                                theme,
                                state,
                                l10n,
                              );
                            }
                            return _buildMessageTile(
                              state.messages[i],
                              i,
                              l10n,
                            );
                          },
                        ),
                ),
                if (state.error != null)
                  _buildErrorBanner(
                    theme,
                    state.error!,
                    state.errorDetails,
                    l10n,
                  ),
                AiChatInputBar(
                  controller: _controller,
                  enabled: configured,
                  sending: state.isSending,
                  onSend: _send,
                  images: _pendingImages,
                  pickingImages: _pickingImages,
                  onAddImages: _showImageSourcePicker,
                  onRemoveImage: (index) {
                    setState(() => _pendingImages.removeAt(index));
                  },
                ),
              ],
            ),
    );
  }

  Widget _buildChatHeader(ThemeData theme, AppLocalizations l10n) {
    final active = _settings.activeProvider;
    final model = active?.selectedModel ?? '';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: active == null ? null : _showProviderSheet,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 19,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.aiChatCoachName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  active == null
                      ? l10n.aiChatNotConfigured
                      : model.isEmpty
                      ? active.name
                      : model,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (active != null) ...[
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }

  bool _showActivity(AiChatState state) =>
      state.phase != AiTurnPhase.idle && state.phase != AiTurnPhase.failed;

  Widget _buildActivityIndicator(
    ThemeData theme,
    AiChatState state,
    AppLocalizations l10n,
  ) {
    return Semantics(
      liveRegion: true,
      label: _phaseText(state, l10n),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primaryContainer,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 16,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              margin: const EdgeInsets.only(top: 1),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Text(
                    _phaseText(state, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _sendSuggestion(String text) {
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    _send();
  }

  Widget _suggestionCard(
    ThemeData theme, {
    required IconData icon,
    required String text,
  }) {
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _sendSuggestion(text),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, size: 19, color: theme.colorScheme.primary),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  text,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                Icons.arrow_forward_rounded,
                size: 17,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _phaseText(AiChatState state, AppLocalizations l10n) {
    switch (state.phaseMessage) {
      case 'sending':
        return l10n.aiChatSending;
      case 'reading':
        return l10n.aiChatReading(state.phaseToolCount ?? 0);
      case 'finalising':
        return l10n.aiChatFinalising;
      case 'preparing_proposal':
        return l10n.aiChatPreparingProposal;
      case 'preparing_food_proposal':
        return l10n.aiChatPreparingFoodProposal;
      case 'applying_proposal':
        return l10n.aiChatApplyingProposal;
      default:
        return l10n.aiChatProcessing;
    }
  }

  Widget _buildWelcome(ThemeData theme, AppLocalizations l10n) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 28,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.aiChatWelcomeTitle,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  l10n.aiChatWelcomeSubtitle,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    height: 1.45,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(height: 26),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    _suggestionCard(
                      theme,
                      icon: Icons.battery_charging_full_rounded,
                      text: l10n.aiChatSuggestionRecovery,
                    ),
                    const SizedBox(height: 10),
                    _suggestionCard(
                      theme,
                      icon: Icons.bedtime_outlined,
                      text: l10n.aiChatSuggestionSleep,
                    ),
                    const SizedBox(height: 10),
                    _suggestionCard(
                      theme,
                      icon: Icons.trending_up_rounded,
                      text: l10n.aiChatSuggestionProgress,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(
    ThemeData theme,
    String error,
    AiChatErrorDetails? details,
    AppLocalizations l10n,
  ) {
    final failedProposalId = _failedProposalId(error);
    final technicalLines = _technicalErrorLines(error, details, l10n);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: theme.colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: theme.colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    localizeAiError(error, l10n),
                    style: theme.textTheme.bodySmall?.copyWith(
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    l10n.aiChatErrorTechnicalTitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  SelectableText(
                    technicalLines.join('\n'),
                    style: theme.textTheme.labelSmall?.copyWith(
                      height: 1.35,
                      color: theme.colorScheme.onErrorContainer.withValues(
                        alpha: 0.88,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: l10n.aiChatRetry,
              color: theme.colorScheme.onErrorContainer,
              onPressed: AiChatService.instance.state.isSending
                  ? null
                  : failedProposalId != null
                  ? () => AiChatService.instance.approveRoutineProposal(
                      failedProposalId,
                    )
                  : !AiChatService.instance.state.messages.any(
                      (message) => message.isUser,
                    )
                  ? null
                  : AiChatService.instance.retryLastTurn,
              icon: const Icon(Icons.refresh_rounded, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _technicalErrorLines(
    String error,
    AiChatErrorDetails? details,
    AppLocalizations l10n,
  ) {
    final fallbackCode = error.startsWith('ai_error:')
        ? error.substring('ai_error:'.length).split(':').first
        : 'generic';
    if (details == null) {
      return ['${l10n.aiChatErrorTechnicalCode}: $fallbackCode'];
    }
    return [
      '${l10n.aiChatErrorTechnicalStage}: ${details.stage}',
      [
        '${l10n.aiChatErrorTechnicalCode}: ${details.code}',
        if (details.httpStatus != null) 'HTTP ${details.httpStatus}',
        if (details.round != null)
          '${l10n.aiChatErrorTechnicalRound}: ${details.round}',
      ].join(' · '),
      if (details.provider != null || details.model != null)
        '${l10n.aiChatErrorTechnicalProvider}: '
            '${details.provider ?? '—'} / ${details.model ?? '—'}',
      if (details.endpoint != null)
        '${l10n.aiChatErrorTechnicalEndpoint}: ${details.endpoint}',
      if (details.schemaToolCount != null || details.requestCharacters != null)
        '${l10n.aiChatErrorTechnicalRequest}: '
            '${details.schemaToolCount ?? 0} tools · '
            '${details.requestCharacters ?? 0} chars',
      if (details.tools.isNotEmpty)
        '${l10n.aiChatErrorTechnicalTools}: ${details.tools.join(', ')}',
      if (details.providerAttempts != null)
        '${l10n.aiChatErrorTechnicalAttempts}: ${details.providerAttempts}',
      if (details.compatibilityAdjustments.isNotEmpty)
        '${l10n.aiChatErrorTechnicalAdjustments}: '
            '${details.compatibilityAdjustments.join(', ')}',
      if (details.message?.isNotEmpty ?? false)
        '${l10n.aiChatErrorTechnicalDetail}: ${details.message}',
    ];
  }

  String? _failedProposalId(String error) {
    const prefix = 'ai_error:routine_apply_failed:';
    if (!error.startsWith(prefix)) return null;
    final id = error.substring(prefix.length);
    return id.isEmpty ? null : id;
  }

  Widget _buildMessageTile(AiChatMessage m, int index, AppLocalizations l10n) {
    if (m.isUser) {
      return AiMessageBubble(
        message: m,
        showTimestamp: _settings.settings.showMessageTimestamps,
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
            showTimestamp: _settings.settings.showMessageTimestamps,
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
          final proposalId = _proposalIdFromTool(n);
          final proposal = proposalId == null
              ? null
              : AiChatService.instance.state.proposalById(proposalId);
          if (proposal != null) {
            children.add(
              AiRoutineProposalCard(
                proposal: proposal,
                onApprove: () =>
                    AiChatService.instance.approveRoutineProposal(proposal.id),
                onReject: () =>
                    AiChatService.instance.rejectRoutineProposal(proposal.id),
                onRetrySummary: proposal.errorCode == 'summary_pending'
                    ? () => AiChatService.instance.retryAppliedProposalSummary(
                        proposal.id,
                      )
                    : null,
                onViewRoutine: proposal.appliedRoutineId == null
                    ? null
                    : () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => RoutineFormScreen(
                              routineId: proposal.appliedRoutineId!,
                            ),
                          ),
                        );
                      },
              ),
            );
          } else {
            final foodProposal = _manualFoodProposalFromTool(n);
            if (foodProposal != null) {
              children.add(
                AiManualFoodProposalCard(
                  proposal: foodProposal,
                  onApprove: () => _openManualFoodProposal(n, foodProposal),
                  onReject: () =>
                      AiChatService.instance.rejectManualFoodProposal(n.id),
                ),
              );
              j++;
              continue;
            }
            children.add(
              AiToolResultBubble(
                message: n,
                toolLabel: _toolLabels.humanLabel(n.toolName ?? '', l10n),
                initiallyExpanded: _settings.settings.autoExpandToolDetails,
              ),
            );
          }
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

  String? _proposalIdFromTool(AiChatMessage message) {
    if (message.toolName != 'propose_routine_change') return null;
    try {
      final raw = jsonDecode(message.content ?? '');
      final data = raw is Map ? raw['data'] : null;
      return data is Map ? data['proposalId'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  AiManualFoodProposal? _manualFoodProposalFromTool(AiChatMessage message) {
    if (message.toolName != 'propose_manual_food_creation') return null;
    try {
      final raw = jsonDecode(message.content ?? '');
      final data = raw is Map ? raw['data'] : null;
      if (data is! Map) return null;
      return AiManualFoodProposal.fromJson(data.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  Future<void> _openManualFoodProposal(
    AiChatMessage message,
    AiManualFoodProposal proposal,
  ) async {
    if (proposal.status != AiManualFoodProposalStatus.awaitingApproval) return;
    final food = await Navigator.of(context).push<Food>(
      MaterialPageRoute(
        builder: (_) => ManualFoodScreen(
          repository: DatabaseHelper.instance.nutritionRepository,
          source: FoodSource.aiCoach,
          initial: proposal.draft,
        ),
      ),
    );
    if (food == null || !mounted) return;
    await AiChatService.instance.completeManualFoodProposal(
      toolMessageId: message.id,
      foodId: food.id,
    );
  }

  void _showProviderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiProviderPickerSheet(notifier: _settings),
    );
  }
}
