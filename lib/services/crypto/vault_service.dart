import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/utils.dart';
import 'crypto_service.dart';

class SecretEnvelope {
  const SecretEnvelope({
    required this.cipher,
    required this.nonce,
    required this.mac,
  });
  final String cipher;
  final String nonce;
  final String mac;

  Map<String, String> toColumns() => {
    'cipher': cipher,
    'nonce': nonce,
    'mac': mac,
  };

  static SecretEnvelope fromColumns(String cipher, String nonce, String mac) =>
      SecretEnvelope(cipher: cipher, nonce: nonce, mac: mac);
}

/// Owns the local vault file and keeps the unlocked data key in memory only.
///
/// The vault password is never persisted. The random 32-byte data key is
/// wrapped with an Argon2id-derived key (and optionally a recovery key). All
/// cloud payloads are encrypted with the data key, so changing the password
/// only re-wraps the key instead of re-encrypting every remote file.
class VaultService {
  VaultService({CryptoService? crypto, Directory? directory})
    : _crypto = crypto ?? CryptoService(),
      _overrideDirectory = directory;

  final CryptoService _crypto;
  final Directory? _overrideDirectory;
  SecretKey? _dataKey;
  List<int>? _salt;

  bool get isUnlocked => _dataKey != null;
  List<int>? get salt => _salt;

  Future<Directory> _dir() async =>
      _overrideDirectory ?? await getApplicationSupportDirectory();

  Future<File> _file() async => File(p.join((await _dir()).path, 'vault.json'));

  Future<bool> isInitialized() async => (await _file()).exists();

  Future<Map<String, dynamic>?> _read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  }

  Future<void> _write(Map<String, dynamic> data) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<void> setup(String password, {String? hint}) async {
    if (password.length < 8) {
      throw ArgumentError('Use at least 8 characters for the vault password.');
    }
    final dataKey = await _crypto.randomKey();
    final keyBytes = await dataKey.extractBytes();
    final vaultSalt = randomBytes(16);
    final wrappingKey = await _crypto.deriveKey(password, vaultSalt);
    final wrapped = await _crypto.encryptString(b64(keyBytes), wrappingKey);
    _dataKey = dataKey;
    _salt = vaultSalt;
    await _write({
      'version': 1,
      'createdAt': DateTime.now().toIso8601String(),
      'hint': hint ?? '',
      'salt': b64(vaultSalt),
      'wrapped': wrapped,
    });
  }

  Future<bool> unlock(String password) async {
    final data = await _read();
    if (data == null) return false;
    try {
      final vaultSalt = unb64(data['salt'] as String);
      final wrappingKey = await _crypto.deriveKey(password, vaultSalt);
      final keyB64 = await _crypto.decryptString(
        (data['wrapped'] as Map).cast<String, dynamic>(),
        wrappingKey,
      );
      _dataKey = SecretKey(unb64(keyB64));
      _salt = vaultSalt;
      return true;
    } catch (_) {
      _dataKey = null;
      return false;
    }
  }

  Future<bool> unlockWithRecoveryKey(String recoveryKey) async {
    final data = await _read();
    if (data == null) return false;
    final recovery = data['recovery'] as Map<String, dynamic>?;
    if (recovery == null) return false;
    try {
      final saltBytes = unb64(recovery['salt'] as String);
      final wrappingKey = await _crypto.deriveKey(
        recoveryKey.trim(),
        saltBytes,
      );
      final keyB64 = await _crypto.decryptString(
        (recovery['wrapped'] as Map).cast<String, dynamic>(),
        wrappingKey,
      );
      _dataKey = SecretKey(unb64(keyB64));
      _salt = unb64(data['salt'] as String);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String> exportRecoveryKey() async {
    final dataKey = _requireKey();
    final data = await _read();
    final dataKeyBytes = await dataKey.extractBytes();
    final recoveryKey = b64(randomBytes(32));
    final recoverySalt = randomBytes(16);
    final wrappingKey = await _crypto.deriveKey(recoveryKey, recoverySalt);
    final wrapped = await _crypto.encryptString(b64(dataKeyBytes), wrappingKey);
    data?['recovery'] = {
      'salt': b64(recoverySalt),
      'wrapped': wrapped,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (data != null) await _write(data);
    return recoveryKey;
  }

  Future<void> changePassword(String current, String next) async {
    if (!await unlock(current)) {
      throw StateError('Current password is incorrect.');
    }
    final dataKey = _requireKey();
    final dataKeyBytes = await dataKey.extractBytes();
    final vaultSalt = randomBytes(16);
    final wrappingKey = await _crypto.deriveKey(next, vaultSalt);
    final wrapped = await _crypto.encryptString(b64(dataKeyBytes), wrappingKey);
    final data = await _read() ?? <String, dynamic>{};
    data['salt'] = b64(vaultSalt);
    data['wrapped'] = wrapped;
    data['version'] = 1;
    await _write(data);
    _salt = vaultSalt;
  }

  void lock() => _dataKey = null;

  Future<SecretEnvelope> encryptSecret(String clearText) async {
    final envelope = await _crypto.encryptString(clearText, _requireKey());
    return SecretEnvelope(
      cipher: envelope['ct']!,
      nonce: envelope['nonce']!,
      mac: envelope['mac']!,
    );
  }

  Future<String> decryptSecret(SecretEnvelope envelope) {
    return _crypto.decryptString({
      'ct': envelope.cipher,
      'nonce': envelope.nonce,
      'mac': envelope.mac,
    }, _requireKey());
  }

  Future<SecretKey> dataKeyForBackup() async {
    if (_dataKey == null) {
      throw StateError(
        'Unlock the vault before exporting an encrypted backup.',
      );
    }
    return _dataKey!;
  }

  SecretKey _requireKey() {
    final key = _dataKey;
    if (key == null) {
      throw StateError('Vault is locked.');
    }
    return key;
  }
}
