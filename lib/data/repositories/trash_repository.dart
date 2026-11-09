import 'dart:io';

import 'package:drift/drift.dart';

import '../db/database.dart';
import 'base.dart';

class TrashItem {
  const TrashItem({
    required this.id,
    required this.type,
    required this.title,
    required this.deletedAt,
  });

  final String id;
  final String type;
  final String title;
  final DateTime deletedAt;
}

class TrashRepository extends RepositoryBase {
  TrashRepository(super.db, super.deviceId);

  Future<List<TrashItem>> list() async {
    final items = <TrashItem>[];

    for (final row
        in await (db.select(
          db.notes,
        )..where((t) => t.deletedAt.isNotNull())).get()) {
      items.add(
        TrashItem(
          id: row.id,
          type: 'note',
          title: row.title,
          deletedAt: row.deletedAt!,
        ),
      );
    }
    for (final row
        in await (db.select(
          db.tasks,
        )..where((t) => t.deletedAt.isNotNull())).get()) {
      items.add(
        TrashItem(
          id: row.id,
          type: 'task',
          title: row.title,
          deletedAt: row.deletedAt!,
        ),
      );
    }

    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> restore(TrashItem item) async {
    final stamp = DateTime.now();
    switch (item.type) {
      case 'note':
        await (db.update(db.notes)..where((t) => t.id.equals(item.id))).write(
          NotesCompanion(deletedAt: const Value(null), updatedAt: Value(stamp)),
        );
      case 'task':
        await (db.update(db.tasks)..where((t) => t.id.equals(item.id))).write(
          TasksCompanion(deletedAt: const Value(null), updatedAt: Value(stamp)),
        );
    }
  }

  Future<void> deleteForever(TrashItem item) async {
    switch (item.type) {
      case 'note':
        final attachments = await (db.select(db.attachments)..where(
              (t) =>
                  t.entityType.equals('note') & t.entityId.equals(item.id),
            ))
            .get();
        for (final attachment in attachments) {
          try {
            final file = File(attachment.localPath);
            if (await file.exists()) await file.delete();
          } catch (_) {
            // Ignore files that already vanished from disk.
          }
        }
        await (db.delete(db.attachments)..where(
              (t) =>
                  t.entityType.equals('note') & t.entityId.equals(item.id),
            ))
            .go();
        await (db.delete(db.revisions)..where(
              (t) =>
                  t.entityType.equals('note') & t.entityId.equals(item.id),
            ))
            .go();
        await (db.delete(db.notes)..where((t) => t.id.equals(item.id))).go();
      case 'task':
        await (db.delete(db.tasks)..where((t) => t.id.equals(item.id))).go();
    }
  }

  Future<void> emptyTrash() async {
    for (final item in await list()) {
      await deleteForever(item);
    }
  }
}
