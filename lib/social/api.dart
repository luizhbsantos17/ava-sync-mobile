import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../estado_app.dart';

class SocialApiException implements Exception {
  final String message;
  final int status;
  const SocialApiException(this.message, [this.status = 0]);

  bool get rede => status == 0;
  @override
  String toString() => message;
}

/// Fala com a Edge Function `social`. Troca o token do AVA por uma sessão de 12 h
/// (guardada no armazenamento seguro) e renova sozinha quando expira.
class SocialApi {
  static const url = String.fromEnvironment('SOCIAL_SUPABASE_URL', defaultValue: 'https://zfyxjqdiffuuofwrgvat.supabase.co');
  static const key = String.fromEnvironment('SOCIAL_SUPABASE_KEY', defaultValue: 'sb_publishable_Z2Dd3ItPRVW7DRq3vo8jlg_ftshQWRi');
  static const _storage = FlutterSecureStorage();

  final http.Client _http;
  String? _session;
  int _expiresAt = 0;
  Future<Map<String, dynamic>>? _renewing;

  /// Perfil devolvido na última renovação da sessão.
  Map<String, dynamic>? lastMe;

  SocialApi({http.Client? client}) : _http = client ?? http.Client();

  static bool get configured => url.isNotEmpty && key.isNotEmpty;

  Future<String?> _moodleToken() async => app.token ?? await Cfg.token();

  Future<void> _loadSession() async {
    if (_session != null) return;
    final raw = await _storage.read(key: 'social_session');
    if (raw == null) return;
    final parts = raw.split('|');
    if (parts.length != 2) return;
    _session = parts[1];
    _expiresAt = int.tryParse(parts[0]) ?? 0;
  }

  bool get _sessionValid => _session != null && _expiresAt - 300 > DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<Map<String, dynamic>> renewSession() {
    return _renewing ??= () async {
      try {
        final token = await _moodleToken();
        if (token == null || Cfg.site.isEmpty) throw const SocialApiException('Entre no AVA para usar o Social.', 401);
        final r = Map<String, dynamic>.from(await _post({'action': 'session', 'site': Cfg.site, 'token': token}) as Map);
        _session = '${r['session']}';
        _expiresAt = (r['expiresAt'] as num).toInt();
        lastMe = r['me'] is Map ? Map<String, dynamic>.from(r['me'] as Map) : null;
        await _storage.write(key: 'social_session', value: '$_expiresAt|$_session');
        return r;
      } finally {
        _renewing = null;
      }
    }();
  }

  Future<void> clearSession() async {
    _session = null;
    _expiresAt = 0;
    await _storage.delete(key: 'social_session');
  }

  Future<dynamic> _post(Map<String, dynamic> body, {Duration timeout = const Duration(seconds: 30)}) async {
    final http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse('$url/functions/v1/social'),
            headers: {'Content-Type': 'application/json', 'apikey': key, 'Accept': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const SocialApiException('O servidor do Social demorou para responder.');
    } on SocketException {
      throw const SocialApiException('Sem conexão com a internet.');
    } on http.ClientException {
      throw const SocialApiException('Sem conexão com o servidor do Social.');
    } on HandshakeException {
      throw const SocialApiException('Falha na conexão segura com o Social.');
    }
    dynamic value;
    try {
      value = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw SocialApiException('O servidor Social respondeu em formato inválido (${response.statusCode}).', response.statusCode);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SocialApiException(value is Map ? '${value['error'] ?? 'Falha no Social.'}' : 'Falha no Social.', response.statusCode);
    }
    return value;
  }

  /// Chama uma ação. Renova a sessão uma vez se ela expirou.
  Future<dynamic> call(String action, [Map<String, dynamic> payload = const {}, Duration timeout = const Duration(seconds: 30)]) async {
    await _loadSession();
    if (!_sessionValid) await renewSession();
    try {
      return await _post({'action': action, 'session': _session, 'payload': payload}, timeout: timeout);
    } on SocialApiException catch (e) {
      if (e.status != 401) rethrow;
      await renewSession();
      return _post({'action': action, 'session': _session, 'payload': payload}, timeout: timeout);
    }
  }

  /// Ações de professor: o servidor confere no AVA a cada chamada.
  Future<dynamic> callWithMoodle(String action, [Map<String, dynamic> payload = const {}]) async {
    final token = await _moodleToken();
    if (token == null || Cfg.site.isEmpty) throw const SocialApiException('Entre no AVA para usar o Social.', 401);
    return _post({'action': action, 'site': Cfg.site, 'token': token, 'payload': payload}, timeout: const Duration(seconds: 90));
  }

  Future<void> upload(String uploadUrl, Uint8List bytes, {String contentType = 'application/octet-stream'}) async {
    final http.Response r;
    try {
      r = await _http
          .put(Uri.parse(uploadUrl), headers: {'Content-Type': contentType, 'apikey': key, 'x-upsert': 'false'}, body: bytes)
          .timeout(const Duration(minutes: 3));
    } on TimeoutException {
      throw const SocialApiException('O envio do arquivo demorou demais.');
    } on SocketException {
      throw const SocialApiException('Sem conexão com a internet.');
    }
    if (r.statusCode < 200 || r.statusCode >= 300) throw SocialApiException('Não foi possível enviar o arquivo (${r.statusCode}).', r.statusCode);
  }

  Future<Uint8List> download(String signedUrl) async {
    final r = await _http.get(Uri.parse(signedUrl)).timeout(const Duration(minutes: 2));
    if (r.statusCode != 200) throw SocialApiException('Não foi possível baixar o arquivo (${r.statusCode}).', r.statusCode);
    return r.bodyBytes;
  }
}
