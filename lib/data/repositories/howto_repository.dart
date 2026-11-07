import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class HowToRepository extends RepositoryBase {
  HowToRepository(super.db, super.deviceId);

  Stream<List<HowTo>> watchActive({
    String? category,
    HowToDifficulty? difficulty,
  }) {
    final query = db.select(db.howTos)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]);
    if (category != null && category.isNotEmpty && category != 'All') {
      query.where((t) => t.category.equals(category));
    }
    if (difficulty != null) {
      query.where((t) => t.difficulty.equalsValue(difficulty));
    }
    return query.watch();
  }

  Future<List<HowTo>> activeList() =>
      (db.select(db.howTos)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<HowTo?> byId(String id) =>
      (db.select(db.howTos)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<HowTo> create({
    String title = 'New how-to',
    String category = 'Servers',
    HowToDifficulty difficulty = HowToDifficulty.easy,
    List<Map<String, dynamic>> steps = const [],
    String tagsCsv = '',
  }) async {
    final stamp = now;
    final row = HowTo(
      id: const Uuid().v4(),
      title: title,
      category: category,
      difficulty: difficulty,
      stepsJson: jsonEncode(steps),
      tagsCsv: tagsCsv,
      lastTested: null,
      relatedServerIds: '[]',
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.howTos).insert(row);
    return row;
  }

  Future<HowTo> save(
    HowTo howTo, {
    required String title,
    required String category,
    required HowToDifficulty difficulty,
    required List<Map<String, dynamic>> steps,
    required String tagsCsv,
    DateTime? lastTested,
    List<String> relatedServerIds = const [],
  }) async {
    final stamp = now;
    final version = howTo.version + 1;
    final stepsJson = jsonEncode(steps);
    await db.transaction(() async {
      await (db.update(db.howTos)..where((t) => t.id.equals(howTo.id))).write(
        HowTosCompanion(
          title: Value(title.trim().isEmpty ? 'Untitled how-to' : title.trim()),
          category: Value(category),
          difficulty: Value(difficulty),
          stepsJson: Value(stepsJson),
          tagsCsv: Value(tagsCsv),
          lastTested: Value(lastTested),
          relatedServerIds: Value(jsonEncode(relatedServerIds)),
          updatedAt: Value(stamp),
          version: Value(version),
          syncStatus: const Value(SyncState.pending),
        ),
      );
      await db
          .into(db.revisions)
          .insert(
            Revision(
              id: const Uuid().v4(),
              entityType: 'howto',
              entityId: howTo.id,
              version: version,
              contentJson: jsonEncode({
                'title': title,
                'category': category,
                'difficulty': difficulty.name,
                'steps': steps,
                'tagsCsv': tagsCsv,
              }),
              createdAt: stamp,
            ),
          );
    });
    return (await byId(howTo.id))!;
  }

  Future<void> markTested(HowTo howTo) async {
    await (db.update(db.howTos)..where((t) => t.id.equals(howTo.id))).write(
      HowTosCompanion(
        lastTested: Value(now),
        updatedAt: Value(now),
        version: Value(howTo.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final row = await byId(id);
    if (row == null) return;
    await (db.update(db.howTos)..where((t) => t.id.equals(id))).write(
      HowTosCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> restore(String id) async {
    final row = await byId(id);
    if (row == null) return;
    await (db.update(db.howTos)..where((t) => t.id.equals(id))).write(
      HowTosCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    await db.transaction(() async {
      await (db.delete(
            db.revisions,
          )..where((t) => t.entityType.equals('howto') & t.entityId.equals(id)))
          .go();
      await (db.delete(db.howTos)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<Revision>> revisions(String id) =>
      (db.select(db.revisions)
            ..where((t) => t.entityType.equals('howto') & t.entityId.equals(id))
            ..orderBy([(t) => OrderingTerm.desc(t.version)]))
          .get();
}
