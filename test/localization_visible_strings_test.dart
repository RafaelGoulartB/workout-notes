import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('visible UI strings are sourced from AppLocalizations', () {
    final roots = [Directory('lib/screens'), Directory('lib/widgets')];
    final literalPatterns = [
      RegExp(
        r'''(?:const\s+)?Text\(\s*(['"])([A-Za-zÀ-ÿ][^'"\r\n]*)\1''',
        multiLine: true,
      ),
      RegExp(
        r'''(?:tooltip|labelText|helperText|semanticLabel)\s*:\s*(['"])([A-Za-zÀ-ÿ][^'"\r\n]*)\1''',
        multiLine: true,
      ),
    ];
    const localeIndependentLabels = {'RPE', 's', 'km', 'kcal', 'g'};
    final violations = <String>[];

    for (final root in roots) {
      for (final entity in root.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final pattern in literalPatterns) {
          for (final match in pattern.allMatches(source)) {
            final value = match.group(2)!;
            if (localeIndependentLabels.contains(value)) continue;
            if (value.startsWith(r'v${') || value.startsWith(r'S${')) continue;
            final line =
                '\n'.allMatches(source.substring(0, match.start)).length + 1;
            violations.add('${entity.path}:$line: $value');
          }
        }
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'Move visible text to app_en.arb and app_pt.arb, then run '
          '`flutter gen-l10n`:\n${violations.join('\n')}',
    );
  });
}
