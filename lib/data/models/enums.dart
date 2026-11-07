/// Shared enums used by BRASSPLATES.
enum SyncState { synced, pending, conflict }

enum TaskStatus { todo, doing, done }

enum TaskPriority { high, medium, low }

enum ProjectStatus { planned, active, onHold, done }

enum ServerPurpose { fdms, trading, other }

enum ServerStatus { online, offline, unknown }

enum HowToDifficulty { easy, medium, hard }

enum DiagramShapeType {
  rectangle,
  ellipse,
  diamond,
  text,
  sticky,
  arrow,
  line,
  freehand,
  image,
  server,
  database,
  sqlServer,
  firewall,
  cloud,
  router,
  networkSwitch,
  loadBalancer,
  user,
  laptop,
  phone,
  nextcloud,
  storage,
  terminator,
  process,
  document,
  inputOutput,
  subprocess,
  note,
}

enum ConnectorKind { straight, elbow, curve }

enum SyncProviderKind { none, webdav, nextcloud, googleDrive, localFolder }

extension TaskPriorityX on TaskPriority {
  String get label => switch (this) {
    TaskPriority.high => 'High',
    TaskPriority.medium => 'Medium',
    TaskPriority.low => 'Low',
  };
}

extension TaskStatusX on TaskStatus {
  String get label => switch (this) {
    TaskStatus.todo => 'To Do',
    TaskStatus.doing => 'Doing',
    TaskStatus.done => 'Done',
  };
}

extension ServerPurposeX on ServerPurpose {
  String get label => switch (this) {
    ServerPurpose.fdms => 'FDMS',
    ServerPurpose.trading => 'Trading',
    ServerPurpose.other => 'Other',
  };
}

extension ServerStatusX on ServerStatus {
  String get label => switch (this) {
    ServerStatus.online => 'Online',
    ServerStatus.offline => 'Offline',
    ServerStatus.unknown => 'Unknown',
  };
}

extension HowToDifficultyX on HowToDifficulty {
  String get label => switch (this) {
    HowToDifficulty.easy => 'Easy',
    HowToDifficulty.medium => 'Medium',
    HowToDifficulty.hard => 'Hard',
  };
}

String enumName(Object value) => value.toString().split('.').last;
