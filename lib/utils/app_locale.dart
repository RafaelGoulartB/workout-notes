import 'dart:ui';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Single source of truth for the app language (`pt` or `en`) and the `intl`
/// locale derived from it. The saved `app_locale` preference wins; without one
/// the device language decides (Portuguese -> `pt`, anything else -> `en`).
class AppLocale {
  const AppLocale._();

  /// `pt` or `en` for a saved preference value, falling back to [device].
  static String languageCode(String? saved, {Locale? device}) {
    if (saved == 'pt' || saved == 'pt_BR') return 'pt';
    if (saved == 'en') return 'en';
    final deviceLocale = device ?? PlatformDispatcher.instance.locale;
    return deviceLocale.languageCode == 'pt' ? 'pt' : 'en';
  }

  /// The Flutter locale for [languageCode].
  static Locale flutterLocale(String languageCode) =>
      languageCode == 'pt' ? const Locale('pt', 'BR') : const Locale('en');

  /// The `intl` locale name for [languageCode].
  static String intlName(String languageCode) =>
      languageCode == 'pt' ? 'pt_BR' : 'en';

  /// Loads the date symbols and makes [languageCode] the `Intl.defaultLocale`.
  static Future<void> apply(String languageCode) async {
    final name = intlName(languageCode);
    await initializeDateFormatting(name, null);
    Intl.defaultLocale = name;
  }
}
