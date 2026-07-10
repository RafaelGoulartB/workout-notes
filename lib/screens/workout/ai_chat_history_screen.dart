import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../state/ai_chat_service.dart';
import '../../widgets/empty_state_placeholder.dart';

class AiChatHistoryScreen extends StatefulWidget {
  const AiChatHistoryScreen({super.key});

  @override
  State<AiChatHistoryScreen> createState() => _AiChatHistoryScreenState();
}

class _AiChatHistoryScreenState extends State<AiChatHistoryScreen> {
  @override
  void initState() {
    super.initState();
    AiChatService.instance.addListener(_onChange);
  }

  @override
  void dispose() {
    AiChatService.instance.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final threads = AiChatService.instance.state.threads;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de conversas'),
      ),
      body: threads.isEmpty
          ? const EmptyStatePlaceholder(
              icon: Icons.history_rounded,
              title: 'Nenhuma conversa ainda',
              subtitle: 'Comece uma nova conversa no chat do Treinador IA.',
            )
          : ListView.separated(
              itemCount: threads.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final t = threads[i];
                return Dismissible(
                  key: ValueKey(t.id),
                  background: Container(
                    color: theme.colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Icon(
                      Icons.delete_rounded,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) async {
                    return await showDialog<bool>(
                          context: context,
                          builder: (_) => AlertDialog(
                            title: const Text('Apagar conversa?'),
                            content: Text(
                              'Esta ação não pode ser desfeita. "${t.title}" será removida.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: Text(l10n.commonCancel),
                              ),
                              FilledButton.tonal(
                                onPressed: () => Navigator.pop(context, true),
                                child: Text(l10n.commonDelete),
                              ),
                            ],
                          ),
                        ) ??
                        false;
                  },
                  onDismissed: (_) async {
                    await AiChatService.instance.deleteThread(t.id);
                  },
                  child: ListTile(
                    leading: const Icon(Icons.chat_bubble_outline_rounded),
                    title: Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: t.lastMessagePreview != null
                        ? Text(
                            t.lastMessagePreview!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          )
                        : null,
                    trailing: Text(_formatTimestamp(t.updatedAt)),
                    onTap: () async {
                      await AiChatService.instance.openThread(t.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                  ),
                );
              },
            ),
    );
  }

  String _formatTimestamp(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tsDay = DateTime(t.year, t.month, t.day);
    final diff = today.difference(tsDay).inDays;
    if (diff == 0) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'ontem';
    if (diff < 7) return '${diff}d';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
  }
}
