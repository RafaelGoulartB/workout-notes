import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/repositories/export_import_repository.dart';
import 'package:workout_notes/services/export_service.dart';

import 'support/test_db.dart';

Map<String, Object?> _provider(String id, String baseUrl) => {
  'id': id,
  'name': 'Provider $id',
  'baseUrl': baseUrl,
  'availableModels': <String>[],
  'selectedModel': 'm',
  'createdAt': '2026-08-29T08:00:00.000Z',
};

void main() {
  late Database database;
  late ExportService service;
  late Directory temp;

  setUpAll(initSqfliteFfiForTests);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('restore_ai_tokens_');
    database = await openTestDb();
    FlutterSecureStorage.setMockInitialValues({
      'ai_token:same': 'secret-same',
      'ai_token:moved': 'secret-moved',
      'ai_token:gone': 'secret-gone',
      'ai_token:fresh': 'secret-fresh',
      'unrelated': 'keep',
    });
    service = ExportService(
      exportRepo: ExportImportRepository(
        databaseProvider: () async => database,
      ),
      backupsDirectoryProvider: () async => temp,
    );
  });

  tearDown(() async {
    await database.close();
    await temp.delete(recursive: true);
  });

  /// Exports the current (local) state, then swaps the providers in the file
  /// for [restored], like a backup made on another device.
  Future<Uint8List> backupWithProviders(
    List<Map<String, Object?>> restored,
  ) async {
    final exported =
        jsonDecode(utf8.decode(await service.exportBackupBytes()))
            as Map<String, dynamic>;
    (exported['preferences'] as Map)['ai_providers_v1'] = jsonEncode(restored);
    return Uint8List.fromList(utf8.encode(jsonEncode(exported)));
  }

  Future<Map<String, String>> storedTokens() =>
      const FlutterSecureStorage().readAll();

  test('a restored provider with a different URL loses the local token', () async {
    SharedPreferences.setMockInitialValues({
      'ai_providers_v1': jsonEncode([
        _provider('same', 'https://api.example.com/v1'),
        _provider('moved', 'https://api.example.com/v1'),
        _provider('gone', 'https://other.example.com/v1'),
      ]),
    });
    final backup = await backupWithProviders([
      // Same id, same URL (only spelled differently): the token stays.
      _provider('same', 'https://api.example.com/v1/'),
      // Same id, URL now points elsewhere: the token must not follow it.
      _provider('moved', 'https://evil.example.net/v1'),
      // An id this device never had.
      _provider('fresh', 'https://api.example.com/v1'),
    ]);

    await service.restoreFromBytes(backup);

    final tokens = await storedTokens();
    expect(tokens['ai_token:same'], 'secret-same');
    expect(tokens.containsKey('ai_token:moved'), isFalse);
    expect(tokens.containsKey('ai_token:fresh'), isFalse);
    // Providers absent from the backup and unrelated secrets are untouched.
    expect(tokens['ai_token:gone'], 'secret-gone');
    expect(tokens['unrelated'], 'keep');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_providers_v1'), contains('evil.example.net'));
  });

  test('a restore that fails keeps every token', () async {
    SharedPreferences.setMockInitialValues({
      'ai_providers_v1': jsonEncode([
        _provider('moved', 'https://api.example.com/v1'),
      ]),
    });
    final exported =
        jsonDecode(utf8.decode(await service.exportBackupBytes()))
            as Map<String, dynamic>;
    (exported['preferences'] as Map)['ai_providers_v1'] = jsonEncode([
      _provider('moved', 'https://evil.example.net/v1'),
    ]);
    // Breaks the manifest so the database restore throws after the checks.
    exported['categories'] = [
      {'id': 'x'},
    ];
    (exported['record_counts'] as Map)['categories'] = 1;

    await expectLater(
      service.restoreFromBytes(
        Uint8List.fromList(utf8.encode(jsonEncode(exported))),
      ),
      throwsA(anything),
    );

    expect((await storedTokens())['ai_token:moved'], 'secret-moved');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('ai_providers_v1'), contains('api.example.com'));
  });
}
