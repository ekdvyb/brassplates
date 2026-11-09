import 'dart:io';

import 'package:path/path.dart' as p;

import '../../data/models/enums.dart';

abstract class SyncProvider {
  SyncProviderKind get kind;
  String get label;

  Future<bool> test();
  Future<List<int>?> readBytes(String path);
  Future<void> writeBytes(String path, List<int> bytes);
  Future<bool> exists(String path);
  Future<void> ensureDir(String path);
  Future<void> close();
}

/// Syncs through a normal folder.
///
/// Point this at a Google Drive, OneDrive or Syncthing folder and the cloud
/// client does the transport. BRASSPLATES itself never talks to a server.
class LocalFolderProvider implements SyncProvider {
  LocalFolderProvider(this.rootPath);

  final String rootPath;

  @override
  SyncProviderKind get kind => SyncProviderKind.localFolder;

  @override
  String get label => 'Sync folder';

  File _file(String path) => File(p.join(rootPath, path));

  @override
  Future<bool> test() async {
    try {
      final dir = Directory(rootPath);
      await dir.create(recursive: true);
      final probe = File(p.join(rootPath, '.brassplates-probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    final file = _file(path);
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final file = _file(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<bool> exists(String path) => _file(path).exists();

  @override
  Future<void> ensureDir(String path) async {
    await Directory(p.join(rootPath, path)).create(recursive: true);
  }

  @override
  Future<void> close() async {}
}

class MemorySyncProvider implements SyncProvider {
  MemorySyncProvider();

  final Map<String, List<int>> files = {};

  @override
  SyncProviderKind get kind => SyncProviderKind.localFolder;

  @override
  String get label => 'In-memory (tests)';

  @override
  Future<bool> test() async => true;

  @override
  Future<List<int>?> readBytes(String path) async => files[path];

  @override
  Future<void> writeBytes(String path, List<int> bytes) async =>
      files[path] = bytes;

  @override
  Future<bool> exists(String path) async => files.containsKey(path);

  @override
  Future<void> ensureDir(String path) async {}

  @override
  Future<void> close() async {}
}
