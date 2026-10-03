import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/l10n/app_localizations_en.dart';
import 'package:workout_notes/services/app_data_coordinator.dart';
import 'package:workout_notes/services/backup_actions.dart';
import 'package:workout_notes/services/export_service.dart';

import 'support/test_db.dart';

/// Records every call instead of touching the database or the file system.
class _FakeExportService extends ExportService {
  _FakeExportService(this.log);

  final List<String> log;
  Object? restoreError;
  int restoredCount = 7;

  @override
  Future<String> shareJsonBackup() async {
    log.add('share');
    return '/tmp/shared.json';
  }

  @override
  Future<String?> saveJsonBackup({required String dialogTitle}) async {
    log.add('save:$dialogTitle');
    return dialogTitle == 'cancel' ? null : '/tmp/saved.json';
  }

  @override
  Future<List<BackupFileInfo>> listLocalBackups() async {
    log.add('list');
    return [
      BackupFileInfo(
        path: '/backups/a.json',
        name: 'a.json',
        createdAt: DateTime(2026, 9, 1),
        sizeBytes: 12,
      ),
    ];
  }

  @override
  Future<String> getBackupsPathDescription(loc) async {
    log.add('path');
    return 'Downloads/Workout Notes';
  }

  Future<int> _restore(String what) async {
    log.add('restore:$what');
    final error = restoreError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return restoredCount;
  }

  @override
  Future<int> restoreFromFile(String filePath) => _restore('file:$filePath');

  @override
  Future<int> restoreFromJsonString(String jsonString) =>
      _restore('json:$jsonString');

  @override
  Future<int> restoreFromBytes(Uint8List bytes) =>
      _restore('bytes:${bytes.length}');
}

final class _FakePlatformFile extends PlatformFile {
  _FakePlatformFile({this.fileUri, this.bytes, this.bytesError});

  final Uri? fileUri;
  final Uint8List? bytes;
  final Object? bytesError;

  @override
  String get name => 'backup.json';

  @override
  Uri get uri => fileUri ?? Uri.parse('content://provider/backup.json');

  @override
  get xFile => throw UnimplementedError();

  @override
  int? lengthSync() => bytes?.length;

  @override
  Future<int?> length() async => bytes?.length ?? 0;

  @override
  Future<Uint8List> readAsBytes() async {
    final error = bytesError;
    if (error != null) Error.throwWithStackTrace(error, StackTrace.current);
    return bytes ?? Uint8List(0);
  }

  @override
  Stream<Uint8List> readAsByteStream() => Stream.value(bytes ?? Uint8List(0));
}

class _FakeFilePicker extends FilePickerPlatform {
  PlatformFile? result;
  Object? error;
  FileType? requestedType;
  List<String>? requestedExtensions;

  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    requestedType = type;
    requestedExtensions = allowedExtensions;
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> log;
  late _FakeExportService export;
  late BackupActions actions;
  late FilePickerPlatform originalPicker;
  late _FakeFilePicker picker;
  late Directory tempDir;

  setUpAll(() {
    initSqfliteFfiForTests();
    originalPicker = FilePickerPlatform.instance;
  });

  setUp(() {
    log = [];
    export = _FakeExportService(log);
    actions = BackupActions(
      exportService: export,
      coordinator: AppDataCoordinator(
        syncAlarms: () async => log.add('alarms'),
        syncMedications: () async => log.add('medications'),
        resetAi: () async => log.add('ai'),
        refreshAppearance: () async => log.add('appearance'),
      ),
    );
    picker = _FakeFilePicker();
    FilePickerPlatform.instance = picker;
    tempDir = Directory.systemTemp.createTempSync('backup_actions_test_');
  });

  tearDown(() async {
    FilePickerPlatform.instance = originalPicker;
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    await uninstallTestDb();
  });

  group('export side', () {
    test('delegates sharing, saving, listing and the path text', () async {
      expect(await actions.shareBackup(), '/tmp/shared.json');
      expect(await actions.saveBackup(dialogTitle: 'Save'), '/tmp/saved.json');
      expect(await actions.saveBackup(dialogTitle: 'cancel'), isNull);
      final backups = await actions.listLocalBackups();
      expect(backups.single.name, 'a.json');
      expect(
        await actions.backupsPathDescription(AppLocalizationsEn()),
        'Downloads/Workout Notes',
      );
      expect(log, ['share', 'save:Save', 'save:cancel', 'list', 'path']);
    });
  });

  group('restore', () {
    test('a file source restores then brings the app in line', () async {
      final count = await actions.restore(const BackupFileSource('/b/a.json'));

      expect(count, 7);
      expect(log, [
        'restore:file:/b/a.json',
        'alarms',
        'medications',
        'ai',
        'appearance',
      ]);
    });

    test('pasted JSON and picked bytes use their own restore path', () async {
      export.restoredCount = 3;
      expect(await actions.restore(const BackupJsonSource('{"a":1}')), 3);
      expect(
        await actions.restore(BackupBytesSource(Uint8List.fromList([1, 2]))),
        3,
      );

      expect(log.where((entry) => entry.startsWith('restore:')), [
        'restore:json:{"a":1}',
        'restore:bytes:2',
      ]);
    });

    test('a failed restore is rethrown and nothing is resynced', () async {
      export.restoreError = const FormatException('not a backup');

      await expectLater(
        actions.restore(const BackupJsonSource('garbage')),
        throwsFormatException,
      );

      expect(log, ['restore:json:garbage']);
    });
  });

  group('pickBackupFile', () {
    test('asks for a json file only', () async {
      await actions.pickBackupFile();

      expect(picker.requestedType, FileType.custom);
      expect(picker.requestedExtensions, ['json']);
    });

    test('returns null when the user cancels', () async {
      expect(await actions.pickBackupFile(), isNull);
    });

    test('streams a real file from its path instead of reading it', () async {
      final file = File('${tempDir.path}/backup.json')..writeAsStringSync('{}');
      picker.result = _FakePlatformFile(
        fileUri: file.uri,
        bytesError: StateError('must not be read'),
      );

      final picked = await actions.pickBackupFile();

      expect(picked!.source, isA<BackupFileSource>());
      expect((picked.source! as BackupFileSource).path, file.path);
    });

    test('falls back to bytes when the path is not readable', () async {
      picker.result = _FakePlatformFile(
        fileUri: Uri.file('${tempDir.path}/missing.json'),
        bytes: Uint8List.fromList([1, 2, 3]),
      );

      final picked = await actions.pickBackupFile();

      expect((picked!.source! as BackupBytesSource).bytes, [1, 2, 3]);
    });

    test('uses bytes for providers that expose no file path', () async {
      picker.result = _FakePlatformFile(bytes: Uint8List.fromList([9]));

      final picked = await actions.pickBackupFile();

      expect((picked!.source! as BackupBytesSource).bytes, [9]);
    });

    test('keeps the path when the bytes cannot be read', () async {
      final path = '${tempDir.path}/gone.json';
      picker.result = _FakePlatformFile(
        fileUri: Uri.file(path),
        bytesError: const FileSystemException('denied'),
      );

      final picked = await actions.pickBackupFile();

      expect((picked!.source! as BackupFileSource).path, path);
    });

    test('reports a file that exposes neither bytes nor a path', () async {
      picker.result = _FakePlatformFile(bytesError: StateError('no stream'));

      final picked = await actions.pickBackupFile();

      expect(picked, isNotNull);
      expect(picked!.source, isNull);
    });

    test('rethrows picker failures', () async {
      picker.error = StateError('picker crashed');

      await expectLater(actions.pickBackupFile(), throwsStateError);
    });
  });
}
