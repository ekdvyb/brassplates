import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../crypto/crypto_service.dart';
import '../crypto/vault_service.dart';
import '../snapshot/snapshot_service.dart';
import 'conflict_resolver.dart';
import 'sync_provider.dart';

class SyncResult {
  SyncResult({
    required this.startedAt,
    this.finishedAt,
    this.pushed = 0,
    this.pulled = 0,
    this.conflicts = 0,
    this.errors = const [],
  });

  final DateTime startedAt;
  DateTime? finishedAt;
  int pushed;
  int pulled;
  int conflicts;
  List<String> errors;

  bool get ok => errors.isEmpty;
  Duration get duration => (finishedAt ?? DateTime.now()).difference(startedAt);
}

class SyncService {
  SyncService({
    required this.db,
    required this.provider,
    required this.vault,
    required this.snapshots,
    required this.deviceId,
    CryptoService? crypto,
    this._resolver = const ConflictResolver(),
  }) : _crypto = crypto ?? CryptoService();

  final AppDatabase db;
  final SyncProvider provider;
  final VaultService vault;
  final SnapshotService snapshots;
  final String deviceId;
  final CryptoService _crypto;
  final ConflictResolver _resolver;

  static const manifestPath = 'manifest.enc.json';

  static const entityTables = <String>[
    'folders',
    'tags',
    'notes',
    'tasks',
    'diagrams',
    'attachments',
  ];

  Future<String> _encrypt(String clear) async {
    final key = await vault.dataKeyForBackup();
    final envelope = await _crypto.encryptString(clear, key);
    return jsonEncode(envelope);
  }

  Future<String> _decrypt(String encoded) async {
    final key = await vault.dataKeyForBackup();
    return _crypto.decryptString(
      jsonDecode(encoded) as Map<String, dynamic>,
      key,
    );
  }

  Future<List<Map<String, dynamic>>> _rows(String table) async {
    final result = await db.customSelect('SELECT * FROM "$table"').get();
    return result.map((r) => Map<String, dynamic>.from(r.data)).toList();
  }

  String _rowId(Map<String, dynamic> row) => row['id'].toString();

  DateTime _rowUpdated(Map<String, dynamic> row) {
    final value = row['updated_at'];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    return DateTime.tryParse(value?.toString() ?? '') ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  /// Content hash. Fields that legitimately differ per device are ignored.
  String _hash(Map<String, dynamic> row) {
    final keys = row.keys
        .where(
          (key) =>
              key != 'local_path' && key != 'device_id' && key != 'sync_status',
        )
        .toList()
      ..sort();
    final canonical = {for (final key in keys) key: row[key]};
    return sha256.convert(utf8.encode(jsonEncode(canonical))).toString();
  }

  bool _deleted(Map<String, dynamic> row) => row['deleted_at'] != null;

  String _titleColumn(String table) =>
      (table == 'folders' || table == 'tags' || table == 'attachments')
      ? 'name'
      : 'title';

  Future<Map<String, dynamic>> _buildManifest() async {
    final entries = <String, dynamic>{};
    for (final table in entityTables) {
      final rows = await _rows(table);
      for (final row in rows) {
        final key = '$table/${_rowId(row)}';
        entries[key] = SyncMeta(
          version: (row['version'] as num?)?.toInt() ?? 1,
          updatedAt: _rowUpdated(row),
          hash: _hash(row),
          deleted: _deleted(row),
          pending: row['sync_status'] == 'pending',
        ).toJson();
      }
    }
    return {
      'version': 1,
      'deviceId': deviceId,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
      'entries': entries,
    };
  }

  Future<Map<String, dynamic>?> _readRemoteManifest() async {
    final bytes = await provider.readBytes(manifestPath);
    if (bytes == null) return null;
    final clear = await _decrypt(utf8.decode(bytes));
    return jsonDecode(clear) as Map<String, dynamic>;
  }

  Future<void> _writeRemoteManifest(Map<String, dynamic> manifest) async {
    final encrypted = await _encrypt(jsonEncode(manifest));
    await provider.writeBytes(manifestPath, utf8.encode(encrypted));
  }

  Future<void> _upload(String table, Map<String, dynamic> row) async {
    final key = await vault.dataKeyForBackup();
    final payload = utf8.encode(jsonEncode({'table': table, 'data': row}));
    final encrypted = await _crypto.encryptBytes(payload, key);
    await provider.writeBytes('$table/${_rowId(row)}.bpv', encrypted);
    if (table == 'attachments') {
      await _uploadAttachmentFile(row, key);
    }
  }

  Future<Map<String, dynamic>?> _download(String table, String id) async {
    final bytes = await provider.readBytes('$table/$id.bpv');
    if (bytes == null) return null;
    final key = await vault.dataKeyForBackup();
    final clear = await _crypto.decryptBytes(bytes, key);
    final decoded = jsonDecode(utf8.decode(clear)) as Map<String, dynamic>;
    final row = Map<String, dynamic>.from(decoded['data'] as Map);
    if (table == 'attachments') {
      await _downloadAttachmentFile(id, row, key);
    }
    return row;
  }

  Future<void> _uploadAttachmentFile(
    Map<String, dynamic> row,
    SecretKey key,
  ) async {
    try {
      final path = row['local_path'] as String?;
      if (path == null || path.isEmpty) return;
      final file = File(path);
      if (!await file.exists()) return;
      final encrypted = await _crypto.encryptBytes(
        await file.readAsBytes(),
        key,
      );
      await provider.writeBytes('files/${_rowId(row)}.bpv', encrypted);
    } catch (_) {
      // A missing picture should not abort the whole sync.
    }
  }

  Future<void> _downloadAttachmentFile(
    String id,
    Map<String, dynamic> row,
    SecretKey key,
  ) async {
    final bytes = await provider.readBytes('files/$id.bpv');
    if (bytes == null) return;
    final dir = await _attachmentDir();
    final fileName = (row['file_name'] as String?) ?? 'picture';
    final extension = p.extension(fileName);
    final target = File(p.join(dir.path, '$id$extension'));
    final clear = await _crypto.decryptBytes(bytes, key);
    await target.writeAsBytes(clear, flush: true);
    row['local_path'] = target.path;
  }

  Future<Directory> _attachmentDir() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'attachments'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<void> _insertRow(String table, Map<String, dynamic> row) async {
    if (row.isEmpty) return;
    final columns = row.keys.toList();
    final quoted = columns.map((c) => '"$c"').join(', ');
    final placeholders = List.filled(columns.length, '?').join(', ');
    await db.customStatement(
      'INSERT OR REPLACE INTO "$table" ($quoted) VALUES ($placeholders)',
      row.values.toList(),
    );
  }

  Future<void> _markSynced(String table, Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final quoted = ids.map((id) => "'${id.replaceAll("'", "''")}'").join(', ');
    await db.customStatement(
      'UPDATE "$table" SET sync_status = \'synced\' WHERE id IN ($quoted)',
    );
  }

  Future<void> _createConflictCopy(
    String table,
    Map<String, dynamic> row,
  ) async {
    final copy = Map<String, dynamic>.from(row);
    copy['id'] = const Uuid().v4();
    copy['version'] = ((row['version'] as num?)?.toInt() ?? 1) + 1;
    copy['updated_at'] = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
    copy['sync_status'] = 'pending';
    final titleColumn = _titleColumn(table);
    final original = row[titleColumn]?.toString() ?? 'Untitled';
    final stamp = DateTime.now().toUtc().toIso8601String().split('T').first;
    copy[titleColumn] = 'Conflict - $stamp - $original';
    if (table == 'attachments') {
      final source = row['local_path'] as String?;
      if (source != null) {
        final dir = await _attachmentDir();
        final extension = p.extension(source);
        final target = File(p.join(dir.path, '${copy['id']}$extension'));
        try {
          await File(source).copy(target.path);
          copy['local_path'] = target.path;
        } catch (_) {}
      }
    }
    await _insertRow(table, copy);
  }

  Future<SyncResult> sync() async {
    final result = SyncResult(startedAt: DateTime.now());
    final touched = <String, Set<String>>{};
    try {
      await snapshots.create('before-sync');
      await provider.ensureDir('.');
      final remote = await _readRemoteManifest();
      final remoteEntries =
          (remote?['entries'] as Map?)?.cast<String, dynamic>() ?? {};

      for (final table in entityTables) {
        final localRows = await _rows(table);
        final localById = {for (final row in localRows) _rowId(row): row};
        touched[table] = <String>{};

        for (final row in localRows) {
          final id = _rowId(row);
          final key = '$table/$id';
          final localMeta = SyncMeta(
            version: (row['version'] as num?)?.toInt() ?? 1,
            updatedAt: _rowUpdated(row),
            hash: _hash(row),
            deleted: _deleted(row),
            pending: row['sync_status'] == 'pending',
          );
          final remoteMeta = remoteEntries[key] is Map
              ? SyncMeta.fromJson(
                  (remoteEntries[key] as Map).cast<String, dynamic>(),
                )
              : null;

          switch (_resolver.decide(local: localMeta, remote: remoteMeta)) {
            case SyncAction.none:
              touched[table]!.add(id);
              break;
            case SyncAction.push:
              await _upload(table, row);
              touched[table]!.add(id);
              result.pushed++;
              break;
            case SyncAction.pull:
              final pulled = await _download(table, id);
              if (pulled != null) {
                await _insertRow(table, pulled);
                touched[table]!.add(id);
                result.pulled++;
              }
              break;
            case SyncAction.conflict:
              await _createConflictCopy(table, row);
              final pulled = await _download(table, id);
              if (pulled != null) {
                await _insertRow(table, pulled);
                result.pulled++;
              }
              result.conflicts++;
              touched[table]!.add(id);
              break;
          }
        }

        for (final entry in remoteEntries.entries) {
          if (!entry.key.startsWith('$table/')) continue;
          final id = entry.key.split('/').last;
          if (localById.containsKey(id)) continue;
          final pulled = await _download(table, id);
          if (pulled != null) {
            await _insertRow(table, pulled);
            result.pulled++;
            touched[table]!.add(id);
          }
        }

        await _markSynced(table, touched[table]!);
      }

      final finalManifest = await _buildManifest();
      await _writeRemoteManifest(finalManifest);
      result.finishedAt = DateTime.now();
      await _log(
        'sync',
        'info',
        'Sync complete: ${result.pushed} pushed, ${result.pulled} pulled, ${result.conflicts} conflicts',
      );
    } catch (error) {
      result.errors = [error.toString()];
      result.finishedAt = DateTime.now();
      await _log('sync', 'error', 'Sync failed: $error');
    }
    return result;
  }

  Future<void> _log(String providerName, String level, String message) async {
    await db
        .into(db.syncLogs)
        .insert(
          SyncLogsCompanion.insert(
            id: newId(),
            provider: Value(providerName),
            level: Value(level),
            message: message,
            createdAt: DateTime.now(),
          ),
        );
  }
}
