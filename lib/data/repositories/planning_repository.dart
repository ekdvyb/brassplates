import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import 'base.dart';

class PlanningRepository extends RepositoryBase {
  PlanningRepository(super.db, super.deviceId);

  Stream<List<Project>> watchProjects() =>
      (db.select(db.projects)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .watch();

  Stream<List<Milestone>> watchMilestones(String projectId) =>
      (db.select(db.milestones)
            ..where((t) => t.projectId.equals(projectId) & t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.dueDate)]))
          .watch();

  Future<List<Project>> projectList() =>
      (db.select(db.projects)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
          .get();

  Future<Project?> projectById(String id) =>
      (db.select(db.projects)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<Project> createProject({
    required String title,
    String description = '',
    ProjectStatus status = ProjectStatus.active,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final stamp = now;
    final row = Project(
      id: const Uuid().v4(),
      title: title,
      description: description,
      status: status,
      startDate: startDate,
      endDate: endDate,
      progress: 0,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.projects).insert(row);
    return row;
  }

  Future<void> saveProject(
    Project project, {
    required String title,
    required String description,
    required ProjectStatus status,
    DateTime? startDate,
    DateTime? endDate,
    required int progress,
  }) async {
    await (db.update(db.projects)..where((t) => t.id.equals(project.id))).write(
      ProjectsCompanion(
        title: Value(title),
        description: Value(description),
        status: Value(status),
        startDate: Value(startDate),
        endDate: Value(endDate),
        progress: Value(progress.clamp(0, 100)),
        updatedAt: Value(now),
        version: Value(project.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> softDeleteProject(String id) async {
    final row = await projectById(id);
    if (row == null) return;
    await (db.update(db.projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> restoreProject(String id) async {
    final row = await projectById(id);
    if (row == null) return;
    await (db.update(db.projects)..where((t) => t.id.equals(id))).write(
      ProjectsCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteProjectForever(String id) async {
    await db.transaction(() async {
      await (db.delete(
        db.milestones,
      )..where((t) => t.projectId.equals(id))).go();
      await (db.delete(db.projects)..where((t) => t.id.equals(id))).go();
    });
  }

  Future<Milestone> addMilestone(
    String projectId, {
    required String title,
    DateTime? dueDate,
  }) async {
    final stamp = now;
    final row = Milestone(
      id: const Uuid().v4(),
      projectId: projectId,
      title: title,
      dueDate: dueDate,
      done: false,
      linkedTaskIds: '[]',
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.milestones).insert(row);
    return row;
  }

  Future<void> toggleMilestone(Milestone milestone) async {
    await (db.update(
      db.milestones,
    )..where((t) => t.id.equals(milestone.id))).write(
      MilestonesCompanion(
        done: Value(!milestone.done),
        updatedAt: Value(now),
        version: Value(milestone.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteMilestone(String id) async {
    await (db.delete(db.milestones)..where((t) => t.id.equals(id))).go();
  }
}
