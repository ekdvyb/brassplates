import 'package:drift/drift.dart';

import '../../data/db/database.dart';

class SearchHit {
  const SearchHit({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.snippet,
    required this.rank,
  });

  final String entityType;
  final String entityId;
  final String title;
  final String snippet;
  final double rank;

  String get label => switch (entityType) {
    'notes' => 'Note',
    'tasks' => 'Task',
    _ => entityType,
  };
}

class SearchService {
  SearchService(this.db);

  final AppDatabase db;

  Future<List<SearchHit>> search(String rawQuery, {int limit = 50}) async {
    final terms = rawQuery
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9_#@.\-]+'))
        .where((t) => t.trim().isNotEmpty)
        .toList();
    if (terms.isEmpty) return const [];

    final match = terms.map((t) => '"${t.replaceAll('"', '')}"*').join(' OR ');
    try {
      final rows = await db
          .customSelect(
            '''
        SELECT entity_type, entity_id, title,
               snippet(search_fts, 3, '[', ']', '…', 12) AS snippet,
               bm25(search_fts) AS rank
        FROM search_fts
        WHERE search_fts MATCH ? AND deleted = 0
        ORDER BY rank
        LIMIT ?
        ''',
            variables: [Variable<String>(match), Variable<int>(limit)],
          )
          .get();
      return rows
          .map(
            (row) => SearchHit(
              entityType: row.read<String>('entity_type'),
              entityId: row.read<String>('entity_id'),
              title: row.read<String>('title'),
              snippet: row.read<String>('snippet'),
              rank: row.read<double>('rank'),
            ),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> rebuild() async {
    await db.customStatement('DELETE FROM search_fts');
    await db.customStatement('''
      INSERT INTO search_fts(entity_type, entity_id, title, body, deleted)
      SELECT 'notes', id, title, plain_text,
        CASE WHEN deleted_at IS NULL THEN 0 ELSE 1 END FROM notes
    ''');
    await db.customStatement('''
      INSERT INTO search_fts(entity_type, entity_id, title, body, deleted)
      SELECT 'tasks', id, title, description,
        CASE WHEN deleted_at IS NULL THEN 0 ELSE 1 END FROM tasks
    ''');
  }
}
