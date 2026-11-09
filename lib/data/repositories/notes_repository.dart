import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils.dart';
import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class NotesRepository extends RepositoryBase {
  NotesRepository(super.db, super.deviceId);

  Stream<List<Note>> watchActive({
    String? folderId,
    bool pinnedOnly = false,
    String? tag,
  }) {
    final query = db.select(db.notes)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([
        (t) => OrderingTerm.desc(t.pinned),
        (t) => OrderingTerm.desc(t.updatedAt),
      ]);
    if (folderId != null) {
      query.where((t) => t.folderId.equals(folderId));
    }
    if (pinnedOnly) {
      query.where((t) => t.pinned.equals(true));
    }
    if (tag != null && tag.trim().isNotEmpty) {
      query.where((t) => t.tagsCsv.contains(tag.trim()));
    }
    return query.watch();
  }

  Future<List<Note>> activeList() =>
      (db.select(db.notes)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<List<Note>> recent({int limit = 6}) =>
      (db.select(db.notes)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();

  Future<List<Note>> pinned({int limit = 6}) =>
      (db.select(db.notes)
            ..where((t) => t.deletedAt.isNull() & t.pinned.equals(true))
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();

  Future<Note?> byId(String id) =>
      (db.select(db.notes)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Note> create({
    String title = 'Untitled note',
    String contentDelta = '',
    String plainText = '',
    String tagsCsv = '',
    String? folderId,
  }) async {
    final stamp = now;
    final note = Note(
      id: const Uuid().v4(),
      title: title.trim().isEmpty ? 'Untitled note' : title.trim(),
      contentDelta: contentDelta,
      plainText: plainText,
      folderId: folderId,
      pinned: false,
      tagsCsv: tagsCsv,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.notes).insert(note);
    return note;
  }

  Future<Note> save(
    Note note, {
    required String title,
    required String contentDelta,
    required String plainText,
    String? tagsCsv,
    String? folderId,
  }) async {
    final nextVersion = note.version + 1;
    final stamp = now;
    await db.transaction(() async {
      await (db.update(db.notes)..where((t) => t.id.equals(note.id))).write(
        NotesCompanion(
          title: Value(title.trim().isEmpty ? 'Untitled note' : title.trim()),
          contentDelta: Value(contentDelta),
          plainText: Value(plainText),
          tagsCsv: tagsCsv == null ? const Value.absent() : Value(tagsCsv),
          folderId: folderId == null ? const Value.absent() : Value(folderId),
          updatedAt: Value(stamp),
          version: Value(nextVersion),
          syncStatus: const Value(SyncState.pending),
        ),
      );
      await db
          .into(db.revisions)
          .insert(
            Revision(
              id: const Uuid().v4(),
              entityType: 'note',
              entityId: note.id,
              version: nextVersion,
              contentJson: jsonEncode({
                'title': title,
                'delta': contentDelta,
                'plainText': plainText,
                'tagsCsv': tagsCsv ?? note.tagsCsv,
              }),
              createdAt: stamp,
            ),
          );
      await _trimRevisions('note', note.id);
    });
    return (await byId(note.id))!;
  }

  Future<void> togglePin(Note note) async {
    await (db.update(db.notes)..where((t) => t.id.equals(note.id))).write(
      NotesCompanion(
        pinned: Value(!note.pinned),
        updatedAt: Value(now),
        version: Value(note.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final note = await byId(id);
    if (note == null) return;
    await (db.update(db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(note.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> restore(String id) async {
    final note = await byId(id);
    if (note == null) return;
    await (db.update(db.notes)..where((t) => t.id.equals(id))).write(
      NotesCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(note.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    await db.transaction(() async {
      await (db.delete(db.revisions)
            ..where((t) => t.entityType.equals('note') & t.entityId.equals(id)))
          .go();
      await (db.delete(db.attachments)
            ..where((t) => t.entityType.equals('note') & t.entityId.equals(id)))
          .go();
      await (db.delete(db.notes)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<List<Revision>> revisions(String noteId) =>
      (db.select(db.revisions)
            ..where(
              (t) => t.entityType.equals('note') & t.entityId.equals(noteId),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.version)])
            ..limit(50))
          .get();

  Future<void> restoreRevision(String noteId, Revision revision) async {
    final note = await byId(noteId);
    if (note == null) return;
    final data = decodeMap(revision.contentJson);
    await save(
      note,
      title: data['title'] as String? ?? note.title,
      contentDelta: data['delta'] as String? ?? note.contentDelta,
      plainText: data['plainText'] as String? ?? note.plainText,
      tagsCsv: data['tagsCsv'] as String? ?? note.tagsCsv,
    );
  }

  Future<void> _trimRevisions(
    String entityType,
    String entityId, {
    int keep = 50,
  }) async {
    final rows =
        await (db.select(db.revisions)
              ..where(
                (t) =>
                    t.entityType.equals(entityType) &
                    t.entityId.equals(entityId),
              )
              ..orderBy([(t) => OrderingTerm.desc(t.version)]))
            .get();
    for (final stale in rows.skip(keep)) {
      await (db.delete(db.revisions)..where((t) => t.id.equals(stale.id))).go();
    }
  }
}
