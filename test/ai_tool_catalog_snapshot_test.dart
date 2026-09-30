import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/services/ai_tool_registry.dart';

void main() {
  test('full chat tool catalog is byte-identical to the golden snapshot', () {
    final registry = AiToolRegistry();
    final encoded = const JsonEncoder.withIndent(
      '  ',
    ).convert(registry.openAiChatToolsSchema());
    final golden = File('test/fixtures/ai_tool_catalog.json');
    if (Platform.environment['UPDATE_GOLDEN'] == '1') {
      golden.createSync(recursive: true);
      golden.writeAsStringSync(encoded);
    }
    expect(encoded, golden.readAsStringSync());
  });
}
