import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workout_notes/state/ai_settings_notifier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the legacy token is migrated once, then secure storage is skipped',
    () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = AiSettingsNotifier(prefs: prefs);
      final provider = await settings.addProvider(
        name: 'Old',
        baseUrl: 'https://api.old/v1',
      );

      // A token left by the pre-multi-provider build.
      const storage = FlutterSecureStorage();
      await storage.write(key: 'ai_token', value: 'legacy-secret');

      await settings.load();
      expect(await settings.getToken(provider.id), 'legacy-secret');
      expect(await storage.read(key: 'ai_token'), isNull);
      expect(prefs.getBool('ai_legacy_token_migrated_v1'), isTrue);

      // Later launches never look at the legacy key again.
      await storage.write(key: 'ai_token', value: 'late-value');
      await settings.load();
      expect(await storage.read(key: 'ai_token'), 'late-value');
    },
  );
}
