import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

/// Conteúdo de uma mensagem depois de aberta.
class ConteudoMensagem {
  final String texto;
  final List<SocialAttachment> anexos;
  const ConteudoMensagem(this.texto, [this.anexos = const []]);
}

/// Criptografia feita no aparelho. O servidor guarda só ciphertext, nonce e tag do
/// AES-GCM. Cada conversa tem uma chave de 32 bytes que chega:
/// - pelo convite (`AVASYNC1.`), ou
/// - por envelope: a chave da conversa cifrada para a chave pública X25519 do
///   aparelho de cada membro (qualquer membro que já tem a chave embrulha para os outros).
class SupabaseSocialCrypto {
  static const _storage = FlutterSecureStorage();
  static final _aes = AesGcm.with256bits();
  static final _x25519 = X25519();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final Map<String, List<int>?> _cache = {};
  static SimpleKeyPair? _device;
  static String? _devicePublic;

  static List<int> _randomBytes(int count) {
    final random = Random.secure();
    return List<int>.generate(count, (_) => random.nextInt(256), growable: false);
  }

  static String b64(List<int> bytes) => base64Url.encode(bytes).replaceAll('=', '');
  static List<int> unb64(String value) => base64Url.decode(base64Url.normalize(value));
  static String _keyName(String conversationId) => 'social_group_key_$conversationId';

  // ------------------------------------------------------------ chaves das conversas
  static Future<List<int>> newGroupKey() async => _randomBytes(32);

  static String _oldKeysName(String conversationId) => 'social_group_keys_old_$conversationId';
  static final Map<String, List<List<int>>> _oldCache = {};

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Chaves que este aparelho já teve para a conversa (a atual primeiro). Nenhuma é
  /// jogada fora: mensagens antigas podem ter sido cifradas com qualquer uma delas.
  static Future<List<List<int>>> groupKeys(String conversationId) async {
    final current = await groupKey(conversationId);
    if (!_oldCache.containsKey(conversationId)) {
      final raw = await _storage.read(key: _oldKeysName(conversationId));
      _oldCache[conversationId] = [
        for (final k in (raw ?? '').split(',')) if (k.isNotEmpty) unb64(k),
      ];
    }
    return [?current, ..._oldCache[conversationId]!];
  }

  static Future<void> _saveOld(String conversationId, List<List<int>> old) async {
    _oldCache[conversationId] = old;
    await _storage.write(key: _oldKeysName(conversationId), value: old.map(b64).join(','));
  }

  /// Guarda a chave. Com [atual] (convite ou conversa nova) ela passa a ser usada para
  /// cifrar e a anterior continua guardada para ler; sem [atual] (envelope) ela só é
  /// acrescentada se o aparelho já tiver outra.
  static Future<void> saveGroupKey(String conversationId, List<int> key, {bool atual = true}) async {
    final keys = await groupKeys(conversationId);
    final current = keys.isEmpty ? null : keys.first;
    if (current != null && _same(current, key)) return;
    if (current == null || atual) {
      _cache[conversationId] = key;
      await _storage.write(key: _keyName(conversationId), value: b64(key));
      await _saveOld(conversationId, [for (final k in keys) if (!_same(k, key)) k]);
    } else if (!keys.any((k) => _same(k, key))) {
      await _saveOld(conversationId, [...keys.skip(1), key]);
    }
  }

  static Future<void> removeGroupKey(String conversationId) async {
    _cache.remove(conversationId);
    _oldCache.remove(conversationId);
    await _storage.delete(key: _keyName(conversationId));
    await _storage.delete(key: _oldKeysName(conversationId));
  }

  static Future<List<int>?> groupKey(String conversationId) async {
    if (_cache.containsKey(conversationId)) return _cache[conversationId];
    final stored = await _storage.read(key: _keyName(conversationId));
    final key = stored == null ? null : unb64(stored);
    _cache[conversationId] = key;
    return key;
  }

  static Future<bool> hasKey(String conversationId) async => (await groupKey(conversationId)) != null;

  /// Só para testes.
  static void setKeyForTest(String conversationId, List<int>? key) {
    _cache[conversationId] = key;
    _oldCache[conversationId] = [];
  }

  /// Só para testes: esquece a chave do aparelho carregada.
  static void resetDeviceForTest() {
    _device = null;
    _devicePublic = null;
  }

  // ------------------------------------------------------------ mensagens
  static List<int> _aad(int format, String conversationId, String channelId, String senderId) => utf8.encode(format == 2
      ? 'ava-sync-social-v2|$conversationId|$channelId|$senderId'
      : 'ava-sync-social-v1|$conversationId|$senderId');

  /// Formato 2: JSON `{t: texto, a: [anexos]}` com o canal no AAD.
  static Future<Map<String, dynamic>> encryptMessage({
    required String conversationId,
    required String channelId,
    required String senderId,
    required String text,
    List<SocialAttachment> attachments = const [],
  }) async {
    final key = await groupKey(conversationId);
    if (key == null) throw StateError('Este aparelho ainda não tem a chave desta conversa. Peça um convite ou espere um membro abrir o app.');
    final body = jsonEncode({'t': text, if (attachments.isNotEmpty) 'a': [for (final a in attachments) a.toJson()]});
    final box = await _aes.encrypt(utf8.encode(body), secretKey: SecretKey(key), nonce: _randomBytes(12), aad: _aad(2, conversationId, channelId, senderId));
    return {'ciphertext': b64(box.cipherText), 'nonce': b64(box.nonce), 'mac': b64(box.mac.bytes), 'format': 2};
  }

  /// Abre uma linha de `social_messages` (formatos 1 e 2).
  static Future<ConteudoMensagem> decryptRow(Map<String, dynamic> row) async {
    final conversationId = '${row['conversation_id']}';
    final keys = await groupKeys(conversationId);
    if (keys.isEmpty) throw StateError('Sem a chave desta conversa.');
    final format = row['format'] is num ? (row['format'] as num).toInt() : 1;
    final box = SecretBox(unb64('${row['ciphertext']}'), nonce: unb64('${row['nonce']}'), mac: Mac(unb64('${row['mac']}')));
    final aad = _aad(format, conversationId, '${row['channel_id']}', '${row['sender_id']}');
    List<int>? bytes;
    for (final key in keys) {
      try {
        bytes = await _aes.decrypt(box, secretKey: SecretKey(key), aad: aad);
        break;
      } on SecretBoxAuthenticationError {
        continue;
      }
    }
    if (bytes == null) throw StateError('Nenhuma chave deste aparelho abre esta mensagem.');
    final clear = utf8.decode(bytes);
    if (format != 2) return ConteudoMensagem(clear);
    final j = jsonDecode(clear);
    if (j is! Map) return const ConteudoMensagem('');
    return ConteudoMensagem(
      '${j['t'] ?? ''}',
      [for (final a in (j['a'] as List? ?? const [])) ?SocialAttachment.fromJson(a)],
    );
  }

  /// Compatível com o formato do app 0.7.0 (usado pelos testes antigos).
  static Future<Map<String, String>> encrypt(String conversationId, String senderId, String text) async {
    final key = await groupKey(conversationId);
    if (key == null) throw StateError('Chave local deste grupo não encontrada. Entre novamente pelo convite.');
    final box = await _aes.encrypt(utf8.encode(text), secretKey: SecretKey(key), nonce: _randomBytes(12), aad: _aad(1, conversationId, '', senderId));
    return {'ciphertext': b64(box.cipherText), 'nonce': b64(box.nonce), 'mac': b64(box.mac.bytes)};
  }

  // ------------------------------------------------------------ arquivos
  /// nonce(12) | ciphertext | tag(16)
  static Future<Uint8List> encryptFile(String conversationId, String path, List<int> bytes) async {
    final key = await groupKey(conversationId);
    if (key == null) throw StateError('Sem a chave desta conversa.');
    final box = await _aes.encrypt(bytes, secretKey: SecretKey(key), nonce: _randomBytes(12), aad: utf8.encode('ava-sync-file-v1|$path'));
    return Uint8List.fromList([...box.nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  static Future<Uint8List> decryptFile(String conversationId, String path, List<int> data) async {
    final keys = await groupKeys(conversationId);
    if (keys.isEmpty) throw StateError('Sem a chave desta conversa.');
    if (data.length < 28) throw const FormatException('Arquivo corrompido.');
    final box = SecretBox(data.sublist(12, data.length - 16), nonce: data.sublist(0, 12), mac: Mac(data.sublist(data.length - 16)));
    for (final key in keys) {
      try {
        return Uint8List.fromList(await _aes.decrypt(box, secretKey: SecretKey(key), aad: utf8.encode('ava-sync-file-v1|$path')));
      } on SecretBoxAuthenticationError {
        continue;
      }
    }
    throw StateError('Nenhuma chave deste aparelho abre este arquivo.');
  }

  // ------------------------------------------------------------ chave do aparelho
  static Future<SimpleKeyPair> _deviceKey() async {
    if (_device != null) return _device!;
    var seed = await _storage.read(key: 'social_device_seed');
    if (seed == null) {
      seed = b64(_randomBytes(32));
      await _storage.write(key: 'social_device_seed', value: seed);
    }
    _device = await _x25519.newKeyPairFromSeed(unb64(seed));
    return _device!;
  }

  static Future<String> devicePublicKey() async {
    if (_devicePublic != null) return _devicePublic!;
    final pub = await (await _deviceKey()).extractPublicKey();
    return _devicePublic = b64(pub.bytes);
  }

  static Future<SecretKey> _wrapKey(String conversationId, String otherPublic, String senderPublic, String recipientPublic) async {
    final shared = await _x25519.sharedSecretKey(
      keyPair: await _deviceKey(),
      remotePublicKey: SimplePublicKey(unb64(otherPublic), type: KeyPairType.x25519),
    );
    return _hkdf.deriveKey(
      secretKey: shared,
      nonce: utf8.encode('ava-sync-envelope-v1|$conversationId'),
      info: utf8.encode('$senderPublic|$recipientPublic'),
    );
  }

  /// Embrulha a chave da conversa para o aparelho de outro membro.
  static Future<Map<String, dynamic>?> sealFor({required String conversationId, required String userKey, required String recipientPublic}) async {
    final key = await groupKey(conversationId);
    if (key == null) return null;
    final mine = await devicePublicKey();
    final wrap = await _wrapKey(conversationId, recipientPublic, mine, recipientPublic);
    final box = await _aes.encrypt(key, secretKey: wrap, nonce: _randomBytes(12));
    return {
      'conversationId': conversationId,
      'userKey': userKey,
      'recipientPublic': recipientPublic,
      'senderPublic': mine,
      'sealed': b64(box.cipherText),
      'nonce': b64(box.nonce),
      'mac': b64(box.mac.bytes),
    };
  }

  /// Abre um envelope recebido e guarda a chave. Devolve true se deu certo.
  static Future<bool> openEnvelope(Map<String, dynamic> e) async {
    try {
      final conversationId = '${e['conversation_id']}';
      final mine = await devicePublicKey();
      final sender = '${e['sender_public']}';
      final wrap = await _wrapKey(conversationId, sender, sender, mine);
      final key = await _aes.decrypt(
        SecretBox(unb64('${e['sealed']}'), nonce: unb64('${e['nonce']}'), mac: Mac(unb64('${e['mac']}'))),
        secretKey: wrap,
      );
      if (key.length != 32) return false;
      await saveGroupKey(conversationId, key, atual: false);
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ convites
  static String makeInvite({required String conversationId, required String token, required String conversationKey}) {
    final payload = jsonEncode({'v': 1, 'id': conversationId, 'invite': token, 'key': conversationKey});
    return 'AVASYNC1.${b64(utf8.encode(payload))}';
  }

  static SocialInvite parseInvite(String value) {
    var trimmed = value.trim();
    final at = trimmed.indexOf('AVASYNC1.');
    if (at > 0) trimmed = trimmed.substring(at).split(RegExp(r'\s')).first;
    if (!trimmed.startsWith('AVASYNC1.')) throw const FormatException('Esse código de convite não é válido.');
    final dynamic payload;
    try {
      payload = jsonDecode(utf8.decode(unb64(trimmed.substring('AVASYNC1.'.length))));
    } catch (_) {
      throw const FormatException('Esse código de convite não é válido.');
    }
    if (payload is! Map || payload['v'] != 1 || payload['id'] is! String || payload['invite'] is! String || payload['key'] is! String) {
      throw const FormatException('Esse código de convite não é válido.');
    }
    final key = unb64(payload['key'] as String);
    if (key.length != 32) throw const FormatException('Esse código de convite não é válido.');
    return SocialInvite(conversationId: payload['id'] as String, token: payload['invite'] as String, conversationKey: payload['key'] as String);
  }

  static String newSecret() => b64(_randomBytes(32));
}
