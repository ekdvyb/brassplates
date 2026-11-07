import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:webdav_client/webdav_client.dart' as webdav;

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

class LocalFolderProvider implements SyncProvider {
  LocalFolderProvider(this.rootPath);

  final String rootPath;

  @override
  SyncProviderKind get kind => SyncProviderKind.localFolder;

  @override
  String get label => 'Local folder';

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

class WebDavSyncProvider implements SyncProvider {
  WebDavSyncProvider({
    required this.url,
    required this.username,
    required this.password,
    this.kind = SyncProviderKind.webdav,
    this.label = 'WebDAV',
  }) {
    _client = webdav.newClient(url, user: username, password: password);
    _client.setConnectTimeout(20000);
    _client.setReceiveTimeout(60000);
    _client.setSendTimeout(60000);
  }

  final String url;
  final String username;
  final String password;

  @override
  final SyncProviderKind kind;

  @override
  final String label;

  late final webdav.Client _client;

  String _remote(String path) => '/BrassPlates/data/$path';

  @override
  Future<bool> test() async {
    try {
      await _client.ping();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    try {
      return await _client.read(_remote(path));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    await ensureDir(p.dirname(path));
    await _client.write(_remote(path), Uint8List.fromList(bytes));
  }

  @override
  Future<bool> exists(String path) async {
    try {
      await _client.readProps(_remote(path));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> ensureDir(String path) async {
    final clean = path.replaceAll('\\', '/');
    if (clean.isEmpty || clean == '.') {
      await _client.mkdirAll('/BrassPlates/data');
      return;
    }
    await _client.mkdirAll('/BrassPlates/data/$clean');
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
