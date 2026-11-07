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
    Future<void> collect<T>(
      String type,
      Future<List<T>> Function() fetch,
      String Function(T) id,
      String Function(T) title,
      DateTime? Function(T) deleted,
    ) async {
      for (final row in await fetch()) {
        final when = deleted(row);
        if (when != null) {
          items.add(
            TrashItem(
              id: id(row),
              type: type,
              title: title(row),
              deletedAt: when,
            ),
          );
        }
      }
    }

    await collect<Note>(
      'note',
      () => (db.select(db.notes)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );
    await collect<HowTo>(
      'howto',
      () => (db.select(db.howTos)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );
    await collect<Task>(
      'task',
      () => (db.select(db.tasks)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );
    await collect<Project>(
      'project',
      () =>
          (db.select(db.projects)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );
    await collect<ServerEntry>(
      'server',
      () =>
          (db.select(db.servers)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.name,
      (r) => r.deletedAt,
    );
    await collect<Diagram>(
      'diagram',
      () =>
          (db.select(db.diagrams)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );
    await collect<Stencil>(
      'stencil',
      () =>
          (db.select(db.stencils)..where((t) => t.deletedAt.isNotNull())).get(),
      (r) => r.id,
      (r) => r.title,
      (r) => r.deletedAt,
    );

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
      case 'howto':
        await (db.update(db.howTos)..where((t) => t.id.equals(item.id))).write(
          HowTosCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(stamp),
          ),
        );
      case 'task':
        await (db.update(db.tasks)..where((t) => t.id.equals(item.id))).write(
          TasksCompanion(deletedAt: const Value(null), updatedAt: Value(stamp)),
        );
      case 'project':
        await (db.update(
          db.projects,
        )..where((t) => t.id.equals(item.id))).write(
          ProjectsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(stamp),
          ),
        );
      case 'server':
        await (db.update(db.servers)..where((t) => t.id.equals(item.id))).write(
          ServersCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(stamp),
          ),
        );
      case 'diagram':
        await (db.update(
          db.diagrams,
        )..where((t) => t.id.equals(item.id))).write(
          DiagramsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(stamp),
          ),
        );
      case 'stencil':
        await (db.update(
          db.stencils,
        )..where((t) => t.id.equals(item.id))).write(
          StencilsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(stamp),
          ),
        );
    }
  }

  Future<void> deleteForever(TrashItem item) async {
    switch (item.type) {
      case 'note':
        await (db.delete(db.notes)..where((t) => t.id.equals(item.id))).go();
      case 'howto':
        await (db.delete(db.howTos)..where((t) => t.id.equals(item.id))).go();
      case 'task':
        await (db.delete(db.tasks)..where((t) => t.id.equals(item.id))).go();
      case 'project':
        await (db.delete(db.projects)..where((t) => t.id.equals(item.id))).go();
      case 'server':
        await (db.delete(db.servers)..where((t) => t.id.equals(item.id))).go();
      case 'diagram':
        await (db.delete(db.diagrams)..where((t) => t.id.equals(item.id))).go();
      case 'stencil':
        await (db.delete(db.stencils)..where((t) => t.id.equals(item.id))).go();
    }
  }

  Future<void> emptyTrash() async {
    for (final item in await list()) {
      await deleteForever(item);
    }
  }
}
