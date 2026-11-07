import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/enums.dart';

part 'database.g.dart';

class Folders extends Table {
  @override
  String get tableName => 'folders';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get parentId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Tag')
class Tags extends Table {
  @override
  String get tableName => 'tags';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get color => text().withDefault(const Constant('#B5883E'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Note')
class Notes extends Table {
  @override
  String get tableName => 'notes';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title => text().withDefault(const Constant('Untitled note'))();
  TextColumn get contentDelta => text().withDefault(const Constant(''))();
  TextColumn get plainText => text().withDefault(const Constant(''))();
  TextColumn get folderId => text().nullable()();
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  TextColumn get tagsCsv => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('HowTo')
class HowTos extends Table {
  @override
  String get tableName => 'how_tos';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get category => text().withDefault(const Constant('Servers'))();
  TextColumn get difficulty => textEnum<HowToDifficulty>().withDefault(
    Constant(HowToDifficulty.easy.name),
  )();
  TextColumn get stepsJson => text().withDefault(const Constant('[]'))();
  TextColumn get tagsCsv => text().withDefault(const Constant(''))();
  DateTimeColumn get lastTested => dateTime().nullable()();
  TextColumn get relatedServerIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Task')
class Tasks extends Table {
  @override
  String get tableName => 'tasks';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status =>
      textEnum<TaskStatus>().withDefault(Constant(TaskStatus.todo.name))();
  TextColumn get priority => textEnum<TaskPriority>().withDefault(
    Constant(TaskPriority.medium.name),
  )();
  DateTimeColumn get dueDate => dateTime().nullable()();
  DateTimeColumn get reminderAt => dateTime().nullable()();
  TextColumn get subtasksJson => text().withDefault(const Constant('[]'))();
  TextColumn get linkedServerId => text().nullable()();
  TextColumn get linkedNoteId => text().nullable()();
  TextColumn get linkedDiagramId => text().nullable()();
  TextColumn get tagsCsv => text().withDefault(const Constant(''))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Project')
class Projects extends Table {
  @override
  String get tableName => 'projects';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get status => textEnum<ProjectStatus>().withDefault(
    Constant(ProjectStatus.active.name),
  )();
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get endDate => dateTime().nullable()();
  IntColumn get progress => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Milestone')
class Milestones extends Table {
  @override
  String get tableName => 'milestones';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get projectId => text()();
  TextColumn get title => text()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  TextColumn get linkedTaskIds => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('ServerEntry')
class Servers extends Table {
  @override
  String get tableName => 'servers';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get ip => text().withDefault(const Constant(''))();
  TextColumn get databaseName => text().withDefault(const Constant(''))();
  TextColumn get purpose => textEnum<ServerPurpose>().withDefault(
    Constant(ServerPurpose.other.name),
  )();
  TextColumn get status => textEnum<ServerStatus>().withDefault(
    Constant(ServerStatus.unknown.name),
  )();
  DateTimeColumn get lastBackup => dateTime().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get hasSecret => boolean().withDefault(const Constant(false))();
  TextColumn get secretCipher => text().nullable()();
  TextColumn get secretNonce => text().nullable()();
  TextColumn get secretMac => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Diagram')
class Diagrams extends Table {
  @override
  String get tableName => 'diagrams';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title =>
      text().withDefault(const Constant('Untitled diagram'))();
  TextColumn get folderId => text().nullable()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();
  TextColumn get documentJson => text().withDefault(const Constant('{}'))();
  TextColumn get thumbnailBase64 => text().nullable()();
  TextColumn get searchText => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Stencil')
class Stencils extends Table {
  @override
  String get tableName => 'stencils';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get shapeJson => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  DateTimeColumn get deletedAt => dateTime().nullable()();
  TextColumn get syncStatus =>
      textEnum<SyncState>().withDefault(Constant(SyncState.pending.name))();
  IntColumn get version => integer().withDefault(const Constant(1))();
  TextColumn get deviceId => text().withDefault(const Constant(''))();
}

@DataClassName('Revision')
class Revisions extends Table {
  @override
  String get tableName => 'revisions';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get version => integer()();
  TextColumn get contentJson => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('Snapshot')
class Snapshots extends Table {
  @override
  String get tableName => 'snapshots';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get path => text()();
  TextColumn get reason => text().withDefault(const Constant('manual'))();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('SyncLog')
class SyncLogs extends Table {
  @override
  String get tableName => 'sync_logs';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get provider => text().withDefault(const Constant('local'))();
  TextColumn get level => text().withDefault(const Constant('info'))();
  TextColumn get message => text()();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('Attachment')
class Attachments extends Table {
  @override
  String get tableName => 'attachments';
  @override
  Set<Column> get primaryKey => {id};

  TextColumn get id => text()();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get fileName => text()();
  TextColumn get mimeType =>
      text().withDefault(const Constant('application/octet-stream'))();
  TextColumn get localPath => text()();
  IntColumn get bytes => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime()();
}

@DataClassName('AppSetting')
class AppSettings extends Table {
  @override
  String get tableName => 'settings';
  @override
  Set<Column> get primaryKey => {key};

  TextColumn get key => text()();
  TextColumn get value => text()();
}

@DriftDatabase(
  tables: [
    Folders,
    Tags,
    Notes,
    HowTos,
    Tasks,
    Projects,
    Milestones,
    Servers,
    Diagrams,
    Stencils,
    Revisions,
    Snapshots,
    SyncLogs,
    Attachments,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createSearchIndex();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
      if (details.wasCreated) {
        await _createSearchIndex();
      }
    },
  );

  Future<void> _createSearchIndex() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS search_fts USING fts5(
        entity_type UNINDEXED,
        entity_id UNINDEXED,
        title,
        body,
        deleted UNINDEXED,
        tokenize = 'unicode61'
      )
    ''');

    Future<void> trigger(
      String name,
      String table,
      String title,
      String body,
    ) async {
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${name}_ai AFTER INSERT ON $table BEGIN
          INSERT INTO search_fts(entity_type, entity_id, title, body, deleted)
          VALUES ('$table', new.id, new.$title, new.$body,
            CASE WHEN new.deleted_at IS NULL THEN 0 ELSE 1 END);
        END
      ''');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${name}_au AFTER UPDATE ON $table BEGIN
          DELETE FROM search_fts WHERE entity_type = '$table' AND entity_id = old.id;
          INSERT INTO search_fts(entity_type, entity_id, title, body, deleted)
          VALUES ('$table', new.id, new.$title, new.$body,
            CASE WHEN new.deleted_at IS NULL THEN 0 ELSE 1 END);
        END
      ''');
      await customStatement('''
        CREATE TRIGGER IF NOT EXISTS ${name}_ad AFTER DELETE ON $table BEGIN
          DELETE FROM search_fts WHERE entity_type = '$table' AND entity_id = old.id;
        END
      ''');
    }

    await trigger('notes', 'notes', 'title', 'plain_text');
    await trigger('how_tos', 'how_tos', 'title', 'steps_json');
    await trigger('tasks', 'tasks', 'title', 'description');
    await trigger('projects', 'projects', 'title', 'description');
    await trigger('servers', 'servers', 'name', 'database_name');
    await trigger('diagrams', 'diagrams', 'title', 'search_text');
  }

  /// Removes tombstones older than [retention] and keeps the database tidy.
  Future<void> purgeExpiredTrash({
    Duration retention = const Duration(days: 30),
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    await (delete(notes)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
    await (delete(howTos)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
    await (delete(tasks)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
    await (delete(projects)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
    await (delete(servers)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
    await (delete(diagrams)..where(
          (t) =>
              t.deletedAt.isNotNull() & t.deletedAt.isSmallerThanValue(cutoff),
        ))
        .go();
  }

  Future<String> integrityCheck() async {
    final rows = await customSelect('PRAGMA integrity_check').get();
    if (rows.isEmpty) return 'ok';
    return rows.first.data.values.first?.toString() ?? 'ok';
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationSupportDirectory();
    final file = File(p.join(dir.path, 'brassplates.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
