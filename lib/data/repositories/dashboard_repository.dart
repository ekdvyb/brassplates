import '../db/database.dart';
import '../models/enums.dart';

class DashboardStats {
  const DashboardStats({
    required this.notes,
    required this.openTasks,
    required this.doneTasks,
    required this.pictures,
  });

  final int notes;
  final int openTasks;
  final int doneTasks;
  final int pictures;
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
    final openTasks = await _count(
      "SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status != '${TaskStatus.done.name}'",
    );
    final doneTasks = await _count(
      "SELECT COUNT(*) FROM tasks WHERE deleted_at IS NULL AND status = '${TaskStatus.done.name}'",
    );
    final pictures = await _count(
      'SELECT COUNT(*) FROM attachments WHERE deleted_at IS NULL',
    );
    return DashboardStats(
      notes: notes,
      openTasks: openTasks,
      doneTasks: doneTasks,
      pictures: pictures,
    );
  }
}
