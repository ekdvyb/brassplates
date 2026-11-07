import '../db/database.dart';
import '../models/enums.dart';

class DashboardStats {
  const DashboardStats({
    required this.notes,
    required this.howTos,
    required this.openTasks,
    required this.serversOnline,
    required this.serversTotal,
    required this.diagrams,
  });

  final int notes;
  final int howTos;
  final int openTasks;
  final int serversOnline;
  final int serversTotal;
  final int diagrams;
}

class DashboardRepository {
  DashboardRepository(this.db);

  final AppDatabase db;

  Future<int> _count(String sql) async {
    final row = await db.customSelect(sql).getSingle();
    return row.data.values.first as int? ?? 0;
  }

  Future<DashboardStats> stats() async {
    final notes = await _count(
      'SELECT COUNT(*) FROM notes WHERE deleted_at IS NULL',
    );
    final howTos = await _count(
      'SELECT COUNT(*) FROM how_tos WHERE deleted_at IS NULL',
    );
    final openTasks = await _count(
      "SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status != '${TaskStatus.done.name}'",
    );
    final diagrams = await _count(
      'SELECT COUNT(*) FROM diagrams WHERE deleted_at IS NULL',
    );
    final serversTotal = await _count(
      'SELECT COUNT(*) FROM servers WHERE deleted_at IS NULL',
    );
    final serversOnline = await _count(
      "SELECT COUNT(*) FROM servers WHERE deleted_at IS NULL AND status = '${ServerStatus.online.name}'",
    );
    return DashboardStats(
      notes: notes,
      howTos: howTos,
      openTasks: openTasks,
      serversOnline: serversOnline,
      serversTotal: serversTotal,
      diagrams: diagrams,
    );
  }
}
