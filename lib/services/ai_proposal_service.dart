import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_proposal.dart';
import 'package:workout_notes/repositories/ai_proposal_repository.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handler.dart';
import 'package:workout_notes/services/ai_proposals/ai_proposal_handlers.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

/// How long a proposal can wait for an answer. After that it expires: the data
/// it was based on has most likely moved on.
const Duration kAiProposalLifetime = Duration(days: 7);

/// Generic proposal pipeline: one handler per kind (routine, meal log, body
/// measurement, goal, …) behind a single prepare → approve/reject flow.
///
/// The AI never writes. It calls a `propose_*` tool; [prepare] validates the
/// arguments and stores an `awaiting` proposal with an honest preview; only
/// [approve] (or [markApplied] for forms the user saved) changes data. Approval
/// is one SQLite transaction: atomic claim, revalidation against the state the
/// proposal was based on, apply, outcome. A failed apply rolls everything back
/// and the proposal ends `failed` (or `stale` when the data moved).
class AiProposalService {
  final DatabaseHelper _db;
  final DateTime Function() _now;
  final Map<String, AiProposalHandler> _byKind;
  final Map<String, AiProposalHandler> _byTool;
  final List<AiProposalHandler> _handlers;

  AiProposalService({
    DatabaseHelper? db,
    List<AiProposalHandler>? handlers,
    DateTime Function()? now,
  }) : _db = db ?? DatabaseHelper.instance,
       _now = now ?? DateTime.now,
       _handlers = handlers ?? defaultAiProposalHandlers(db: db, now: now),
       _byKind = {},
       _byTool = {} {
    for (final handler in _handlers) {
      _byKind[handler.kind] = handler;
      _byTool[handler.toolName] = handler;
    }
  }

  AiProposalRepository get _repo => _db.aiProposalRepo;

  /// Tool specs of every proposal kind, in a stable order. Their handlers are
  /// unused: proposal tool calls go through [prepare].
  List<AiToolSpec> toolSpecs() => [for (final h in _handlers) h.catalogSpec];

  /// Whether [toolName] is a proposal tool handled by [prepare].
  bool handles(String toolName) => _byTool.containsKey(toolName);

  /// How approving [proposal] reaches the database. Unknown kinds (written by
  /// a newer version of the app) are treated as transactional but can only
  /// end `failed`.
  AiProposalApplyMode applyModeOf(AiProposal proposal) =>
      _byKind[proposal.kind]?.applyMode ?? AiProposalApplyMode.transactional;

  /// Validates the model's arguments and stores an `awaiting` proposal.
  /// The returned result is what the model sees: on success
  /// `{proposal_id, kind, status: awaiting, summary}`; on failure
  /// `ok:false` with `code`, `message` and a `hint` the model can act on.
  Future<AiToolResult> prepare({
    required String threadId,
    required String toolCallId,
    required String toolName,
    required Map<String, dynamic> args,
  }) async {
    final handler = _byTool[toolName];
    if (handler == null) {
      return AiToolResult(
        ok: false,
        code: 'unknown_tool',
        message: 'Tool "$toolName" is not a proposal tool.',
      );
    }
    try {
      await _expireOld();
      // A retried call must not create a second card.
      final sameCall = await _repo.byToolCall(threadId, toolCallId);
      if (sameCall != null && sameCall.kind == handler.kind) {
        return _toolResult(sameCall, handler, reused: true);
      }
      final database = await _db.database;
      final draft = await handler.prepare(database, AiProposalArgs(args));
      final pending = await _repo.awaitingOfKind(threadId, handler.kind);
      final same = pending.firstWhereOrNull(
        (p) =>
            p.subjectId == draft.subjectId &&
            p.baseHash == draft.baseHash &&
            const DeepCollectionEquality().equals(p.payload, draft.payload),
      );
      if (same != null) return _toolResult(same, handler, reused: true);
      final proposal = AiProposal(
        id: const Uuid().v4(),
        threadId: threadId,
        toolCallId: toolCallId,
        kind: handler.kind,
        subjectId: draft.subjectId,
        baseHash: draft.baseHash,
        base: draft.base,
        payload: draft.payload,
        preview: {...draft.preview, 'summary': draft.summary},
        status: AiProposalStatus.awaiting,
        createdAt: _now(),
      );
      await _repo.insert(proposal);
      return _toolResult(proposal, handler);
    } on AiProposalException catch (error) {
      return error.toToolResult();
    } catch (error, stackTrace) {
      debugPrint('AiProposalService.prepare($toolName) failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return const AiToolResult(
        ok: false,
        code: 'internal_error',
        message: 'The proposal could not be prepared.',
        data: {'hint': 'Try again, or tell the user it could not be prepared.'},
      );
    }
  }

  AiToolResult _toolResult(
    AiProposal proposal,
    AiProposalHandler handler, {
    bool reused = false,
  }) => AiToolResult(
    ok: true,
    data: {
      'proposal_id': proposal.id,
      'kind': proposal.kind,
      'status': proposal.status.storageValue,
      'applied': false,
      'summary': proposal.preview['summary'] ?? const {},
      'note':
          'NOTHING was applied or saved. The user sees a card in the app and '
          'must approve it. Tell the user it is waiting for their approval; '
          'do not say it was done.',
      if (reused) 'reused': true,
    },
  );

  /// Proposals of a conversation, oldest first. Awaiting proposals older than
  /// [kAiProposalLifetime] are expired first; previews written by an older
  /// version are rebuilt once.
  Future<List<AiProposal>> forThread(String threadId) async {
    await _expireOld();
    final list = await _repo.forThread(threadId);
    return [for (final p in list) await _refreshPreview(p)];
  }

  Future<AiProposal?> get(String id) async {
    await _expireOld();
    final proposal = await _repo.get(id);
    return proposal == null ? null : _refreshPreview(proposal);
  }

  /// Approves a transactional proposal: claim, revalidate against its base,
  /// apply in one transaction. Returns the updated proposal (applied, stale or
  /// failed). Idempotent: approving a resolved proposal returns it unchanged,
  /// and a user-confirmed kind is left awaiting (its form applies it).
  Future<AiProposal> approve(String id) async {
    await _expireOld();
    final database = await _db.database;
    AiProposalException? failure;
    AiProposal? outcome;
    try {
      outcome = await database.transaction((txn) async {
        final proposal = await _repo.get(id, executor: txn);
        if (proposal == null) {
          throw const AiProposalException('not_found', 'Proposal not found.');
        }
        if (!proposal.isPending) return proposal;
        final handler = _byKind[proposal.kind];
        if (handler == null) {
          throw AiProposalException(
            'unknown_kind',
            'Unknown proposal kind "${proposal.kind}".',
          );
        }
        if (handler.applyMode != AiProposalApplyMode.transactional) {
          return proposal;
        }
        final at = _now();
        final claimed = await _repo.transition(
          txn,
          id,
          from: AiProposalStatus.awaiting,
          to: AiProposalStatus.applied,
          at: at,
        );
        if (claimed != 1) return (await _repo.get(id, executor: txn))!;
        final staleCode = await handler.revalidate(txn, proposal);
        if (staleCode != null) {
          await _repo.transition(
            txn,
            id,
            from: AiProposalStatus.applied,
            to: AiProposalStatus.stale,
            at: at,
            errorCode: staleCode,
          );
          return proposal.copyWith(
            status: AiProposalStatus.stale,
            errorCode: staleCode,
            resolvedAt: at,
          );
        }
        final result = await handler.apply(txn, proposal);
        await _repo.setResult(txn, id, result);
        return proposal.copyWith(
          status: AiProposalStatus.applied,
          result: result,
          resolvedAt: at,
        );
      });
    } on AiProposalException catch (error) {
      failure = error;
    } catch (error, stackTrace) {
      debugPrint('AiProposalService.approve($id) failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      failure = const AiProposalException(
        'apply_failed',
        'The proposal could not be applied.',
      );
    }
    if (failure != null) {
      if (failure.code == 'not_found') throw failure;
      // The transaction rolled back (the claim with it): record why.
      await _repo.transition(
        database,
        id,
        from: AiProposalStatus.awaiting,
        to: failure.stale ? AiProposalStatus.stale : AiProposalStatus.failed,
        at: _now(),
        errorCode: failure.code,
      );
      return (await _repo.get(id))!;
    }
    return outcome!;
  }

  /// Rejects an awaiting proposal. Idempotent.
  Future<AiProposal> reject(String id) async {
    final database = await _db.database;
    await _repo.transition(
      database,
      id,
      from: AiProposalStatus.awaiting,
      to: AiProposalStatus.rejected,
      at: _now(),
    );
    final proposal = await _repo.get(id);
    if (proposal == null) {
      throw const AiProposalException('not_found', 'Proposal not found.');
    }
    return proposal;
  }

  /// Marks a user-confirmed proposal (approval opened a form) as applied once
  /// the user saved the form.
  Future<AiProposal> markApplied(
    String id, {
    Map<String, dynamic>? result,
  }) async {
    final database = await _db.database;
    final proposal = await _repo.get(id);
    if (proposal == null) {
      throw const AiProposalException('not_found', 'Proposal not found.');
    }
    if (applyModeOf(proposal) != AiProposalApplyMode.userConfirmed) {
      throw const AiProposalException(
        'invalid_state',
        'Only user-confirmed proposals are marked applied by the app.',
      );
    }
    await _repo.transition(
      database,
      id,
      from: AiProposalStatus.awaiting,
      to: AiProposalStatus.applied,
      at: _now(),
      result: result ?? const {},
    );
    return (await _repo.get(id))!;
  }

  /// Compact, language-neutral facts about [proposal]'s outcome that the
  /// orchestrator appends to the transcript so the model learns what happened
  /// (applied, rejected, stale…) without an extra provider call.
  Map<String, dynamic> outcomeFacts(AiProposal proposal) {
    final handler = _byKind[proposal.kind];
    final status = proposal.status;
    return {
      'proposal_id': proposal.id,
      'kind': proposal.kind,
      'status': status.storageValue,
      'applied': status == AiProposalStatus.applied,
      if (proposal.errorCode != null) 'error_code': proposal.errorCode,
      if (status == AiProposalStatus.applied)
        'result': handler?.resultFacts(proposal) ?? proposal.result ?? const {},
      'note': switch (status) {
        AiProposalStatus.applied => 'The user approved it and it was applied.',
        AiProposalStatus.rejected =>
          'The user rejected it. Nothing was changed.',
        AiProposalStatus.stale =>
          'The data changed after the proposal, so it was NOT applied. '
              'Re-read the data and propose again if the user still wants it.',
        AiProposalStatus.failed =>
          'It could not be applied and nothing was changed.',
        AiProposalStatus.expired =>
          'It expired without an answer. Nothing was changed.',
        AiProposalStatus.awaiting => 'Still waiting for the user to decide.',
      },
    };
  }

  Future<void> _expireOld() async {
    final now = _now();
    await _repo.expireAwaitingBefore(
      now.subtract(kAiProposalLifetime),
      now: now,
    );
  }

  /// Rebuilds the preview of a proposal stored by an older app version.
  Future<AiProposal> _refreshPreview(AiProposal proposal) async {
    final handler = _byKind[proposal.kind];
    if (handler == null || !handler.needsPreviewRefresh(proposal)) {
      return proposal;
    }
    try {
      final database = await _db.database;
      final rebuilt = await handler.rebuildPreview(database, proposal);
      if (rebuilt == null) return proposal;
      await _repo.updatePreview(proposal.id, rebuilt);
      return proposal.copyWith(preview: rebuilt);
    } catch (error) {
      debugPrint('Could not rebuild the preview of ${proposal.id}: $error');
      return proposal;
    }
  }
}
