import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Criptografia do conteúdo antes de sair do aparelho. O banco guarda apenas
/// ciphertext, nonce e tag de autenticação do AES-GCM.
class SupabaseSocialCrypto {
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();

  static List<int> _randomBytes(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256), growable: false);
  }

  static String _b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  static List<int> _unb64(String value) => base64Url.decode(base64Url.normalize(value));
  static String _keyName(String conversationId) => 'social_group_key_$conversationId';

  static Future<List<int>> newGroupKey() async => _randomBytes(32);

  static Future<void> saveGroupKey(String conversationId, List<int> key) =>
      _storage.write(key: _keyName(conversationId), value: _b64(key));

  static Future<void> removeGroupKey(String conversationId) => _storage.delete(key: _keyName(conversationId));

  static Future<List<int>?> groupKey(String conversationId) async {
    final stored = await _storage.read(key: _keyName(conversationId));
    return stored == null ? null : _unb64(stored);
  }

  static Future<Map<String, String>> encrypt(String conversationId, String senderId, String text) async {
    final key = await groupKey(conversationId);
    if (key == null) throw StateError('Chave local deste grupo não encontrada. Entre novamente pelo convite.');
    final aad = utf8.encode('ava-sync-social-v1|$conversationId|$senderId');
    final box = await _aes.encrypt(utf8.encode(text), secretKey: SecretKey(key), nonce: _randomBytes(12), aad: aad);
    return {'ciphertext': _b64(box.cipherText), 'nonce': _b64(box.nonce), 'mac': _b64(box.mac.bytes)};
  }

  static Future<String> decrypt(String conversationId, Map<String, dynamic> row) async {
    final key = await groupKey(conversationId);
    if (key == null) throw StateError('Chave local deste grupo não encontrada.');
    final box = SecretBox(
      _unb64('${row['ciphertext']}'),
      nonce: _unb64('${row['nonce']}'),
      mac: Mac(_unb64('${row['mac']}')),
    );
    final aad = utf8.encode('ava-sync-social-v1|$conversationId|${row['sender_id']}');
    return utf8.decode(await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad));
  }

  static String makeInvite({required String conversationId, required String token, required String conversationKey}) {
    final payload = jsonEncode({'v': 1, 'id': conversationId, 'invite': token, 'key': conversationKey});
    return 'AVASYNC1.${_b64(utf8.encode(payload))}';
  }

  static SocialInvite parseInvite(String value) {
    final trimmed = value.trim();
    if (!trimmed.startsWith('AVASYNC1.')) throw const FormatException('Esse código de convite não é válido.');
    final payload = jsonDecode(utf8.decode(_unb64(trimmed.substring('AVASYNC1.'.length))));
    if (payload is! Map || payload['v'] != 1 || payload['id'] is! String || payload['invite'] is! String || payload['key'] is! String) {
      throw const FormatException('Esse código de convite não é válido.');
    }
    final key = _unb64(payload['key'] as String);
    if (key.length != 32) throw const FormatException('Esse código de convite não é válido.');
    return SocialInvite(conversationId: payload['id'] as String, token: payload['invite'] as String, conversationKey: payload['key'] as String);
  }
}

