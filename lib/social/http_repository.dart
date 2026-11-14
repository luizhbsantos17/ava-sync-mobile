import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

import 'models.dart';
import 'repository.dart';
import 'supabase_crypto.dart';

/// Adaptador para uma API própria no PC. Usa polling leve para receber mensagens;
/// o contrato deixa a interface desacoplada deste transporte.
class HttpSocialRepository implements SocialRepository {
  static const _storage = FlutterSecureStorage();
  static const _tokenStorageKey = 'social_pc_server_token';
  final Uri _baseUri;
  final http.Client _http;
  final _auth = StreamController<SocialAccount?>.broadcast();
  String? _token;
  SocialAccount? _user;

  HttpSocialRepository(String baseUrl, {http.Client? client, String tlsCertificateBase64 = ''})
      : _baseUri = Uri.parse(baseUrl.endsWith('/') ? baseUrl : '$baseUrl/'),
        _http = client ?? _createClient(tlsCertificateBase64);

  static http.Client _createClient(String certificateBase64) {
    if (certificateBase64.isEmpty) return http.Client();
    final context = SecurityContext(withTrustedRoots: false)
      ..setTrustedCertificatesBytes(base64.decode(certificateBase64));
    return IOClient(HttpClient(context: context));
  }

  @override
  bool get configured => true;
  @override
  SocialAccount? get currentUser => _user;
  @override
  Stream<SocialAccount?> get authChanges => _auth.stream;

  @override
  Future<SocialAccount?> identity() async => currentUser;

  Future<void> restoreSession() async {
    _token = await _storage.read(key: _tokenStorageKey);
    if (_token == null) return;
    try {
      final response = await _request('GET', 'api/auth/me');
      _user = _account(Map<String, dynamic>.from(response['user'] as Map));
      _auth.add(_user);
    } catch (_) {
      await _storage.delete(key: _tokenStorageKey);
      _token = null;
      _user = null;
    }
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    final response = await _request('POST', 'api/auth/signin', body: {'email': email.trim(), 'password': password}, auth: false);
    await _acceptSession(response);
  }

  @override
  Future<void> signUp({required String email, required String password, required String username, required String displayName}) async {
    final response = await _request('POST', 'api/auth/signup', body: {
      'email': email.trim(),
      'password': password,
      'username': username.trim().toLowerCase(),
      'displayName': displayName.trim(),
    }, auth: false);
    await _acceptSession(response);
  }

  Future<void> _acceptSession(Map<String, dynamic> response) async {
    _token = '${response['token']}';
    await _storage.write(key: _tokenStorageKey, value: _token);
    _user = _account(Map<String, dynamic>.from(response['user'] as Map));
    _auth.add(_user);
  }

  SocialAccount _account(Map<String, dynamic> row) => SocialAccount(id: '${row['id']}', email: row['email'] as String?);

  @override
  Future<void> signOut() async {
    try { await _request('POST', 'api/auth/signout'); } catch (_) {}
    await _storage.delete(key: _tokenStorageKey);
    _token = null;
    _user = null;
    _auth.add(null);
  }

  Future<dynamic> _request(String method, String path, {Object? body, bool auth = true, Map<String, String>? query}) async {
    final uri = _baseUri.resolve(path).replace(queryParameters: query);
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json; charset=utf-8';
    if (auth && _token != null) headers['Authorization'] = 'Bearer $_token';
    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await _http.send(request).timeout(const Duration(seconds: 15));
    final response = await http.Response.fromStream(streamed);
    dynamic decoded;
    try { decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body); }
    catch (_) { throw Exception('Servidor respondeu em formato inválido (${response.statusCode}).'); }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = decoded is Map ? decoded['error'] : null;
      throw Exception(message ?? 'Falha ao falar com o servidor (${response.statusCode}).');
    }
    return decoded;
  }

  @override
  Future<List<SocialConversation>> conversations() async {
    final response = await _request('GET', 'api/conversations') as List;
    return Future.wait(response.map((raw) async {
      final row = Map<String, dynamic>.from(raw as Map);
      var preview = 'Grupo criado';
      final last = row['last_message'];
      if (last is Map) {
        try {
          final message = Map<String, dynamic>.from(last);
          final text = await SupabaseSocialCrypto.decrypt('${row['id']}', message);
          preview = '${message['sender_name'] ?? 'Colega'}: $text';
        } catch (_) {
          preview = 'Mensagem protegida';
        }
      }
      return SocialConversation(
        id: '${row['id']}',
        title: '${row['title']}',
        lastMessage: preview,
        createdAt: DateTime.parse('${row['created_at']}').toLocal(),
      );
    }));
  }

  @override
  Stream<List<SocialMessage>> messages(String conversationId) async* {
    final known = <String, SocialMessage>{};
    String? after;
    Future<List<SocialMessage>> fetch() async {
      final rows = await _request('GET', 'api/conversations/$conversationId/messages', query: after == null ? null : {'after': after!}) as List;
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = '${row['id']}';
        if (known.containsKey(id)) continue;
        known[id] = SocialMessage(
          id: id,
          conversationId: conversationId,
          senderId: '${row['sender_id']}',
          senderName: '${row['sender_name'] ?? 'Colega'}',
          text: await SupabaseSocialCrypto.decrypt(conversationId, row),
          createdAt: DateTime.parse('${row['created_at']}').toLocal(),
        );
      }
      if (known.isNotEmpty) {
        final latest = known.values.map((m) => m.createdAt.toUtc()).reduce((a, b) => a.isAfter(b) ? a : b);
        after = latest.subtract(const Duration(milliseconds: 1)).toIso8601String();
      }
      final result = known.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return result;
    }

    yield await fetch();
    await for (final _ in Stream<int>.periodic(const Duration(seconds: 3), (count) => count)) {
      yield await fetch();
    }
  }

  @override
  Future<SocialInvite> createGroup(String title) async {
    if (_user == null) throw StateError('Entre na sua conta Social primeiro.');
    final key = await SupabaseSocialCrypto.newGroupKey();
    final encodedKey = base64Url.encode(key).replaceAll('=', '');
    final tokenBytes = List<int>.generate(32, (_) => Random.secure().nextInt(256), growable: false);
    final token = base64Url.encode(tokenBytes).replaceAll('=', '');
    final response = await _request('POST', 'api/conversations', body: {'title': title.trim(), 'inviteSecret': token});
    final id = '${response['id']}';
    await SupabaseSocialCrypto.saveGroupKey(id, key);
    return SocialInvite(conversationId: id, token: token, conversationKey: encodedKey);
  }

  @override
  Future<List<SocialCourse>> teacherCourses() async => throw UnsupportedError('Grupos de matéria requerem o backend Supabase.');

  @override
  Future<SocialInvite> createCourseGroup({required String title, required SocialCourse course}) async =>
      throw UnsupportedError('Grupos de matéria requerem o backend Supabase.');

  @override
  Future<void> joinGroup(String inviteCode) async {
    final invite = SupabaseSocialCrypto.parseInvite(inviteCode);
    final key = base64Url.decode(base64Url.normalize(invite.conversationKey));
    await SupabaseSocialCrypto.saveGroupKey(invite.conversationId, key);
    try {
      await _request('POST', 'api/conversations/join', body: {'conversationId': invite.conversationId, 'inviteSecret': invite.token});
    } catch (_) {
      await SupabaseSocialCrypto.removeGroupKey(invite.conversationId);
      rethrow;
    }
  }

  @override
  Future<void> sendMessage(String conversationId, String text) async {
    if (_user == null) throw StateError('Entre na sua conta Social primeiro.');
    final encrypted = await SupabaseSocialCrypto.encrypt(conversationId, _user!.id, text.trim());
    await _request('POST', 'api/conversations/$conversationId/messages', body: encrypted);
  }
}
