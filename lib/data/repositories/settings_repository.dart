import '../db/database.dart';

class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  Future<String?> get(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> set(String key, String value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, value: value),
        );
  }

  Future<void> remove(String key) async {
    await (db.delete(db.appSettings)..where((t) => t.key.equals(key))).go();
  }

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final value = await get(key);
    if (value == null) return fallback;
    return value == 'true' || value == '1';
  }

  Future<int> getInt(String key, {int fallback = 0}) async =>
      int.tryParse(await get(key) ?? '') ?? fallback;

  Future<double> getDouble(String key, {double fallback = 0}) async =>
      double.tryParse(await get(key) ?? '') ?? fallback;

  Future<Map<String, String>> all() async {
    final rows = await db.select(db.appSettings).get();
    return {for (final row in rows) row.key: row.value};
  }
}
