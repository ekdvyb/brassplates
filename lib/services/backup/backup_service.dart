import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils.dart';
import '../../data/db/database.dart';
import '../crypto/crypto_service.dart';
import '../crypto/vault_service.dart';
import '../snapshot/snapshot_service.dart';

class BackupService {
  BackupService({
    required this.db,
    required this.vault,
    required this.snapshots,
    CryptoService? crypto,
  }) : _crypto = crypto ?? CryptoService();

  final AppDatabase db;
  final VaultService vault;
  final SnapshotService snapshots;
  final CryptoService _crypto;

  static const tables = <String>[
    'folders',
    'tags',
    'notes',
    'tasks',
    'diagrams',
    'revisions',
    'attachments',
    'settings',
  ];

  Future<Map<String, dynamic>> _dump() async {
    final data = <String, dynamic>{};
    for (final table in tables) {
      final rows = await db.customSelect('SELECT * FROM "$table"').get();
      data[table] = rows.map((r) => r.data).toList();
    }
    final attachmentsDir = await _attachmentsDir();
    final attachments = <Map<String, dynamic>>[];
    if (await attachmentsDir.exists()) {
      await for (final entity in attachmentsDir.list()) {
        if (entity is! File) continue;
        attachments.add({
          'name': p.basename(entity.path),
          'bytes': b64(await entity.readAsBytes()),
        });
      }
    }
    return {
      'format': 'brassplates-backup',
      'formatVersion': 2,
      'appVersion': '1.1.0',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'tables': data,
      'files': attachments,
    };
  }

  Future<File> export({bool encrypt = false, String? password}) async {
    final payload = jsonEncode(await _dump());
    String fileName;
    List<int> contents;
    if (encrypt) {
      final salt = password != null ? randomBytes(16) : null;
      final key = password != null
          ? await _crypto.deriveKey(password, salt!)
          : await vault.dataKeyForBackup();
      final envelope = await _crypto.encryptString(payload, key);
      contents = utf8.encode(
        jsonEncode({
          'format': 'brassplates-encrypted-backup',
          'formatVersion': 1,
          'salt': salt == null ? null : b64(salt),
          'envelope': envelope,
        }),
      );
      fileName = 'brassplates-backup-encrypted.bpbackup';
    } else {
      contents = utf8.encode(payload);
      fileName = 'brassplates-backup.bpbackup';
    }

    final archive = Archive()
      ..addFile(ArchiveFile(fileName, contents.length, contents));
    final zipBytes = ZipEncoder().encode(archive);
    final dir = await getApplicationDocumentsDirectory();
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final out = File(p.join(dir.path, 'brassplates-backup-$stamp.zip'));
    await out.writeAsBytes(zipBytes, flush: true);
    return out;
  }

  Future<List<int>> exportBytes({bool encrypt = false}) async {
    final payload = jsonEncode(await _dump());
    List<int> contents;
    if (encrypt) {
      final key = await vault.dataKeyForBackup();
      final envelope = await _crypto.encryptString(payload, key);
      contents = utf8.encode(
        jsonEncode({
          'format': 'brassplates-encrypted-backup',
          'formatVersion': 1,
          'envelope': envelope,
        }),
      );
    } else {
      contents = utf8.encode(payload);
    }
    final archive = Archive()
      ..addFile(ArchiveFile('backup.bpbackup', contents.length, contents));
    return ZipEncoder().encode(archive);
  }

  Future<int> import(File file, {bool merge = true, String? password}) async {
    final bytes = await file.readAsBytes();
    return importBytes(bytes, merge: merge, password: password);
  }

  Future<int> importBytes(
    List<int> zipBytes, {
    bool merge = true,
    String? password,
  }) async {
    await snapshots.create('before-import');
    final archive = ZipDecoder().decodeBytes(zipBytes);
    final entry = archive.files.firstWhere((f) => f.isFile);
    final raw = utf8.decode(entry.content as List<int>);
    final outer = jsonDecode(raw) as Map<String, dynamic>;
    Map<String, dynamic> data;
    if (outer['format'] == 'brassplates-encrypted-backup') {
      final envelope = (outer['envelope'] as Map).cast<String, dynamic>();
      dynamic key;
      if (outer['salt'] != null) {
        if (password == null) {
          throw StateError('This backup is password protected.');
        }
        key = await _crypto.deriveKey(password, unb64(outer['salt'] as String));
      } else {
        key = await vault.dataKeyForBackup();
      }
      data = jsonDecode(
        await _crypto.decryptString(envelope, key),
      ) as Map<String, dynamic>;
    } else {
      data = outer;
    }

    final tableData = data['tables'] as Map<String, dynamic>? ?? {};
    var imported = 0;
    if (!merge) {
      for (final table in tables) {
        await db.customStatement('DELETE FROM "$table"');
      }
    }
    for (final table in tables) {
      final rows = (tableData[table] as List?) ?? const [];
      for (final row in rows) {
        final map = (row as Map).cast<String, dynamic>();
        if (merge && table != 'settings') {
          final existing = await db
              .customSelect(
                'SELECT updated_at FROM "$table" WHERE id = ?',
                variables: [Variable<String>(map['id'].toString())],
              )
              .getSingleOrNull();
          if (existing != null) {
            final local = existing.data['updated_at'] as int? ?? 0;
            final incoming = map['updated_at'] as int? ?? 0;
            if (local > incoming) continue;
          }
        }
        await _insertRow(table, map);
        imported++;
      }
    }

    final files = (data['files'] as List?) ?? const [];
    final dir = await _attachmentsDir();
    await dir.create(recursive: true);
    for (final file in files) {
      final map = (file as Map).cast<String, dynamic>();
      final name = map['name'] as String;
      final target = File(p.join(dir.path, name));
      await target.writeAsBytes(unb64(map['bytes'] as String));
      // The backup stores the picture next to its attachment id, but the old
      // absolute path belongs to the other device. Repoint it here.
      final attachmentId = p.basenameWithoutExtension(name);
      await db.customStatement(
        'UPDATE attachments SET local_path = ? WHERE id = ?',
        [target.path, attachmentId],
      );
    }
    return imported;
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

  Future<Directory> _attachmentsDir() async {
    final support = await getApplicationSupportDirectory();
    return Directory(p.join(support.path, 'attachments'));
  }
}
