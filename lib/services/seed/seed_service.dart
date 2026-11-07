import 'dart:convert';

import '../../core/constants.dart';
import '../../data/db/database.dart';
import '../../data/models/enums.dart';
import '../../data/repositories/howto_repository.dart';
import '../../data/repositories/diagrams_repository.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/notes_repository.dart';
import '../../data/repositories/planning_repository.dart';
import '../../data/repositories/servers_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../data/repositories/tasks_repository.dart';
import '../../features/diagrams/diagram_templates.dart';

class SeedService {
  SeedService({
    required this.db,
    required this.settings,
    required this.notes,
    required this.howTos,
    required this.tasks,
    required this.planning,
    required this.servers,
    required this.diagrams,
    required this.library,
    required this.deviceId,
  });

  final AppDatabase db;
  final SettingsRepository settings;
  final NotesRepository notes;
  final HowToRepository howTos;
  final TasksRepository tasks;
  final PlanningRepository planning;
  final ServersRepository servers;
  final DiagramsRepository diagrams;
  final LibraryRepository library;
  final String deviceId;

  Future<void> seedIfNeeded() async {
    if (await settings.get('seeded') == 'true') return;
    if ((await notes.activeList()).isNotEmpty) {
      await settings.set('seeded', 'true');
      return;
    }

    for (final tag in defaultTags) {
      await library.createTag(tag);
    }

    final welcomeDelta = jsonEncode({
      'ops': [
        {
          'insert': 'Welcome to BRASSPLATES\n',
          'attributes': {'header': 1},
        },
        {'insert': 'Your local-first, encrypted IT workspace.\n\n'},
        {'insert': 'Everything is stored on this device first. '},
        {
          'insert': 'Nothing is lost',
          'attributes': {'bold': true},
        },
        {'insert': ' when the network is down.\n\n'},
        {
          'insert': 'What you can do here:\n',
          'attributes': {'bold': true},
        },
        {
          'insert': 'Notes with diagrams, How-Tos, Kanban tasks, planning, server inventory and the Diagrams Studio.\n\n',
        },
        {
          'insert': 'Try Ctrl+K',
          'attributes': {'code': true},
        },
        {'insert': ' anywhere to search everything.\n'},
      ],
    });

    await notes.create(
      title: 'Welcome to BRASSPLATES',
      contentDelta: welcomeDelta,
      plainText: 'Welcome to BRASSPLATES. Your local-first, encrypted IT workspace. Everything is stored on this device first. Nothing is lost when the network is down.',
      tagsCsv: '#Servers,#Diagrams',
    );

    await howTos.create(
      title: 'Verify SQL Server backups',
      category: 'SQL',
      difficulty: HowToDifficulty.medium,
      tagsCsv: '#SQL,#FDMS',
      steps: [
        {
          'type': 'text',
          'text': 'Open SQL Server Management Studio and connect to the target instance.',
        },
        {
          'type': 'code',
          'language': 'sql',
          'text': "RESTORE VERIFYONLY FROM DISK = N'D:\\\\Backups\\\\FDMS_PROD.bak';",
        },
        {
          'type': 'text',
          'text':
              'Confirm the output says "The backup set on file 1 is valid."',
        },
      ],
    );

    final project = await planning.createProject(
      title: 'Migrate 29 SQL Servers to Vault',
      description: 'Consolidate credentials, retire hard-coded connection strings and move all 29 servers into Vault with audited access.',
      status: ProjectStatus.active,
      startDate: DateTime.now(),
      endDate: DateTime.now().add(const Duration(days: 45)),
    );
    await planning.addMilestone(
      project.id,
      title: 'Inventory all 29 servers',
      dueDate: DateTime.now().add(const Duration(days: 7)),
    );
    await planning.addMilestone(
      project.id,
      title: 'Pilot Vault on FDMS cluster',
      dueDate: DateTime.now().add(const Duration(days: 21)),
    );
    await planning.addMilestone(
      project.id,
      title: 'Cut over remaining servers',
      dueDate: DateTime.now().add(const Duration(days: 40)),
    );

    for (final row in seedServers) {
      await servers.create(
        name: row[0],
        ip: row[1],
        databaseName: row[2],
        purpose: ServerPurpose.values.firstWhere(
          (p) => p.name == row[3],
          orElse: () => ServerPurpose.other,
        ),
      );
    }

    final doc = templateById('sql-vault');
    await diagrams.create(
      title: doc.title,
      documentJson: doc.toJson(),
      searchText: doc.searchableText,
    );
    final network = templateById('network');
    await diagrams.create(
      title: network.title,
      documentJson: network.toJson(),
      searchText: network.searchableText,
    );

    await tasks.create(
      title: 'Audit hard-coded connection strings',
      description: 'Search all 29 servers for plain-text credentials.',
      priority: TaskPriority.high,
      dueDate: DateTime.now().add(const Duration(days: 3)),
      tagsCsv: '#SQL,#Network',
    );
    await tasks.create(
      title: 'Draft Vault migration runbook',
      description: 'Write the step-by-step rollback plan.',
      status: TaskStatus.doing,
      priority: TaskPriority.medium,
      dueDate: DateTime.now().add(const Duration(days: 10)),
      tagsCsv: '#Servers',
    );
    await tasks.create(
      title: 'Verify FDMS backups',
      priority: TaskPriority.low,
      status: TaskStatus.done,
      tagsCsv: '#FDMS',
    );

    await settings.set('seeded', 'true');
    await settings.set('project.example', project.id);
  }
}
