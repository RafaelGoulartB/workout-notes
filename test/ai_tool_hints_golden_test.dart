import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

/// Guards the keyword routing hint against regressions: every query in the
/// corpus must map to exactly the tool set recorded in the golden file.
void main() {
  test('toolNamesForQuery matches the recorded golden for the corpus', () {
    final registry = AiToolRegistry();
    final corpus =
        (jsonDecode(
                  File(
                    'test/fixtures/ai_tool_hints_corpus.json',
                  ).readAsStringSync(),
                )
                as List)
            .cast<String>();
    final catalog =
        registry
            .openAiChatToolsSchema()
            .map((t) => (t['function'] as Map)['name'] as String)
            .toList()
          ..sort();
    final lines = <String>[
      for (final query in corpus)
        (registry.toolNamesForQuery(query).map(catalog.indexOf).toList()
              ..sort())
            .join(','),
    ];
    final golden = File('test/fixtures/ai_tool_hints_golden.txt');
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.writeAsStringSync(lines.join('\n'));
    }
    expect(lines.join('\n'), golden.readAsStringSync());
  });
}
