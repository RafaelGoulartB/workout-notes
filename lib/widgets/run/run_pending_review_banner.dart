import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_review_draft.dart';
import 'package:workout_notes/screens/run/run_post_run_review_screen.dart';
import 'package:workout_notes/services/run_tracking_service.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Reminder for a finished run whose review was never saved or discarded
/// (the app was closed or backgrounded on the review screen). Without it the
/// recording would stay parked in the native spool with no way back to it.
///
/// Renders nothing while there is no pending review. Bump [refreshToken] to
/// re-read the pending list, e.g. after returning from the record screen.
class RunPendingReviewBanner extends StatefulWidget {
  final int refreshToken;

  /// Called after a review was saved or discarded from the banner, so the
  /// host can reload its own stats.
  final VoidCallback? onChanged;

  const RunPendingReviewBanner({
    super.key,
    this.refreshToken = 0,
    this.onChanged,
  });

  @override
  State<RunPendingReviewBanner> createState() => _RunPendingReviewBannerState();
}

class _RunPendingReviewBannerState extends State<RunPendingReviewBanner> {
  final _service = RunTrackingService.instance;
  List<RunReviewDraft> _drafts = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RunPendingReviewBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshToken != widget.refreshToken) _load();
  }

  Future<void> _load() async {
    List<RunReviewDraft> drafts;
    try {
      drafts = await _service.listPendingReviews();
    } catch (_) {
      drafts = const [];
    }
    if (!mounted) return;
    setState(() => _drafts = drafts);
  }

  Future<void> _review(RunReviewDraft draft) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => RunPostRunReviewScreen(draft: draft)),
    );
    if (!mounted) return;
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _discard(RunReviewDraft draft) async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: loc.runReviewDiscardTitle,
      message: loc.runReviewDiscardBody,
      confirmLabel: loc.runReviewDiscard,
      cancelLabel: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    await _service.discardReview(draft);
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_drafts.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final draft = _drafts.first;
    final activity = draft.activity;
    final seconds = activity.movingTimeSeconds > 0
        ? activity.movingTimeSeconds
        : activity.durationSeconds;
    final date = DateFormat.MMMd(
      Localizations.localeOf(context).toString(),
    ).add_Hm().format(activity.startedAt.toLocal());

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        key: const Key('run-pending-review-banner'),
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
        decoration: BoxDecoration(
          color: colors.tertiaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.tertiary.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.save_outlined, color: colors.tertiary),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.runHomePendingTitle(_drafts.length),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        loc.runHomePendingSubtitle(
                          RunFormatters.distanceWithUnit(
                            activity.distanceMeters,
                          ),
                          RunFormatters.duration(seconds),
                          date,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _busy ? null : () => _discard(draft),
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  child: Text(loc.runReviewDiscard),
                ),
                const SizedBox(width: 4),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _review(draft),
                  child: Text(loc.runHomePendingReview),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
