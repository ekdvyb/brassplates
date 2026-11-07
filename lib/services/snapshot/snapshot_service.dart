import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';

class SnapshotService {
  SnapshotService(this.db);

  final AppDatabase db;

  Future<Directory> _snapshotDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'snapshots'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<File> databaseFile() async {
    final support = await getApplicationSupportDirectory();
    return File(p.join(support.path, 'brassplates.sqlite'));
  }

  Future<Snapshot> create(String reason) async {
    final dir = await _snapshotDir();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final target = File(p.join(dir.path, 'brassplates-$stamp.sqlite'));
    // VACUUM INTO produces a transactionally consistent copy even with WAL.
    await db.customStatement(
      "VACUUM INTO '${target.path.replaceAll("'", "''")}'",
    );
    final size = await target.length();
    final row = Snapshot(
      id: newId(),
      path: target.path,
      reason: reason,
      bytes: size,
      createdAt: DateTime.now(),
    );
    await db.into(db.snapshots).insert(row);
    await _trim();
    return row;
  }

  Future<void> maybeDailySnapshot() async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day);
    final existing =
        await (db.select(db.snapshots)
              ..where((t) => t.createdAt.isBiggerOrEqualValue(start))
              ..limit(1))
            .getSingleOrNull();
    if (existing == null) {
      await create('daily');
    }
  }

  Future<List<Snapshot>> list() => (db.select(
    db.snapshots,
  )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

  Future<void> _trim({int keep = 14}) async {
    final all = await list();
    if (all.length <= keep) return;
    for (final stale in all.skip(keep)) {
      final file = File(stale.path);
      if (await file.exists()) {
        await file.delete();
      }
      await (db.delete(db.snapshots)..where((t) => t.id.equals(stale.id))).go();
    }
  }

  /// Restores a snapshot. The database is closed first; the caller must restart
  /// the app afterwards.
  Future<void> restore(Snapshot snapshot) async {
    final source = File(snapshot.path);
    if (!await source.exists()) {
      throw StateError('Snapshot file is missing: ${snapshot.path}');
    }
    final target = await databaseFile();
    await db.close();
    await source.copy(target.path);
    final wal = File('${target.path}-wal');
    final shm = File('${target.path}-shm');
    if (await wal.exists()) await wal.delete();
    if (await shm.exists()) await shm.delete();
  }

  Future<void> deleteSnapshot(Snapshot snapshot) async {
    final file = File(snapshot.path);
    if (await file.exists()) await file.delete();
    await (db.delete(
      db.snapshots,
    )..where((t) => t.id.equals(snapshot.id))).go();
  }
}
