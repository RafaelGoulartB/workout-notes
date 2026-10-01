import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/main.dart';
import 'package:workout_notes/models/ai_chat_message.dart';
import 'package:workout_notes/models/ai_chat_state.dart';
import 'package:workout_notes/models/ai_image_attachment.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/screens/ai/ai_chat_history_screen.dart';
import 'package:workout_notes/screens/settings/ai_settings_screen.dart';
import 'package:workout_notes/services/ai_image_attachment_store.dart';
import 'package:workout_notes/state/ai_chat_service.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';
import 'package:workout_notes/utils/ai_error_localizer.dart';
import 'package:workout_notes/widgets/ai/ai_chat_input_bar.dart';
import 'package:workout_notes/widgets/ai/ai_chat_timeline.dart';
import 'package:workout_notes/widgets/ai/ai_consent_dialog.dart';
import 'package:workout_notes/widgets/ai/ai_empty_state.dart';
import 'package:workout_notes/widgets/ai/ai_error_banner.dart';
import 'package:workout_notes/widgets/ai/ai_live_turn.dart';
import 'package:workout_notes/widgets/ai/ai_message_bubble.dart';
import 'package:workout_notes/widgets/ai/ai_proposal_card.dart';
import 'package:workout_notes/widgets/ai/ai_proposal_forms.dart';
import 'package:workout_notes/widgets/ai/ai_provider_picker_sheet.dart';
import 'package:workout_notes/widgets/ai/ai_scroll_anchor.dart';
import 'package:workout_notes/widgets/ai/ai_status_lines.dart';
import 'package:workout_notes/widgets/ai/ai_tool_steps.dart';

/// Distance from the newest message (px) within which the list keeps
/// following new content.
const double kAiFollowThreshold = 120;

/// Distance from the newest message beyond which "Latest" is offered.
const double kAiJumpThreshold = 240;

/// Distance from the oldest loaded message (px) at which the previous page is
/// requested.
const double kAiLoadOlderThreshold = 400;

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  late final AiSettingsNotifier _settings;
  final ImagePicker _imagePicker = ImagePicker();
  final List<AiPendingImage> _pendingImages = [];
  bool _pickingImages = false;

  // Conversation list (newest first, so the list is `reverse: true`: offset 0
  // is the newest message, and loading older ones never moves what is read).
  String? _lastActiveThreadId;
  String? _lastMessageId;
  List<AiChatItem> _items = const [];
  List<AiChatMessage>? _itemsMessages;
  List<AiProposal>? _itemsProposals;
  bool _showJump = false;

  // Rows appended since the last frame: while the reader is scrolled away,
  // their height must not push what they read (see [AiScrollAnchor]).
  Set<String> _freshKeys = const {};
  String? _itemsThreadId;
  bool _hadLiveTurn = false;

  @override
  void initState() {
    super.initState();
    _settings = WorkoutNotesApp.aiSettings;
    AiChatService.instance.addListener(_onChange);
    _settings.addListener(_onSettingsChange);
    _scroll.addListener(_onScroll);
    unawaited(AiChatService.instance.ensureReady());
    _lastActiveThreadId = AiChatService.instance.state.activeThreadId;
  }

  @override
  void dispose() {
    AiChatService.instance.removeListener(_onChange);
    _settings.removeListener(_onSettingsChange);
    _scroll.removeListener(_onScroll);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onSettingsChange() {
    if (mounted) setState(() {});
  }

  void _onChange() {
    final state = AiChatService.instance.state;
    final openedThread = state.activeThreadId != _lastActiveThreadId;
    final last = state.messages.isEmpty ? null : state.messages.last;
    final newMessage = last?.id != _lastMessageId;
    _lastActiveThreadId = state.activeThreadId;
    _lastMessageId = last?.id;
    if (mounted) setState(() {});
    if (openedThread || (newMessage && last?.isUser == true)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _scrollToLatest(animated: !openedThread),
      );
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    final showJump = position.pixels > kAiJumpThreshold;
    if (showJump != _showJump && mounted) setState(() => _showJump = showJump);
    if (position.maxScrollExtent - position.pixels < kAiLoadOlderThreshold) {
      final state = AiChatService.instance.state;
      if (state.hasOlderMessages && !state.isLoadingOlderMessages) {
        unawaited(AiChatService.instance.loadOlderMessages());
      }
    }
  }

  /// A row below the reader changed height: move the offset by the same
  /// amount (during layout, so there is no visible jump). Following the end
  /// needs nothing: offset 0 stays pinned to the newest message.
  void _correctForTail(double delta) {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels <= kAiFollowThreshold) return;
    position.correctBy(delta);
  }

  void _scrollToLatest({required bool animated}) {
    if (!mounted || !_scroll.hasClients) return;
    if (!animated) {
      _scroll.jumpTo(0);
      return;
    }
    unawaited(
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      ),
    );
  }

  /// Rows of the conversation, rebuilt only when the messages or proposals
  /// changed.
  List<AiChatItem> _itemsFor(AiChatState state) {
    if (!identical(_itemsMessages, state.messages) ||
        !identical(_itemsProposals, state.proposals)) {
      final sameThread = _itemsThreadId == state.activeThreadId;
      final known = {for (final item in _items) item.key};
      _itemsMessages = state.messages;
      _itemsProposals = state.proposals;
      _itemsThreadId = state.activeThreadId;
      _items = buildAiChatItems(
        state.messages,
        proposalCallIds: {for (final p in state.proposals) p.toolCallId},
      );
      final fresh = sameThread && known.isNotEmpty
          ? {
              for (final item in _items)
                if (!known.contains(item.key)) item.key,
            }
          : <String>{};
      _freshKeys = fresh;
      if (fresh.isNotEmpty) {
        // Only the frame that first lays the new rows out counts them.
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _freshKeys = const {},
        );
      }
    }
    return _items;
  }

  Future<void> _send() async {
    final provider = _settings.activeProvider;
    if (_settings.isConfigured && !_settings.settings.dataSharingAccepted) {
      final accepted = await showAiConsentDialog(
        context,
        providerName: provider?.name,
      );
      if (!accepted || !mounted) return;
      await _settings.setDataSharingAccepted(true);
      if (!mounted) return;
    }
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

  /// The banner's Retry: allow data sharing then send again (consent), re-run
  /// the failed turn, or re-approve the proposal that failed.
  Future<void> _retryFromBanner(AiChatState state) async {
    final service = AiChatService.instance;
    if (aiErrorCode(state.error) == 'consent_required') {
      final accepted = await showAiConsentDialog(
        context,
        providerName: _settings.activeProvider?.name,
      );
      if (!accepted || !mounted) return;
      await _settings.setDataSharingAccepted(true);
      service.dismissError();
      // Nothing was sent: the blocked text and images are still in the
      // composer, so send them now (never re-run an older message).
      if (!mounted) return;
      if (_controller.text.trim().isNotEmpty || _pendingImages.isNotEmpty) {
        await _send();
      }
      return;
    }
    switch (state.errorAction) {
      case AiErrorAction.retryTurn:
        await service.retryLastTurn();
      case AiErrorAction.retryProposal:
        final id = state.errorProposalId;
        if (id != null) await service.approveProposal(id);
      case AiErrorAction.none:
        break;
    }
  }

  Future<void> _approveProposal(AiProposal proposal) async {
    final service = AiChatService.instance;
    if (service.proposalApplyMode(proposal) ==
        AiProposalApplyMode.userConfirmed) {
      final result = await AiProposalForms.open(context, proposal);
      if (result != null) {
        await service.completeUserConfirmedProposal(
          proposal.id,
          result: result,
        );
      }
    } else {
      await service.approveProposal(proposal.id);
    }
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
            if (defaultTargetPlatform == TargetPlatform.android)
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
            onPressed: AiChatService.instance.newChat,
          ),
          IconButton(
            tooltip: l10n.aiChatHistory,
            icon: const Icon(Icons.history_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AiChatHistoryScreen()),
              );
            },
          ),
          PopupMenuButton<String>(
            tooltip: l10n.aiChatMoreOptions,
            onSelected: (v) {
              switch (v) {
                case 'settings':
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AiSettingsScreen()),
                  );
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
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child:
                            state.messages.isEmpty &&
                                !state.isTurnInActiveThread
                            ? _buildWelcome(theme, l10n)
                            : _buildConversation(state),
                      ),
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          ignoring: !_showJump,
                          child: AnimatedOpacity(
                            key: const ValueKey('ai-jump-to-latest'),
                            opacity: _showJump ? 1 : 0,
                            duration: const Duration(milliseconds: 150),
                            child: Center(
                              child: FilledButton.tonalIcon(
                                onPressed: () =>
                                    _scrollToLatest(animated: true),
                                icon: const Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 18,
                                ),
                                label: Text(l10n.aiChatJumpToLatest),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (state.error != null)
                  AiErrorBanner(
                    error: state.error!,
                    details: state.errorDetails,
                    developerMode: _settings.settings.developerMode,
                    onRetry: _canRetryFromBanner(state)
                        ? () => unawaited(_retryFromBanner(state))
                        : null,
                    onDismiss: AiChatService.instance.dismissError,
                  ),
                AiChatInputBar(
                  controller: _controller,
                  enabled: configured,
                  sending: state.isSending,
                  stopping: state.turn?.cancelling ?? false,
                  onStop: AiChatService.instance.cancelTurn,
                  busyElsewhere: state.isBusyElsewhere,
                  onOpenBusyConversation: state.turn == null
                      ? null
                      : () => unawaited(
                          AiChatService.instance.openThread(
                            state.turn!.threadId,
                          ),
                        ),
                  onSend: () => unawaited(_send()),
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

  bool _canRetryFromBanner(AiChatState state) {
    if (state.isSending) return false;
    if (aiErrorCode(state.error) == 'consent_required') return true;
    switch (state.errorAction) {
      case AiErrorAction.none:
        return false;
      case AiErrorAction.retryTurn:
        return state.messages.any((message) => message.isUser);
      case AiErrorAction.retryProposal:
        return state.errorProposalId != null;
    }
  }

  // ===========================================================================
  // CONVERSATION
  // ===========================================================================

  static bool _isAssistantSide(AiChatItem item) =>
      item is AiAssistantItem ||
      item is AiStepsItem ||
      item is AiMemoryItem ||
      item is AiProposalItem;

  Widget _buildConversation(AiChatState state) {
    final l10n = AppLocalizations.of(context)!;
    final items = _itemsFor(state);
    final developerMode = _settings.settings.developerMode;
    final liveTurn = state.isTurnInActiveThread ? state.turn : null;

    final lastItem = items.isEmpty ? null : items.last;
    final showTurnInfo =
        developerMode &&
        liveTurn == null &&
        state.lastTurnDiagnostics.isNotEmpty &&
        lastItem is AiAssistantItem &&
        !lastItem.intermediate;

    // Rows at the bottom, below the newest item (index 0 is the lowest).
    final liveStarted = liveTurn != null && !_hadLiveTurn;
    _hadLiveTurn = liveTurn != null;
    final extras = <Widget>[
      if (liveTurn != null)
        AiScrollAnchor(
          key: const ValueKey('ai-live-turn'),
          reportInitial: liveStarted,
          trackChanges: true,
          // Gone because the turn ended, not because the list recycled it.
          reportRemoval: () =>
              !AiChatService.instance.state.isTurnInActiveThread,
          onHeightDelta: _correctForTail,
          child: AiLiveTurnBubble(
            turn: liveTurn,
            showAvatar: lastItem == null || !_isAssistantSide(lastItem),
          ),
        ),
      if (showTurnInfo)
        AiScrollAnchor(
          key: const ValueKey('ai-turn-info'),
          reportInitial: true,
          onHeightDelta: _correctForTail,
          child: AiTurnInfoRow(rounds: state.lastTurnDiagnostics),
        ),
    ];
    final hasHeader = state.hasOlderMessages || state.isLoadingOlderMessages;
    final lastUserId = _lastUserId(state.messages);
    final keyToIndex = <Key, int>{
      for (var i = 0; i < extras.length; i++)
        if (extras[i].key != null) extras[i].key!: i,
      for (var i = 0; i < items.length; i++)
        ValueKey(items[i].key): extras.length + (items.length - 1 - i),
    };

    return ListView.builder(
      controller: _scroll,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
      itemCount: extras.length + items.length + (hasHeader ? 1 : 0),
      findChildIndexCallback: (key) => keyToIndex[key],
      itemBuilder: (context, index) {
        if (index < extras.length) return extras[index];
        final itemIndex = items.length - 1 - (index - extras.length);
        if (itemIndex < 0) {
          return Center(
            key: const ValueKey('ai-older'),
            child: TextButton.icon(
              onPressed: state.isLoadingOlderMessages
                  ? null
                  : AiChatService.instance.loadOlderMessages,
              icon: state.isLoadingOlderMessages
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.history, size: 18),
              label: Text(
                state.isLoadingOlderMessages
                    ? l10n.aiChatOlderLoading
                    : l10n.aiChatLoadOlder,
              ),
            ),
          );
        }
        final item = items[itemIndex];
        return KeyedSubtree(
          key: ValueKey(item.key),
          child: AiScrollAnchor(
            reportInitial: _freshKeys.contains(item.key),
            onHeightDelta: _correctForTail,
            child: _buildItem(items, itemIndex, state, lastUserId),
          ),
        );
      },
    );
  }

  String? _lastUserId(List<AiChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].isUser) return messages[i].id;
    }
    return null;
  }

  Widget _buildItem(
    List<AiChatItem> items,
    int index,
    AiChatState state,
    String? lastUserId,
  ) {
    final item = items[index];
    final startsAnswer = index == 0 || !_isAssistantSide(items[index - 1]);
    final service = AiChatService.instance;
    final showTimestamp = _settings.settings.showMessageTimestamps;
    switch (item) {
      case AiUserItem(:final message):
        final unfinished =
            message.turnStatus == AiTurnStatus.cancelled ||
            message.turnStatus == AiTurnStatus.failed ||
            message.turnStatus == AiTurnStatus.interrupted;
        return AiMessageBubble(
          message: message,
          showTimestamp: showTimestamp,
          onCopy: () => MessageCopyAction.copy(context, message.content ?? ''),
          onRetryTurn:
              unfinished && message.id == lastUserId && !state.isSending
              ? () => unawaited(service.retryTurn(message.id))
              : null,
        );
      case AiAssistantItem(:final message, :final intermediate):
        return AiMessageBubble(
          message: message,
          showTimestamp: showTimestamp,
          showHeader: startsAnswer,
          intermediate: intermediate,
          onCopy: () => MessageCopyAction.copy(context, message.content ?? ''),
        );
      case AiStepsItem(:final steps):
        return AiAssistantFrame(
          showAvatar: startsAnswer,
          padding: EdgeInsets.fromLTRB(8, startsAnswer ? 12 : 4, 12, 4),
          child: AiToolStepsRow(
            steps: steps,
            developerMode: _settings.settings.developerMode,
          ),
        );
      case AiMemoryItem(:final step):
        return AiMemoryLine(
          step: step,
          onUndo: step.result == null
              ? null
              : () => unawaited(service.undoMemoryChange(step.result!.id)),
        );
      case AiProposalItem(:final toolCallId):
        final proposal = state.proposalForToolCall(toolCallId);
        if (proposal == null) return const SizedBox.shrink();
        return AiAssistantFrame(
          showAvatar: false,
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          child: AiProposalCard(
            proposal: proposal,
            busy: state.busyProposalIds.contains(proposal.id),
            onApprove: () => _approveProposal(proposal),
            onReject: () => service.rejectProposal(proposal.id),
          ),
        );
      case AiEventItem(:final payload):
        return AiEventLine(payload: payload);
    }
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

  void _showProviderSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiProviderPickerSheet(notifier: _settings),
    );
  }
}
