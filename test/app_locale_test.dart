import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/utils/app_locale.dart';

void main() {
  tearDown(() => Intl.defaultLocale = null);

  group('AppLocale.languageCode', () {
    test('follows the device language when nothing is saved', () {
      expect(
        AppLocale.languageCode(null, device: const Locale('pt', 'BR')),
        'pt',
      );
      expect(
        AppLocale.languageCode(null, device: const Locale('pt', 'PT')),
        'pt',
      );
      expect(
        AppLocale.languageCode(null, device: const Locale('en', 'US')),
        'en',
      );
      expect(AppLocale.languageCode(null, device: const Locale('de')), 'en');
    });

    test('an explicit choice wins over the device language', () {
      expect(
        AppLocale.languageCode('en', device: const Locale('pt', 'BR')),
        'en',
      );
      expect(AppLocale.languageCode('pt', device: const Locale('en')), 'pt');
      expect(AppLocale.languageCode('pt_BR', device: const Locale('en')), 'pt');
    });
  });

  test('maps the language to Flutter and intl locales', () {
    expect(AppLocale.flutterLocale('pt'), const Locale('pt', 'BR'));
    expect(AppLocale.flutterLocale('en'), const Locale('en'));
    expect(AppLocale.intlName('pt'), 'pt_BR');
    expect(AppLocale.intlName('en'), 'en');
  });

  test('apply sets one Intl.defaultLocale for both entry points', () async {
    await AppLocale.apply('pt');
    expect(Intl.defaultLocale, 'pt_BR');
    expect(
      DateFormat.MMMd(Intl.defaultLocale).format(DateTime(2026, 3, 5)),
      '5 de mar.',
    );
    await AppLocale.apply('en');
    expect(Intl.defaultLocale, 'en');
  });
}
