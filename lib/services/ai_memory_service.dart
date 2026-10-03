import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_memory.dart';
import 'package:workout_notes/models/ai_message_role.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/ai_memory_repository.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';

const _uuid = Uuid();

/// Long-term memory of the AI Coach: a short list of durable facts about the
/// user shared by every conversation.
///
/// The model manages it with `save_memory` / `delete_memory`. These tools
/// change only the coach's own notes (never the user's training data), so
/// they apply immediately; the chat shows a "memory updated" line with undo
/// and the user can review or delete every entry in the AI settings.
class AiMemoryService extends ChangeNotifier {
  static final AiMemoryService instance = AiMemoryService();

  final AiMemoryRepository _repo;

  AiMemoryService({AiMemoryRepository? repo})
    : _repo = repo ?? DatabaseHelper.instance.aiMemoryRepo;

  static const int maxEntries = 40;
  static const int maxChars = 280;
  static const Set<String> toolNames = {'save_memory', 'delete_memory'};

  List<AiMemory>? _cache;

  Future<List<AiMemory>> all() async => _cache ??= await _repo.getAll();

  /// `<memory>` block for the stable part of the prompt; empty when there is
  /// nothing to remember. Ids are shortened to 8 characters. Every entry is a
  /// single quoted data line built from sanitized text (even for rows saved
  /// before sanitizing existed), so an entry can never close the block, start
  /// a new line of instructions or pose as a tag.
  Future<String> contextBlock() async {
    final memories = await all();
    if (memories.isEmpty) return '';
    return memories
        .map(
          (m) =>
              '- [${_short(m.id)}] (${m.category.name}) '
              '${jsonEncode(sanitizeContent(m.content))}',
        )
        .join('\n');
  }

  /// [text] as one plain line of data: control characters and line breaks
  /// become spaces and angle brackets become typographic ones (`‹ ›`), so no
  /// tag-like sequence (`</memory>`, `<app_event>`) survives. The model
  /// writes these notes without approval and they are read back as system
  /// context, so they are neutralized on save and again on render.
  static String sanitizeContent(String text) => text
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F-\u009F\u2028\u2029]+'), ' ')
      .replaceAll('<', '\u2039')
      .replaceAll('>', '\u203A')
      .replaceAll(RegExp(r' {2,}'), ' ')
      .trim();

  bool handles(String toolName) => toolNames.contains(toolName);

  List<AiToolSpec> toolSpecs() => [
    AiToolSpec(
      name: 'save_memory',
      domain: AiToolDomain.core,
      description:
          'Remember a durable fact about the user for future conversations '
          '(injury or limitation, equipment, schedule, preference, main goal). '
          'Write one self-contained sentence in the language of the '
          'conversation. To correct an existing entry pass its id as '
          'replaces_id instead of creating a duplicate. Applies immediately; '
          'the user can review and delete memories.',
      properties: {
        'content': {
          'type': 'string',
          'description': 'The fact, one sentence, max $maxChars characters.',
        },
        'category': {
          'type': 'string',
          'enum': [for (final c in AiMemoryCategory.values) c.name],
          'description': 'Kind of fact.',
        },
        'replaces_id': {
          'type': 'string',
          'description': 'Id (from <memory>) of the entry this one replaces.',
        },
      },
      required: ['content', 'category'],
    ),
    AiToolSpec(
      name: 'delete_memory',
      domain: AiToolDomain.core,
      description:
          'Forget a memory that is wrong or no longer true, or that the user '
          'asked you to forget.',
      properties: {
        'id': {'type': 'string', 'description': 'Id from <memory>.'},
      },
      required: ['id'],
    ),
  ];

  Future<AiToolResult> execute({
    required String toolName,
    required Map<String, dynamic> args,
    String? threadId,
  }) async {
    try {
      return switch (toolName) {
        'save_memory' => await _save(AiToolArgs(args), threadId),
        'delete_memory' => await _delete(AiToolArgs(args)),
        _ => const AiToolResult(ok: false, code: 'unknown_tool'),
      };
    } catch (error) {
      debugPrint('AI memory tool failed: $error');
      return const AiToolResult(
        ok: false,
        code: 'internal_error',
        message: 'memory update failed',
      );
    }
  }

  Future<AiToolResult> _save(AiToolArgs args, String? threadId) async {
    final raw = args.string('content');
    final content = raw == null ? null : sanitizeContent(raw);
    if (content == null || content.isEmpty) {
      return const AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: 'content is required',
      );
    }
    if (content.length > maxChars) {
      return const AiToolResult(
        ok: false,
        code: 'invalid_args',
        message: 'content is longer than $maxChars characters',
        hint: 'Write one short sentence.',
      );
    }
    final category = AiMemoryCategory.fromStorage(args.string('category'));
    final memories = await all();
    final replacesId = args.string('replaces_id');
    AiMemory? replaced;
    if (replacesId != null) {
      replaced = _find(memories, replacesId);
      if (replaced == null) {
        return AiToolResult(
          ok: false,
          code: 'not_found',
          message: 'memory "$replacesId" not found',
          hint: 'Use an id listed in <memory>, or omit replaces_id.',
        );
      }
    } else {
      final duplicate = memories.where(
        (m) => m.content.trim().toLowerCase() == content.toLowerCase(),
      );
      if (duplicate.isNotEmpty) {
        return AiToolResult(
          ok: true,
          data: {'id': _short(duplicate.first.id), 'status': 'already_saved'},
        );
      }
      if (memories.length >= maxEntries) {
        return const AiToolResult(
          ok: false,
          code: 'limit_reached',
          message: 'memory is full ($maxEntries entries)',
          hint: 'Replace or delete an outdated entry first.',
        );
      }
    }
    final now = DateTime.now();
    final memory =
        replaced?.copyWith(content: content, category: category) ??
        AiMemory(
          id: _uuid.v4(),
          content: content,
          category: category,
          sourceThreadId: threadId,
          createdAt: now,
          updatedAt: now,
        );
    await _repo.upsert(memory);
    _changed();
    return AiToolResult(
      ok: true,
      data: {
        'id': _short(memory.id),
        'status': replaced == null ? 'saved' : 'updated',
        'content': content,
        'memory_id': memory.id,
        if (replaced != null) 'previous_content': replaced.content,
        if (replaced != null) 'previous_category': replaced.category.name,
      },
    );
  }

  Future<AiToolResult> _delete(AiToolArgs args) async {
    final id = args.string('id');
    final memory = id == null ? null : _find(await all(), id);
    if (memory == null) {
      return AiToolResult(
        ok: false,
        code: 'not_found',
        message: 'memory "$id" not found',
        hint: 'Use an id listed in <memory>.',
      );
    }
    await _repo.delete(memory.id);
    _changed();
    return AiToolResult(
      ok: true,
      data: {
        'id': _short(memory.id),
        'status': 'deleted',
        'content': memory.content,
        'memory_id': memory.id,
        'category': memory.category.name,
        'created_at': memory.createdAt.toIso8601String(),
      },
    );
  }

  // --- user-facing management (settings screen, undo in chat) --------------

  Future<void> add(String content, AiMemoryCategory category) async {
    final now = DateTime.now();
    await _repo.upsert(
      AiMemory(
        id: _uuid.v4(),
        content: sanitizeContent(content),
        category: category,
        createdAt: now,
        updatedAt: now,
      ),
    );
    _changed();
  }

  Future<void> update(AiMemory memory) async {
    final clean = sanitizeContent(memory.content);
    await _repo.upsert(
      clean == memory.content ? memory : memory.copyWith(content: clean),
    );
    _changed();
  }

  Future<void> remove(String id) async {
    await _repo.delete(id);
    _changed();
  }

  /// Restores an entry removed by the model (chat "undo").
  Future<void> restore(AiMemory memory) async {
    await _repo.upsert(memory);
    _changed();
  }

  Future<void> clear() async {
    await _repo.deleteAll();
    _changed();
  }

  Future<AiMemory?> byId(String id) => _repo.getById(id);

  /// Forgets the in-memory list and tells listeners to reload it, after the
  /// table was changed behind this service's back (backup restore, reset).
  void invalidateCache() => _changed();

  void _changed() {
    _cache = null;
    notifyListeners();
  }

  @visibleForTesting
  void resetCacheForTest() => _cache = null;

  static String _short(String id) => id.length <= 8 ? id : id.substring(0, 8);

  /// The memory [id] names: an exact id, or the 8-character short id shown
  /// in `<memory>`. A prefix must be at least 6 characters and match exactly
  /// one entry; anything else (empty, truncated, ambiguous) matches nothing,
  /// because these tools change memory without an approval step.
  static AiMemory? _find(List<AiMemory> memories, String id) {
    final needle = id.trim().replaceAll(RegExp(r'^\[|\]$'), '').trim();
    if (needle.isEmpty) return null;
    for (final memory in memories) {
      if (memory.id == needle) return memory;
    }
    if (needle.length < 6) return null;
    final matches = [
      for (final memory in memories)
        if (memory.id.startsWith(needle)) memory,
    ];
    return matches.length == 1 ? matches.single : null;
  }
}
