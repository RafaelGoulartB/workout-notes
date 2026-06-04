import 'dart:convert';
import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/database_helper.dart';

class ExportService {
  final DatabaseHelper _db = DatabaseHelper.instance;

  Future<String> exportToJson() async {
    final data = await _db.exportAllData();
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/life_notes_backup_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(json);
    return file.path;
  }

  Future<void> shareJsonBackup() async {
    final path = await exportToJson();
    final file = XFile(path, mimeType: 'application/json');
    await Share.shareXFiles([file], text: 'Life Notes - Backup de Treinos');
  }

  Future<String> exportToCsv({
    String? exerciseId,
    String? exerciseName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final rows = await _db.exportWorkoutsCsvData(
      exerciseId: exerciseId,
      startDate: startDate,
      endDate: endDate,
    );

    final csvRows = <List<String>>[
      ['Data', 'Exercício', 'Categoria', 'Peso', 'Repetições', 'Distância', 'Tempo (s)', 'Aquecimento', 'RPE', 'Nota', 'Observação do Treino'],
    ];

    for (final row in rows) {
      csvRows.add([
        (row['date'] as String?) ?? '',
        (row['exercise'] as String?) ?? '',
        (row['category'] as String?) ?? '',
        (row['weight'] as num?)?.toStringAsFixed(1) ?? '',
        (row['reps'] as int?)?.toString() ?? '',
        (row['distance'] as num?)?.toStringAsFixed(2) ?? '',
        (row['time_seconds'] as int?)?.toString() ?? '',
        (row['is_warmup'] as int?) == 1 ? 'Sim' : 'Não',
        (row['rpe'] as num?)?.toStringAsFixed(1) ?? '',
        (row['set_comment'] as String?) ?? '',
        (row['workout_comment'] as String?) ?? '',
      ]);
    }

    final csvData = const ListToCsvConverter().convert(csvRows);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/life_notes_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(csvData);
    return file.path;
  }

  Future<void> shareCsvExport({
    String? exerciseId,
    String? exerciseName,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final path = await exportToCsv(
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      startDate: startDate,
      endDate: endDate,
    );
    final file = XFile(path, mimeType: 'text/csv');
    await Share.shareXFiles([file], text: 'Life Notes - Exportação de Treinos');
  }

  Future<int> importFromJson(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final data = jsonDecode(content) as Map<String, dynamic>;
    return _db.importData(data);
  }

  Future<void> shareWorkoutSummary(String workoutId) async {
    final workout = await _db.getWorkout(workoutId);
    if (workout == null) return;

    final exercises = await _db.getWorkoutExercises(workoutId);
    final date = (workout['date'] as String?) ?? '';
    final comment = (workout['comment'] as String?) ?? '';

    var text = '🏋️ Treino - $date\n';
    if (comment.isNotEmpty) text += '📝 $comment\n';
    text += '\n';

    for (final ex in exercises) {
      final sets = await _db.getExerciseSets(ex['id'] as String);
      final exName = (ex['exercise_name'] as String?) ?? '';
      text += '\n$exName\n';
      for (int i = 0; i < sets.length; i++) {
        final s = sets[i];
        final weight = (s['weight'] as num?)?.toStringAsFixed(1) ?? '-';
        final reps = (s['reps'] as int?)?.toString() ?? '-';
        final complete = (s['is_complete'] as int?) == 1 ? '✅' : '⬜';
        text += '   $complete $i: $weight kg × $reps\n';
      }
    }

    await Share.share(text);
  }
}
