import 'dart:io';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../db/database.dart';
import '../models/enums.dart';
import '../../services/crypto/vault_service.dart';
import 'base.dart';

class ServersRepository extends RepositoryBase {
  ServersRepository(super.db, super.deviceId, this.vault);

  final VaultService vault;

  Stream<List<ServerEntry>> watchActive({
    ServerPurpose? purpose,
    ServerStatus? status,
    String query = '',
  }) {
    final q = db.select(db.servers)
      ..where((t) => t.deletedAt.isNull())
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    if (purpose != null) {
      q.where((t) => t.purpose.equalsValue(purpose));
    }
    if (status != null) {
      q.where((t) => t.status.equalsValue(status));
    }
    if (query.trim().isNotEmpty) {
      final needle = '%${query.trim()}%';
      q.where(
        (t) =>
            t.name.like(needle) |
            t.ip.like(needle) |
            t.databaseName.like(needle),
      );
    }
    return q.watch();
  }

  Future<List<ServerEntry>> activeList() =>
      (db.select(db.servers)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .get();

  Future<ServerEntry?> byId(String id) =>
      (db.select(db.servers)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<ServerEntry> create({
    required String name,
    String ip = '',
    String databaseName = '',
    ServerPurpose purpose = ServerPurpose.other,
    ServerStatus status = ServerStatus.unknown,
    DateTime? lastBackup,
    String notes = '',
    String? secret,
  }) async {
    SecretEnvelope? envelope;
    if (secret != null && secret.isNotEmpty) {
      envelope = await vault.encryptSecret(secret);
    }
    final stamp = now;
    final row = ServerEntry(
      id: const Uuid().v4(),
      name: name,
      ip: ip,
      databaseName: databaseName,
      purpose: purpose,
      status: status,
      lastBackup: lastBackup,
      notes: notes,
      hasSecret: envelope != null,
      secretCipher: envelope?.cipher,
      secretNonce: envelope?.nonce,
      secretMac: envelope?.mac,
      createdAt: stamp,
      updatedAt: stamp,
      deletedAt: null,
      syncStatus: SyncState.pending,
      version: 1,
      deviceId: deviceId,
    );
    await db.into(db.servers).insert(row);
    return row;
  }

  Future<ServerEntry> save(
    ServerEntry server, {
    required String name,
    required String ip,
    required String databaseName,
    required ServerPurpose purpose,
    required ServerStatus status,
    DateTime? lastBackup,
    required String notes,
    String? newSecret,
  }) async {
    SecretEnvelope? envelope;
    if (newSecret != null && newSecret.isNotEmpty) {
      envelope = await vault.encryptSecret(newSecret);
    }
    await (db.update(db.servers)..where((t) => t.id.equals(server.id))).write(
      ServersCompanion(
        name: Value(name),
        ip: Value(ip),
        databaseName: Value(databaseName),
        purpose: Value(purpose),
        status: Value(status),
        lastBackup: Value(lastBackup),
        notes: Value(notes),
        hasSecret: envelope == null ? const Value.absent() : const Value(true),
        secretCipher: envelope == null
            ? const Value.absent()
            : Value(envelope.cipher),
        secretNonce: envelope == null
            ? const Value.absent()
            : Value(envelope.nonce),
        secretMac: envelope == null
            ? const Value.absent()
            : Value(envelope.mac),
        updatedAt: Value(now),
        version: Value(server.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
    return (await byId(server.id))!;
  }

  Future<void> clearSecret(ServerEntry server) async {
    await (db.update(db.servers)..where((t) => t.id.equals(server.id))).write(
      ServersCompanion(
        hasSecret: const Value(false),
        secretCipher: const Value(null),
        secretNonce: const Value(null),
        secretMac: const Value(null),
        updatedAt: Value(now),
        version: Value(server.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<String> revealSecret(ServerEntry server) async {
    if (!server.hasSecret ||
        server.secretCipher == null ||
        server.secretNonce == null ||
        server.secretMac == null) {
      throw StateError('No secret stored for this server.');
    }
    return vault.decryptSecret(
      SecretEnvelope.fromColumns(
        server.secretCipher!,
        server.secretNonce!,
        server.secretMac!,
      ),
    );
  }

  Future<ServerStatus> checkTcp(ServerEntry server, {int port = 1433}) async {
    if (server.ip.trim().isEmpty) return server.status;
    ServerStatus result;
    try {
      final socket = await Socket.connect(
        server.ip.trim(),
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      result = ServerStatus.online;
    } catch (_) {
      result = ServerStatus.offline;
    }
    await (db.update(db.servers)..where((t) => t.id.equals(server.id))).write(
      ServersCompanion(
        status: Value(result),
        updatedAt: Value(now),
        version: Value(server.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
    return result;
  }

  Future<bool> checkPort({required String host, int port = 1433}) async {
    try {
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 4),
      );
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> importCsv(String csvText) async {
    final rows = const CsvDecoder().convert(csvText.trim());
    if (rows.isEmpty) return 0;
    var start = 0;
    final header = rows.first.map((e) => e.toString().toLowerCase()).toList();
    if (header.contains('name') || header.contains('server name')) {
      start = 1;
    }
    var imported = 0;
    for (var i = start; i < rows.length; i++) {
      final row = rows[i];
      if (row.isEmpty || row.first.toString().trim().isEmpty) continue;
      final name = row[0].toString().trim();
      final ip = row.length > 1 ? row[1].toString().trim() : '';
      final database = row.length > 2 ? row[2].toString().trim() : '';
      final purposeRaw = row.length > 3
          ? row[3].toString().toLowerCase()
          : 'other';
      final purpose = ServerPurpose.values.firstWhere(
        (p) =>
            p.name.toLowerCase() == purposeRaw ||
            p.label.toLowerCase() == purposeRaw,
        orElse: () => ServerPurpose.other,
      );
      await create(
        name: name,
        ip: ip,
        databaseName: database,
        purpose: purpose,
      );
      imported++;
    }
    return imported;
  }

  Future<String> exportCsv() async {
    final rows = await activeList();
    final data = <List<dynamic>>[
      [
        'Server Name',
        'IP',
        'Database',
        'Purpose',
        'Status',
        'Last Backup',
        'Notes',
      ],
      for (final row in rows)
        [
          row.name,
          row.ip,
          row.databaseName,
          row.purpose.label,
          row.status.label,
          row.lastBackup?.toIso8601String() ?? '',
          row.notes,
        ],
    ];
    return const CsvEncoder().convert(data);
  }

  Future<void> softDelete(String id) async {
    final row = await byId(id);
    if (row == null) return;
    await (db.update(db.servers)..where((t) => t.id.equals(id))).write(
      ServersCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> restore(String id) async {
    final row = await byId(id);
    if (row == null) return;
    await (db.update(db.servers)..where((t) => t.id.equals(id))).write(
      ServersCompanion(
        deletedAt: const Value(null),
        updatedAt: Value(now),
        version: Value(row.version + 1),
        syncStatus: const Value(SyncState.pending),
      ),
    );
  }

  Future<void> deleteForever(String id) async {
    await (db.delete(db.servers)..where((t) => t.id.equals(id))).go();
  }

  Future<int> countOnline() async {
    final rows =
        await (db.select(db.servers)..where(
              (t) =>
                  t.deletedAt.isNull() &
                  t.status.equalsValue(ServerStatus.online),
            ))
            .get();
    return rows.length;
  }
}
