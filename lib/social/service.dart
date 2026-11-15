import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../fundo.dart';
import 'api.dart';
import 'models.dart';
import 'supabase_crypto.dart';

/// Estado do Social compartilhado pelas telas: perfil, conversas, perfis em cache,
/// chaves e mídia. Atualiza sozinho com o app aberto e para em segundo plano.
class SocialService extends ChangeNotifier with WidgetsBindingObserver {
  SocialService._();
  static final SocialService instance = SocialService._();

  final SocialApi api = SocialApi();

  SocialProfile? me;
  List<SocialConversation> conversations = const [];
  int pendingFriends = 0;
  bool loading = false;
  bool ready = false;
  String? error;

  /// Canal aberto agora (não notifica mensagens dele).
  String? activeChannelId;

  final Map<String, SocialProfile> _profiles = {};
  Timer? _timer;
  bool _foreground = true;
  bool _observing = false;
  DateTime _lastKeyWork = DateTime.fromMillisecondsSinceEpoch(0);
  final Map<String, int> _lastUnread = {};
  bool _firstOverview = true;

  // ------------------------------------------------------------ ciclo de vida
  Future<void> start() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await Cfg.setSocialUsado(true);
    if (!ready) await refresh(showLoading: true);
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    if (fg) {
      unawaited(refresh());
      _schedule();
    } else {
      _timer?.cancel();
    }
    notifyListeners();
  }

  bool get foreground => _foreground;

  void _schedule() {
    _timer?.cancel();
    if (!_foreground) return;
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(refresh()));
  }

  // ------------------------------------------------------------ visão geral
  Future<void>? _refreshing;

  /// Atualiza a visão geral. Chamadas simultâneas esperam a mesma atualização.
  Future<void> refresh({bool showLoading = false}) => _refreshing ??= _refresh(showLoading).whenComplete(() => _refreshing = null);

  Future<void> _refresh(bool showLoading) async {
    loading = true;
    if (showLoading) notifyListeners();
    try {
      final r = Map<String, dynamic>.from(await api.call('overview') as Map);
      me = SocialProfile.fromJson(Map<String, dynamic>.from(r['me'] as Map));
      _profiles[me!.userKey] = me!;
      pendingFriends = (r['pendingFriends'] as num?)?.toInt() ?? 0;

      // chave pública deste aparelho
      final pub = await SupabaseSocialCrypto.devicePublicKey();
      if (me!.publicKey != pub) {
        final u = await api.call('update_profile', {'publicKey': pub});
        me = SocialProfile.fromJson(Map<String, dynamic>.from((u as Map)['me'] as Map));
      }
      for (final e in (r['envelopes'] as List? ?? const [])) {
        await SupabaseSocialCrypto.openEnvelope(Map<String, dynamic>.from(e as Map));
      }

      final list = <SocialConversation>[];
      for (final raw in (r['conversations'] as List? ?? const [])) {
        final j = Map<String, dynamic>.from(raw as Map);
        var c = SocialConversation.fromJson(j);
        if (c.peer != null) _profiles[c.peer!.userKey] = c.peer!;
        final hasKey = await SupabaseSocialCrypto.hasKey(c.id);
        c = c.copyWith(hasKey: hasKey, preview: await _preview(j['last_message'], c, hasKey));
        list.add(c);
      }
      list.sort((a, b) => b.sortAt.compareTo(a.sortAt));
      _notifyNew(list);
      conversations = list;
      error = null;
      ready = true;
      unawaited(Cfg.setSocialUltimaNotif(DateTime.now().toUtc().toIso8601String()));

      final requests = (r['keyRequests'] as List? ?? const []);
      if (requests.isNotEmpty && DateTime.now().difference(_lastKeyWork).inSeconds > 20) {
        _lastKeyWork = DateTime.now();
        unawaited(_shareKeys(requests));
      }
    } on SocialApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<String> _preview(dynamic last, SocialConversation c, bool hasKey) async {
    if (last is! Map) return c.direta ? 'Diga oi!' : 'Grupo criado';
    final row = Map<String, dynamic>.from(last)..['conversation_id'] = c.id;
    if (row['deleted_at'] != null) return 'Mensagem apagada';
    final mine = row['sender_id'] == me?.userKey;
    final who = mine ? 'Você' : (c.direta ? '' : '${row['sender_name'] ?? 'Colega'}');
    if (!hasKey) return 'Mensagem protegida · aguardando a chave';
    try {
      final content = await SupabaseSocialCrypto.decryptRow(row);
      var text = content.texto.replaceAll('\n', ' ');
      if (text.isEmpty && content.anexos.isNotEmpty) text = content.anexos.first.imagem ? '📷 Foto' : '📎 ${content.anexos.first.name}';
      return who.isEmpty ? text : '$who: $text';
    } catch (_) {
      return 'Mensagem protegida';
    }
  }

  /// Membros que trocaram de aparelho ou entraram sem convite recebem a chave.
  Future<void> _shareKeys(List<dynamic> requests) async {
    final envelopes = <Map<String, dynamic>>[];
    for (final raw in requests) {
      final r = Map<String, dynamic>.from(raw as Map);
      final e = await SupabaseSocialCrypto.sealFor(
        conversationId: '${r['conversation_id']}',
        userKey: '${r['user_key']}',
        recipientPublic: '${r['public_key']}',
      );
      if (e != null) envelopes.add(e);
    }
    for (var i = 0; i < envelopes.length; i += 50) {
      try {
        await api.call('put_envelopes', {'envelopes': envelopes.sublist(i, (i + 50).clamp(0, envelopes.length))});
      } catch (_) {}
    }
  }

  void _notifyNew(List<SocialConversation> list) {
    for (final c in list) {
      for (final ch in c.channels) {
        final before = _lastUnread[ch.id] ?? 0;
        _lastUnread[ch.id] = ch.unread;
        if (_firstOverview || c.muted || !Cfg.socialNotificacoes) continue;
        if (ch.unread > before && ch.id != activeChannelId) {
          final title = c.direta ? c.nome : '${c.nome} · #${ch.name}';
          unawaited(Notif.mostrarSocial(c.id.hashCode ^ ch.id.hashCode, title, c.preview, payload: 'social:${c.id}:${ch.id}'));
        }
      }
    }
    _firstOverview = false;
  }

  SocialConversation? conversation(String id) {
    for (final c in conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  int get totalUnread => conversations.where((c) => !c.muted).fold(0, (s, c) => s + c.unread);

  /// Zera o contador local de um canal ao abrir.
  void markChannelSeen(String conversationId, String channelId) {
    conversations = [
      for (final c in conversations)
        c.id == conversationId
            ? c.copyWith(channels: [for (final ch in c.channels) ch.id == channelId ? SocialChannel(id: ch.id, conversationId: ch.conversationId, name: ch.name, topic: ch.topic, position: ch.position, onlyAdmins: ch.onlyAdmins, lastAt: ch.lastAt) : ch])
            : c,
    ];
    _lastUnread[channelId] = 0;
    notifyListeners();
  }

  // ------------------------------------------------------------ perfis
  SocialProfile profile(String key) => _profiles[key] ?? SocialProfile.placeholder(key);
  SocialProfile? cachedProfile(String key) => _profiles[key];

  void mergeProfiles(dynamic raw) {
    if (raw is! Map) return;
    for (final e in raw.entries) {
      if (e.value is Map) _profiles['${e.key}'] = SocialProfile.fromJson(Map<String, dynamic>.from(e.value as Map));
    }
  }

  Future<SocialProfileView> profileView(String key) async {
    final v = SocialProfileView.fromJson(Map<String, dynamic>.from(await api.call('profile', {'userKey': key}) as Map));
    _profiles[key] = v.profile;
    return v;
  }

  Future<void> updateProfile(Map<String, dynamic> fields) async {
    final r = await api.call('update_profile', fields);
    me = SocialProfile.fromJson(Map<String, dynamic>.from((r as Map)['me'] as Map));
    _profiles[me!.userKey] = me!;
    notifyListeners();
  }

  Future<List<SocialProfile>> searchUsers(String query) async {
    final rows = await api.call('search_users', {'query': query}) as List;
    return [for (final r in rows) SocialProfile.fromJson(Map<String, dynamic>.from(r as Map))];
  }

  // ------------------------------------------------------------ amizades
  Future<({List<SocialFriend> friends, List<SocialProfile> blocked})> friends() async {
    final r = Map<String, dynamic>.from(await api.call('friends') as Map);
    final list = <SocialFriend>[];
    for (final raw in (r['friends'] as List)) {
      final j = Map<String, dynamic>.from(raw as Map);
      final p = SocialProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map));
      _profiles[p.userKey] = p;
      list.add(SocialFriend(profile: p, status: '${j['status']}', since: DateTime.tryParse('${j['since']}')?.toLocal()));
    }
    pendingFriends = list.where((f) => f.status == 'incoming').length;
    notifyListeners();
    return (friends: list, blocked: [for (final b in (r['blocked'] as List)) SocialProfile.fromJson(Map<String, dynamic>.from(b as Map))]);
  }

  Future<String> friendRequest({String? userKey, String? username}) async =>
      '${(await api.call('friend_request', {'userKey': ?userKey, 'username': ?username}) as Map)['status']}';
  Future<void> friendRespond(String userKey, bool accept) => api.call('friend_respond', {'userKey': userKey, 'accept': accept});
  Future<void> friendRemove(String userKey) => api.call('friend_remove', {'userKey': userKey});
  Future<void> block(String userKey) => api.call('block', {'userKey': userKey});
  Future<void> unblock(String userKey) => api.call('unblock', {'userKey': userKey});

  // ------------------------------------------------------------ conversas
  /// Abre (ou cria) a conversa direta e garante a chave dela.
  Future<String> openDm(String userKey) async {
    final r = Map<String, dynamic>.from(await api.call('open_dm', {'userKey': userKey}) as Map);
    final id = '${r['conversationId']}';
    if (!await SupabaseSocialCrypto.hasKey(id) && r['created'] == true) {
      await SupabaseSocialCrypto.saveGroupKey(id, await SupabaseSocialCrypto.newGroupKey());
      final peerKey = r['peer'] is Map ? (r['peer'] as Map)['public_key'] : null;
      if (peerKey is String) {
        final e = await SupabaseSocialCrypto.sealFor(conversationId: id, userKey: userKey, recipientPublic: peerKey);
        if (e != null) await api.call('put_envelopes', {'envelopes': [e]});
      }
    }
    await _refreshFor(id);
    return id;
  }

  /// Garante que a conversa recém-criada já está na lista.
  Future<void> _refreshFor(String id) async {
    await refresh();
    if (conversation(id) == null) await refresh();
  }

  Future<String> createGroup({required String title, String? description, Uint8List? icon}) async {
    final r = Map<String, dynamic>.from(await api.call('create_group', {'title': title, 'description': ?description}) as Map);
    final id = '${r['conversationId']}';
    await SupabaseSocialCrypto.saveGroupKey(id, await SupabaseSocialCrypto.newGroupKey());
    if (icon != null) await setGroupIcon(id, icon);
    await _refreshFor(id);
    return id;
  }

  Future<List<SocialCourse>> teacherCourses() async {
    final rows = await api.callWithMoodle('teacher_courses') as List;
    return [for (final r in rows) SocialCourse(id: ((r as Map)['id'] as num).toInt(), name: '${r['name']}')];
  }

  Future<({String id, int members})> createCourseGroup({required SocialCourse course, required String title, String? description}) async {
    final r = Map<String, dynamic>.from(await api.callWithMoodle('create_course_group', {'courseId': course.id, 'title': title, 'description': ?description}) as Map);
    final id = '${r['conversationId']}';
    await SupabaseSocialCrypto.saveGroupKey(id, await SupabaseSocialCrypto.newGroupKey());
    await refresh();
    _lastKeyWork = DateTime.fromMillisecondsSinceEpoch(0);
    return (id: id, members: (r['members'] as num?)?.toInt() ?? 0);
  }

  /// Cria um convite novo. [horas] nulo = não expira.
  Future<String> createInvite(String conversationId, {int? horas, int? usos}) async {
    final key = await SupabaseSocialCrypto.groupKey(conversationId);
    if (key == null) throw StateError('Este aparelho ainda não tem a chave do grupo.');
    final secret = SupabaseSocialCrypto.newSecret();
    await api.call('create_invite', {'conversationId': conversationId, 'inviteSecret': secret, 'expiresHours': ?horas, 'maxUses': ?usos});
    return SupabaseSocialCrypto.makeInvite(conversationId: conversationId, token: secret, conversationKey: SupabaseSocialCrypto.b64(key));
  }

  Future<String> joinGroup(String code) async {
    final invite = SupabaseSocialCrypto.parseInvite(code);
    final key = SupabaseSocialCrypto.unb64(invite.conversationKey);
    final r = await api.call('join_group', {'conversationId': invite.conversationId, 'inviteSecret': invite.token});
    await SupabaseSocialCrypto.saveGroupKey(invite.conversationId, key);
    await refresh();
    return '${(r as Map)['title'] ?? 'Grupo'}';
  }

  Future<SocialGroupInfo> groupInfo(String conversationId) async {
    final info = SocialGroupInfo.fromJson(Map<String, dynamic>.from(await api.call('group_info', {'conversationId': conversationId}) as Map));
    for (final m in info.members) {
      _profiles[m.userKey] = m.profile;
    }
    return info;
  }

  Future<void> groupAction(String action, Map<String, dynamic> payload, {bool reload = true}) async {
    await api.call(action, payload);
    if (reload) await refresh();
  }

  Future<void> leaveGroup(String conversationId) async {
    await api.call('leave_group', {'conversationId': conversationId});
    await SupabaseSocialCrypto.removeGroupKey(conversationId);
    await refresh();
  }

  Future<void> deleteGroup(String conversationId) async {
    await api.call('delete_group', {'conversationId': conversationId});
    await SupabaseSocialCrypto.removeGroupKey(conversationId);
    await refresh();
  }

  Future<void> setMuted(String conversationId, bool muted) async {
    conversations = [for (final c in conversations) c.id == conversationId ? c.copyWith(muted: muted) : c];
    notifyListeners();
    await api.call('set_member_prefs', {'conversationId': conversationId, 'muted': muted});
  }

  // ------------------------------------------------------------ imagens e arquivos
  final Map<String, ({String url, DateTime at})> _signed = {};
  final LinkedHashMap<String, Uint8List> _bytes = LinkedHashMap();
  int _bytesTotal = 0;
  final Map<String, Future<Uint8List?>> _loading = {};
  static const _cacheMax = 60 * 1024 * 1024;

  void _remember(String path, Uint8List data) {
    _bytes.remove(path);
    _bytes[path] = data;
    _bytesTotal += data.length;
    while (_bytesTotal > _cacheMax && _bytes.length > 1) {
      final first = _bytes.keys.first;
      _bytesTotal -= _bytes.remove(first)!.length;
    }
  }

  Uint8List? cachedBytes(String path) => _bytes[path];

  Future<Map<String, String>> _urls(List<String> paths) async {
    final now = DateTime.now();
    final missing = [for (final p in paths) if (_signed[p] == null || now.difference(_signed[p]!.at).inMinutes > 50) p];
    if (missing.isNotEmpty) {
      final r = Map<String, dynamic>.from(await api.call('download_urls', {'paths': missing}) as Map);
      for (final e in r.entries) {
        _signed[e.key] = (url: '${e.value}', at: now);
      }
    }
    return {for (final p in paths) if (_signed[p] != null) p: _signed[p]!.url};
  }

  /// Foto de perfil ou ícone de grupo (sem cifra; acesso só com URL assinada).
  Future<Uint8List?> image(String path) => _fetch(path, null);

  /// Anexo cifrado com a chave da conversa.
  Future<Uint8List?> attachment(String conversationId, String path) => _fetch(path, conversationId);

  Future<Uint8List?> _fetch(String path, String? conversationId) {
    final cached = _bytes[path];
    if (cached != null) return Future.value(cached);
    return _loading[path] ??= () async {
      try {
        final url = (await _urls([path]))[path];
        if (url == null) return null;
        var data = await api.download(url);
        if (conversationId != null) data = await SupabaseSocialCrypto.decryptFile(conversationId, path, data);
        _remember(path, data);
        return data;
      } catch (_) {
        return null;
      } finally {
        unawaited(Future<void>.delayed(const Duration(seconds: 1), () => _loading.remove(path)));
      }
    }();
  }

  Future<String> _uploadRaw(String kind, Uint8List data, {String? conversationId, String contentType = 'application/octet-stream'}) async {
    final r = Map<String, dynamic>.from(await api.call('upload_url', {'kind': kind, 'conversationId': ?conversationId}) as Map);
    final path = '${r['path']}';
    await api.upload('${r['uploadUrl']}', data, contentType: contentType);
    _remember(path, data);
    return path;
  }

  Future<void> setAvatar(Uint8List? original) async {
    if (original == null) {
      await updateProfile({'avatarPath': null});
      return;
    }
    final png = await squarePng(original, 320);
    final path = await _uploadRaw('avatar', png, contentType: 'image/png');
    await updateProfile({'avatarPath': path});
  }

  Future<void> setGroupIcon(String conversationId, Uint8List? original) async {
    if (original == null) {
      await groupAction('update_group', {'conversationId': conversationId, 'iconPath': null});
      return;
    }
    final png = await squarePng(original, 320);
    final path = await _uploadRaw('icon', png, conversationId: conversationId, contentType: 'image/png');
    await groupAction('update_group', {'conversationId': conversationId, 'iconPath': path});
  }

  /// Cifra e envia um anexo. Imagens grandes são reduzidas para 1280 px.
  Future<SocialAttachment> uploadAttachment(String conversationId, String name, Uint8List bytes) async {
    var data = bytes;
    var mime = mimeOf(name);
    int? w, h;
    if (mime.startsWith('image/') && mime != 'image/gif') {
      try {
        final r = await shrinkImage(bytes, 1280);
        data = r.bytes;
        w = r.width;
        h = r.height;
        if (r.reencoded) {
          mime = 'image/png';
          name = '${name.replaceAll(RegExp(r'\.[^.]+$'), '')}.png';
        }
      } catch (_) {}
    }
    if (data.length > 8 * 1024 * 1024) throw const SocialApiException('O arquivo passa de 8 MB.');
    final r = Map<String, dynamic>.from(await api.call('upload_url', {'kind': 'att', 'conversationId': conversationId}) as Map);
    final path = '${r['path']}';
    final sealed = await SupabaseSocialCrypto.encryptFile(conversationId, path, data);
    await api.upload('${r['uploadUrl']}', sealed);
    _remember(path, data);
    return SocialAttachment(path: path, name: name, mime: mime, size: data.length, width: w, height: h);
  }

  // ------------------------------------------------------------ rascunhos
  String draft(String channelId) {
    try {
      return '${(jsonDecode(Cfg.socialRascunhos) as Map)[channelId] ?? ''}';
    } catch (_) {
      return '';
    }
  }

  Future<void> saveDraft(String channelId, String text) async {
    Map<String, dynamic> map;
    try {
      map = Map<String, dynamic>.from(jsonDecode(Cfg.socialRascunhos) as Map);
    } catch (_) {
      map = {};
    }
    if (text.trim().isEmpty) {
      map.remove(channelId);
    } else {
      map[channelId] = text;
    }
    await Cfg.setSocialRascunhos(jsonEncode(map));
  }

  Future<void> useEmoji(String emoji) async {
    final list = [emoji, ...Cfg.socialEmojisRecentes.where((e) => e != emoji)];
    await Cfg.setSocialEmojisRecentes(list);
  }
}

// ------------------------------------------------------------ utilidades de imagem
String mimeOf(String name) {
  final ext = name.toLowerCase().split('.').last;
  return switch (ext) {
    'png' => 'image/png',
    'jpg' || 'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'zip' => 'application/zip',
    'doc' => 'application/msword',
    'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'mp3' => 'audio/mpeg',
    'mp4' => 'video/mp4',
    _ => 'application/octet-stream',
  };
}

/// Recorta no centro e reduz para um quadrado de [size] px (fotos de perfil e ícones).
Future<Uint8List> squarePng(Uint8List bytes, int size) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final side = img.width < img.height ? img.width : img.height;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH((img.width - side) / 2, (img.height - side) / 2, side.toDouble(), side.toDouble()),
    ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    ui.Paint()..filterQuality = ui.FilterQuality.high,
  );
  final out = await recorder.endRecording().toImage(size, size);
  final data = await out.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  out.dispose();
  return data!.buffer.asUint8List();
}

/// Reduz a imagem se passar de [max] px. JPEG pequeno fica como está.
Future<({Uint8List bytes, int width, int height, bool reencoded})> shrinkImage(Uint8List bytes, int max) async {
  final probe = await ui.instantiateImageCodec(bytes);
  final first = (await probe.getNextFrame()).image;
  final w = first.width, h = first.height;
  first.dispose();
  if (w <= max && h <= max && bytes.length < 2 * 1024 * 1024) return (bytes: bytes, width: w, height: h, reencoded: false);
  final scale = max / (w > h ? w : h);
  final tw = scale < 1 ? (w * scale).round() : w;
  final th = scale < 1 ? (h * scale).round() : h;
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: tw, targetHeight: th);
  final img = (await codec.getNextFrame()).image;
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return (bytes: data!.buffer.asUint8List(), width: tw, height: th, reencoded: true);
}
