import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../core/utils.dart';

/// AES-256-GCM envelope encryption with an Argon2id-derived key.
///
/// Every encrypted payload uses a fresh random nonce. Nothing derived from the
/// password is ever written to the remote sync folder.
class CryptoService {
  CryptoService({Argon2id? kdf})
    : _kdf =
          kdf ??
          Argon2id(
            memory: 65536,
            iterations: 3,
            parallelism: 2,
            hashLength: 32,
          );

  final Argon2id _kdf;
  final AesGcm _aead = AesGcm.with256bits();

  Future<SecretKey> deriveKey(String password, List<int> salt) {
    return _kdf.deriveKeyFromPassword(password: password, nonce: salt);
  }

  Future<SecretKey> randomKey() async {
    return SecretKey(randomBytes(32));
  }

  Future<Map<String, String>> encryptString(
    String clearText,
    SecretKey key,
  ) async {
    final box = await _aead.encrypt(utf8.encode(clearText), secretKey: key);
    return {
      'ct': b64(box.cipherText),
      'nonce': b64(box.nonce),
      'mac': b64(box.mac.bytes),
    };
  }

  Future<String> decryptString(
    Map<String, dynamic> envelope,
    SecretKey key,
  ) async {
    final box = SecretBox(
      unb64(envelope['ct'] as String),
      nonce: unb64(envelope['nonce'] as String),
      mac: Mac(unb64(envelope['mac'] as String)),
    );
    final clear = await _aead.decrypt(box, secretKey: key);
    return utf8.decode(clear);
  }

  Future<Uint8List> encryptBytes(List<int> clearBytes, SecretKey key) async {
    final box = await _aead.encrypt(clearBytes, secretKey: key);
    final builder = BytesBuilder(copy: false);
    builder.addByte(box.nonce.length);
    builder.add(box.nonce);
    builder.addByte(box.mac.bytes.length);
    builder.add(box.mac.bytes);
    builder.add(box.cipherText);
    return builder.toBytes();
  }

  Future<Uint8List> decryptBytes(List<int> payload, SecretKey key) async {
    final bytes = Uint8List.fromList(payload);
    var offset = 0;
    final nonceLength = bytes[offset++];
    final nonce = bytes.sublist(offset, offset + nonceLength);
    offset += nonceLength;
    final macLength = bytes[offset++];
    final mac = bytes.sublist(offset, offset + macLength);
    offset += macLength;
    final cipherText = bytes.sublist(offset);
    final clear = await _aead.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    return Uint8List.fromList(clear);
  }

  /// Deterministic short fingerprint used to verify a password without
  /// exposing it.
  Future<String> passwordFingerprint(String password, List<int> salt) async {
    final key = await deriveKey(password, salt);
    final bytes = await key.extractBytes();
    return base64UrlEncode(bytes.sublist(0, 9));
  }
}
