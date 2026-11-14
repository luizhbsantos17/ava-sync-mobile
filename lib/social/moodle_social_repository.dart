import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../estado_app.dart';
import 'models.dart';
import 'repository.dart';
import 'supabase_crypto.dart';

/// Supabase Edge Function valida o token do AVA em toda requisição.
/// O app não cria uma segunda conta nem envia senha Moodle ao backend social.
class MoodleSocialRepository implements SocialRepository {
  static const _url = String.fromEnvironment('SOCIAL_SUPABASE_URL', defaultValue: 'https://zfyxjqdiffuuofwrgvat.supabase.co');
  static const _key = String.fromEnvironment('SOCIAL_SUPABASE_KEY', defaultValue: 'sb_publishable_Z2Dd3ItPRVW7DRq3vo8jlg_ftshQWRi');
  final http.Client _http;
  final _auth = StreamController<SocialAccount?>.broadcast();
  SocialAccount? _user;

  MoodleSocialRepository({http.Client? client}) : _http = client ?? http.Client();

  @override
  bool get configured => _url.isNotEmpty && _key.isNotEmpty;
  @override
  SocialAccount? get currentUser => _user;
  @override
  Stream<SocialAccount?> get authChanges => _auth.stream;

  Future<dynamic> _call(String action, [Map<String, dynamic> payload = const {}]) async {
    final token = app.token ?? await Cfg.token();
    if (token == null || Cfg.site.isEmpty) throw StateError('Entre no AVA para usar o Social.');
    final response = await _http
        .post(
          Uri.parse('$_url/functions/v1/social'),
          headers: {'Content-Type': 'application/json', 'apikey': _key, 'Accept': 'application/json'},
          body: jsonEncode({'action': action, 'site': Cfg.site, 'token': token, 'payload': payload}),
        )
        .timeout(const Duration(seconds: 45));
    dynamic value;
    try {
      value = jsonDecode(response.body);
    } catch (_) {
      throw Exception('O servidor Social respondeu em formato inválido (${response.statusCode}).');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(value is Map ? value['error'] ?? 'Falha ao validar a conta no AVA.' : 'Falha ao validar a conta no AVA.');
    }
    return value;
  }

  @override
  Future<SocialAccount?> identity() async {
    final result = Map<String, dynamic>.from(await _call('me') as Map);
    _user = SocialAccount(id: '${result['id']}', email: null);
    _auth.add(_user);
    return _user;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      Future.error(UnsupportedError('O Social usa a mesma conta já conectada no AVA.'));
  @override
  Future<void> signUp({required String email, required String password, required String username, required String displayName}) =>
      Future.error(UnsupportedError('Não é necessário criar outra conta: entre pelo AVA.'));
  @override
  Future<void> signOut() async {}

  @override
  Future<List<SocialConversation>> conversations() async {
    final rows = await _call('list') as List;
    return Future.wait(rows.map((raw) async {
      final row = Map<String, dynamic>.from(raw as Map);
      var preview = 'Grupo criado';
      final last = row['last_message'];
      if (last is Map) {
        try {
          final message = Map<String, dynamic>.from(last);
          preview = '${message['sender_name'] ?? 'Colega'}: ${await SupabaseSocialCrypto.decrypt('${row['id']}', message)}';
        } catch (_) {
          preview = 'Mensagem protegida · abra o convite do grupo para obter a chave';
        }
      }
      return SocialConversation(
        id: '${row['id']}',
        title: '${row['title']}',
        lastMessage: preview,
        createdAt: DateTime.parse('${row['created_at']}').toLocal(),
        isCourseGroup: row['group_kind'] == 'course',
        courseName: row['moodle_course_name'] as String?,
      );
    }));
  }

  @override
  Stream<List<SocialMessage>> messages(String conversationId) async* {
    while (true) {
      final rows = await _call('messages', {'conversationId': conversationId}) as List;
      final messages = <SocialMessage>[];
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        try {
          messages.add(SocialMessage(
            id: '${row['id']}',
            conversationId: conversationId,
            senderId: '${row['sender_id']}',
            senderName: '${row['sender_name'] ?? 'Colega'}',
            text: await SupabaseSocialCrypto.decrypt(conversationId, row),
            createdAt: DateTime.parse('${row['created_at']}').toLocal(),
          ));
        } catch (_) {
          // Sem a chave local, não exibimos ciphertext nem substituímos por texto ilegível.
        }
      }
      yield messages;
      await Future<void>.delayed(const Duration(seconds: 4));
    }
  }

  String _secret() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(32, (_) => random.nextInt(256), growable: false)).replaceAll('=', '');
  }

  Future<SocialInvite> _create({required String title, SocialCourse? course}) async {
    final key = await SupabaseSocialCrypto.newGroupKey();
    final encodedKey = base64Url.encode(key).replaceAll('=', '');
    final secret = _secret();
    final response = Map<String, dynamic>.from(await _call(
      course == null ? 'create_group' : 'create_course_group',
      {
        'title': title.trim(),
        'inviteSecret': secret,
        if (course != null) 'courseId': course.id,
      },
    ) as Map);
    final id = '${response['conversationId']}';
    await SupabaseSocialCrypto.saveGroupKey(id, key);
    return SocialInvite(
      conversationId: id,
      token: secret,
      conversationKey: encodedKey,
      membersCount: response['members'] is num ? (response['members'] as num).toInt() : null,
    );
  }

  @override
  Future<SocialInvite> createGroup(String title) => _create(title: title);

  @override
  Future<List<SocialCourse>> teacherCourses() async {
    final rows = await _call('teacher_courses') as List;
    return rows.map((row) => SocialCourse(
      id: (row as Map)['id'] as int,
      name: '${row['name']}',
    )).toList();
  }

  @override
  Future<SocialInvite> createCourseGroup({required String title, required SocialCourse course}) => _create(title: title, course: course);

  @override
  Future<void> joinGroup(String inviteCode) async {
    final invite = SupabaseSocialCrypto.parseInvite(inviteCode);
    final key = base64Url.decode(base64Url.normalize(invite.conversationKey));
    try {
      await _call('join_group', {'conversationId': invite.conversationId, 'inviteSecret': invite.token});
      await SupabaseSocialCrypto.saveGroupKey(invite.conversationId, key);
    } catch (_) {
      await SupabaseSocialCrypto.removeGroupKey(invite.conversationId);
      rethrow;
    }
  }

  @override
  Future<void> sendMessage(String conversationId, String text) async {
    final user = _user ?? await identity();
    if (user == null) throw StateError('Entre no AVA para enviar mensagens.');
    final encrypted = await SupabaseSocialCrypto.encrypt(conversationId, user.id, text.trim());
    await _call('send_message', {'conversationId': conversationId, ...encrypted});
  }
}
