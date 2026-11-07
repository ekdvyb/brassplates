import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class DiagramsRepository extends RepositoryBase {
  DiagramsRepository(super.db, super.deviceId);

  Stream<List<Diagram>> watchActive() =>
      (db.select(db.diagrams)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Future<List<Diagram>> activeList() =>
      (db.select(db.diagrams)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<Diagram?> byId(String id) =>
      (db.select(db.diagrams)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Diagram> create({
    String title = 'Untitled diagram',
    String documentJson = '{}',
    String? thumbnailBase64,
    String searchText = '',
    String? folderId,
  }) async {
    final stamp = now;
    final row = Diagram(
      id: const Uuid().v4(),
      title: title,
      folderId: folderId,
      schemaVersion: 1,
      documentJson: documentJson,
      thumbnailBase64: thumbnailBase64,
      searchText: searchText,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.diagrams).insert(row);
    return row;
  }

  Future<Diagram> save(
    Diagram diagram, {
    required String title,
    required String documentJson,
    String? thumbnailBase64,
    required String searchText,
  }) async {
    final version = diagram.version + 1;
    final stamp = now;
    await db.transaction(() async {
      await (db.update(
        db.diagrams,
      )..where((t) => t.id.equals(diagram.id))).write(
        DiagramsCompanion(
          title: Value(
            title.trim().isEmpty ? 'Untitled diagram' : title.trim(),
          ),
          schemaVersion: const Value(1),
          documentJson: Value(documentJson),
          thumbnailBase64: thumbnailBase64 == null
              ? const Value.absent()
              : Value(thumbnailBase64),
          searchText: Value(searchText),
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
              entityType: 'diagram',
              entityId: diagram.id,
              version: version,
              contentJson: jsonEncode({
                'title': title,
                'document': documentJson,
              }),
              createdAt: stamp,
            ),
          );
      await _trimRevisions(diagram.id);
    });
    return (await byId(diagram.id))!;
  }

  Future<void> softDelete(String id) async {
    final row = await byId(id);
    if (row == null) return;
    await (db.update(db.diagrams)..where((t) => t.id.equals(id))).write(
      DiagramsCompanion(
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
    await (db.update(db.diagrams)..where((t) => t.id.equals(id))).write(
      DiagramsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    await db.transaction(() async {
      await (db.delete(db.revisions)..where(
            (t) => t.entityType.equals('diagram') & t.entityId.equals(id),
          ))
          .go();
      await (db.delete(db.diagrams)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<Revision>> revisions(String id) =>
      (db.select(db.revisions)
            ..where(
              (t) => t.entityType.equals('diagram') & t.entityId.equals(id),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.version)]))
          .get();

  Future<void> _trimRevisions(String id, {int keep = 50}) async {
    final rows = await revisions(id);
    for (final stale in rows.skip(keep)) {
      await (db.delete(db.revisions)..where((t) => t.id.equals(stale.id))).go();
    }
  }
}
