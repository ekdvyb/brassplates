import '../db/database.dart';

abstract class RepositoryBase {
  RepositoryBase(this.db, this.deviceId);

  final AppDatabase db;
  final String deviceId;

  DateTime get now => DateTime.now();
}
