/// Shared enums used by BRASSPLATES.
enum SyncState { synced, pending, conflict }

enum TaskStatus { todo, doing, done }

enum TaskPriority { high, medium, low }

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

enum SyncProviderKind { none, localFolder }

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

String enumName(Object value) => value.toString().split('.').last;
