import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class LibraryRepository extends RepositoryBase {
  LibraryRepository(super.db, super.deviceId);

  Stream<List<Folder>> watchFolders() =>
      (db.select(db.folders)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Stream<List<Tag>> watchTags() =>
      (db.select(db.tags)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  Stream<List<Stencil>> watchStencils() =>
      (db.select(db.stencils)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Future<List<Stencil>> stencils() =>
      (db.select(db.stencils)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<Folder> createFolder(String name, {String? parentId}) async {
    final stamp = now;
    final row = Folder(
      id: const Uuid().v4(),
      name: name,
      parentId: parentId,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.folders).insert(row);
    return row;
  }

  Future<Tag> createTag(String name, {String color = '#B5883E'}) async {
    final stamp = now;
    final row = Tag(
      id: const Uuid().v4(),
      name: name.startsWith('#') ? name : '#$name',
      color: color,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.tags).insert(row);
    return row;
  }

  Future<Stencil> saveStencil({
    required String title,
    required String shapeJson,
  }) async {
    final stamp = now;
    final row = Stencil(
      id: const Uuid().v4(),
      title: title,
      shapeJson: shapeJson,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.stencils).insert(row);
    return row;
  }

  Future<void> softDeleteStencil(String id) async {
    final row = await (db.select(
      db.stencils,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) return;
    await (db.update(db.stencils)..where((t) => t.id.equals(id))).write(
      StencilsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }
}
