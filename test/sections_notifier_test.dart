import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:workout_notes/state/sections_notifier.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('plan section is enabled by default', () {
    final sections = SectionsNotifier();
    expect(sections.planEnabled, isTrue);
  });

  test('setPlanEnabled persists the value', () async {
    final sections = SectionsNotifier();
    await sections.setPlanEnabled(false);
    expect(sections.planEnabled, isFalse);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kPrefsPlanSectionEnabled), isFalse);

    final reloaded = SectionsNotifier(
      prefs.getBool(kPrefsPlanSectionEnabled) ?? true,
    );
    expect(reloaded.planEnabled, isFalse);
  });
}
