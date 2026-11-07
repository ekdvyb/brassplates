import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils.dart';
import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class TasksRepository extends RepositoryBase {
  TasksRepository(super.db, super.deviceId);

  Stream<List<Task>> watchActive() =>
      (db.select(db.tasks)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([
              (t) => OrderingTerm.asc(t.status),
              (t) => OrderingTerm.asc(t.sortOrder),
              (t) => OrderingTerm.desc(t.createdAt),
            ]))
          .watch();

  Future<List<Task>> activeList() =>
      (db.select(db.tasks)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.sortOrder)]))
          .get();

  Future<List<Task>> openTasks() =>
      (db.select(db.tasks)
            ..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.equalsValue(TaskStatus.done).not(),
            )
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .get();

  Future<List<Task>> overdue() {
    final stamp = now;
    return (db.select(db.tasks)
          ..where(
            (t) =>
                t.deletedAt.isNull() &
                t.status.equalsValue(TaskStatus.done).not() &
                t.dueDate.isNotNull() &
                t.dueDate.isSmallerThanValue(stamp),
          )
          ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
        .get();
  }

  Future<Task?> byId(String id) =>
      (db.select(db.tasks)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Task> create({
    required String title,
    String description = '',
    TaskStatus status = TaskStatus.todo,
    TaskPriority priority = TaskPriority.medium,
    DateTime? dueDate,
    DateTime? reminderAt,
    List<Map<String, dynamic>> subtasks = const [],
    String tagsCsv = '',
    String? linkedServerId,
    String? linkedNoteId,
    String? linkedDiagramId,
  }) async {
    final stamp = now;
    final row = Task(
      id: const Uuid().v4(),
      title: title,
      description: description,
      status: status,
      priority: priority,
      dueDate: dueDate,
      reminderAt: reminderAt,
      subtasksJson: jsonEncode(subtasks),
      linkedServerId: linkedServerId,
      linkedNoteId: linkedNoteId,
      linkedDiagramId: linkedDiagramId,
      tagsCsv: tagsCsv,
      sortOrder: stamp.millisecondsSinceEpoch,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.tasks).insert(row);
    return row;
  }

  Future<Task> save(
    Task task, {
    required String title,
    required String description,
    required TaskPriority priority,
    DateTime? dueDate,
    DateTime? reminderAt,
    required List<Map<String, dynamic>> subtasks,
    required String tagsCsv,
    String? linkedServerId,
    String? linkedNoteId,
    String? linkedDiagramId,
  }) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        title: Value(title.trim().isEmpty ? 'Untitled task' : title.trim()),
        description: Value(description),
        priority: Value(priority),
        dueDate: Value(dueDate),
        reminderAt: Value(reminderAt),
        subtasksJson: Value(jsonEncode(subtasks)),
        tagsCsv: Value(tagsCsv),
        linkedServerId: Value(linkedServerId),
        linkedNoteId: Value(linkedNoteId),
        linkedDiagramId: Value(linkedDiagramId),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
    return (await byId(task.id))!;
  }

  Future<void> move(Task task, TaskStatus status, int sortOrder) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        status: Value(status),
        sortOrder: Value(sortOrder),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> toggleSubtask(Task task, int index) async {
    final items = decodeListOfMaps(task.subtasksJson);
    if (index < 0 || index >= items.length) return;
    items[index]['done'] = !(items[index]['done'] as bool? ?? false);
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        subtasksJson: Value(jsonEncode(items)),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> setReminder(Task task, DateTime? reminder) async {
    await (db.update(db.tasks)..where((t) => t.id.equals(task.id))).write(
      TasksCompanion(
        reminderAt: Value(reminder),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> softDelete(String id) async {
    final task = await byId(id);
    if (task == null) return;
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> restore(String id) async {
    final task = await byId(id);
    if (task == null) return;
    await (db.update(db.tasks)..where((t) => t.id.equals(id))).write(
      TasksCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(task.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    await (db.delete(db.tasks)..where((t) => t.id.equals(id))).go();
  }
}
