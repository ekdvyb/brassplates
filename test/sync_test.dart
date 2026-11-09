import 'dart:io';

import 'package:brassplates/data/db/database.dart';
import 'package:brassplates/data/repositories/notes_repository.dart';
import 'package:brassplates/services/crypto/vault_service.dart';
import 'package:brassplates/services/snapshot/snapshot_service.dart';
import 'package:brassplates/services/sync/sync_provider.dart';
import 'package:brassplates/services/sync/sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoSnapshots extends SnapshotService {
  _NoSnapshots(super.db);

  @override
  Future<Snapshot> create(String reason) async => Snapshot(
    id: 'test',
    path: '',
    reason: reason,
    bytes: 0,
    createdAt: DateTime.now(),
  );
}

void main() {
  late Directory vaultDir;
  late VaultService vault;
  late MemorySyncProvider provider;
  late AppDatabase phone;
  late AppDatabase laptop;

  setUp(() async {
    vaultDir = await Directory.systemTemp.createTemp('bp-vault');
    vault = VaultService(directory: vaultDir);
    await vault.setup('correct horse battery');
    provider = MemorySyncProvider();
    phone = AppDatabase.forTesting(NativeDatabase.memory());
    laptop = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await phone.close();
    await laptop.close();
    await vaultDir.delete(recursive: true);
  });

  SyncService serviceFor(AppDatabase db, String deviceId) => SyncService(
    db: db,
    provider: provider,
    vault: vault,
    snapshots: _NoSnapshots(db),
    deviceId: deviceId,
  );

  test('a note created on the phone arrives on the laptop', () async {
    final phoneNotes = NotesRepository(phone, 'phone');
    final laptopNotes = NotesRepository(laptop, 'laptop');

    final note = await phoneNotes.create(
      title: 'Shopping',
      plainText: 'Milk and bread',
    );
    expect((await serviceFor(phone, 'phone').sync()).ok, isTrue);
    expect((await serviceFor(laptop, 'laptop').sync()).ok, isTrue);

    final synced = await laptopNotes.byId(note.id);
    expect(synced, isNotNull);
    expect(synced!.title, 'Shopping');
    expect(synced.plainText, 'Milk and bread');
  });

  test('edits travel back from the laptop to the phone', () async {
    final phoneNotes = NotesRepository(phone, 'phone');
    final laptopNotes = NotesRepository(laptop, 'laptop');

    final note = await phoneNotes.create(title: 'Plan', plainText: 'v1');
    expect((await serviceFor(phone, 'phone').sync()).ok, isTrue);
    expect((await serviceFor(laptop, 'laptop').sync()).ok, isTrue);

    final onLaptop = await laptopNotes.byId(note.id);
    await laptopNotes.save(
      onLaptop!,
      title: 'Plan',
      contentDelta: onLaptop.contentDelta,
      plainText: 'v2 from laptop',
    );
    expect((await serviceFor(laptop, 'laptop').sync()).ok, isTrue);
    expect((await serviceFor(phone, 'phone').sync()).ok, isTrue);

    expect((await phoneNotes.byId(note.id))!.plainText, 'v2 from laptop');
  });
}
