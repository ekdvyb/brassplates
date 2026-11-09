import 'dart:io';

import 'package:drift/drift.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

/// Pictures that belong to a note. Files are copied into the app's data
/// directory so the note keeps its picture even if the original is moved.
class AttachmentsRepository extends RepositoryBase {
  AttachmentsRepository(super.db, super.deviceId);

  Stream<List<Attachment>> watchFor(String entityType, String entityId) {
    return (db.select(db.attachments)
          ..where(
            (t) =>
                t.entityType.equals(entityType) &
                t.entityId.equals(entityId) &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .watch();
  }

  Future<List<Attachment>> listFor(String entityType, String entityId) {
    return (db.select(db.attachments)
          ..where(
            (t) =>
                t.entityType.equals(entityType) &
                t.entityId.equals(entityId) &
                t.deletedAt.isNull(),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<Directory> directory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Attachment> addFile({
    required String entityType,
    required String entityId,
    required String sourcePath,
    String? mimeType,
  }) async {
    final dir = await directory();
    final id = const Uuid().v4();
    final extension = p.extension(sourcePath);
    final target = File(p.join(dir.path, '$id$extension'));
    await File(sourcePath).copy(target.path);
    final size = await target.length();
    final stamp = now;
    final row = Attachment(
      id: id,
      entityType: entityType,
      entityId: entityId,
      fileName: p.basename(sourcePath),
      mimeType:
          mimeType ??
          lookupMimeType(sourcePath, headerBytes: null) ??
          'application/octet-stream',
      localPath: target.path,
      bytes: size,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.attachments).insert(row);
    return row;
  }

  Future<void> delete(Attachment attachment) async {
    await (db.delete(
      db.attachments,
    )..where((t) => t.id.equals(attachment.id))).go();
    try {
      final file = File(attachment.localPath);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // The database row is gone; an orphaned file is harmless.
    }
  }

  Future<void> deleteForEntity(String entityType, String entityId) async {
    final rows = await listFor(entityType, entityId);
    for (final row in rows) {
      await delete(row);
    }
  }
}
