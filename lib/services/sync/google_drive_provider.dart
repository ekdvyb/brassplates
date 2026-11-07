import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;

import '../../data/models/enums.dart';
import 'sync_provider.dart';

/// Google Drive sync using the private [appDataFolder] scope only.
///
/// The user's visible Drive is never touched. Files are stored flat inside the
/// app data folder with `/` encoded as `__`.
class GoogleDriveSyncProvider implements SyncProvider {
  GoogleDriveSyncProvider();

  GoogleSignIn? _signIn;
  drive.DriveApi? _drive;
  final Map<String, String> _idCache = {};

  @override
  SyncProviderKind get kind => SyncProviderKind.googleDrive;

  @override
  String get label => 'Google Drive (app data folder)';

  String _encode(String path) => path.replaceAll('/', '__');

  Future<drive.DriveApi> _api() async {
    if (_drive != null) return _drive!;
    final signIn = _signIn ??= GoogleSignIn(
      scopes: [drive.DriveApi.driveAppdataScope],
    );
    final account = await signIn.signIn();
    if (account == null) {
      throw StateError('Google sign-in was cancelled.');
    }
    final headers = await account.authHeaders;
    final raw = headers['Authorization'] ?? headers['authorization'];
    if (raw == null) {
      throw StateError('No authorization header returned by Google.');
    }
    final token = raw.replaceFirst('Bearer ', '');
    final credentials = auth.AccessCredentials(
      auth.AccessToken(
        'Bearer',
        token,
        DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      null,
      [drive.DriveApi.driveAppdataScope],
    );
    final client = auth.authenticatedClient(http.Client(), credentials);
    _drive = drive.DriveApi(client);
    return _drive!;
  }

  Future<drive.File?> _find(String encodedName) async {
    final cached = _idCache[encodedName];
    if (cached != null) {
      return drive.File(id: cached, name: encodedName);
    }
    final api = await _api();
    final result = await api.files.list(
      q: "name = '$encodedName' and trashed = false",
      spaces: 'appDataFolder',
      $fields: 'files(id,name,modifiedTime)',
    );
    final files = result.files;
    if (files == null || files.isEmpty) return null;
    _idCache[encodedName] = files.first.id!;
    return files.first;
  }

  @override
  Future<bool> test() async {
    try {
      final api = await _api();
      await api.files.list(
        spaces: 'appDataFolder',
        pageSize: 1,
        $fields: 'files(id)',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<List<int>?> readBytes(String path) async {
    try {
      final file = await _find(_encode(path));
      if (file?.id == null) return null;
      final api = await _api();
      final media = await api.files.get(
        file!.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;
      final chunks = await media.stream.toList();
      return chunks.expand((e) => e).toList();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> writeBytes(String path, List<int> bytes) async {
    final encoded = _encode(path);
    final api = await _api();
    final existing = await _find(encoded);
    final data = Uint8List.fromList(bytes);
    final media = drive.Media(Stream<List<int>>.value(data), data.length);
    if (existing?.id == null) {
      final created = await api.files.create(
        drive.File(name: encoded, parents: ['appDataFolder']),
        uploadMedia: media,
      );
      _idCache[encoded] = created.id!;
    } else {
      await api.files.update(drive.File(), existing!.id!, uploadMedia: media);
    }
  }

  @override
  Future<bool> exists(String path) async =>
      (await _find(_encode(path))) != null;

  @override
  Future<void> ensureDir(String path) async {}

  @override
  Future<void> close() async {}
}
