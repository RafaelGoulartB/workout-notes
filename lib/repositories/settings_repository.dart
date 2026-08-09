import 'package:sqflite/sqflite.dart';
import 'base_repository.dart';

/// Repository for app settings CRUD operations.
class SettingsRepository extends BaseRepository {
  Future<String?> getSetting(String key) async {
    final db = await this.db;
    final result = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
    );
    if (result.isEmpty) return null;
    return result.first['value'] as String;
  }

  Future<void> setSetting(String key, String value) async {
    final db = await this.db;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, String>> getAllSettings() async {
    final db = await this.db;
    final result = await db.query('app_settings');
    return {
      for (var row in result) row['key'] as String: row['value'] as String,
    };
  }

  Future<bool> getIsDistanceKm() async {
    final val = await getSetting('distance_unit');
    return val != 'mi';
  }

  Future<void> setDistanceUnitKm(bool isKm) async {
    await setSetting('distance_unit', isKm ? 'km' : 'mi');
  }
}
