// Modelos do Social. Tudo que vem do servidor é convertido aqui; o texto das
// mensagens chega cifrado e é aberto em `SocialService`.

DateTime? _date(dynamic v) => v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
String? _str(dynamic v) => v is String && v.isNotEmpty ? v : null;

/// online, ocupado, ausente ou offline (o "invisível" aparece como offline para os outros).
enum Presenca {
  online('Disponível'),
  busy('Ocupado'),
  away('Ausente'),
  invisible('Invisível'),
  offline('Offline');

  final String rotulo;
  const Presenca(this.rotulo);

  static Presenca de(String? v) => Presenca.values.firstWhere((p) => p.name == v, orElse: () => Presenca.offline);
}

class SocialProfile {
  final String userKey;
  final String username;
  final String displayName;
  final String? bio;
  final String? avatarPath;
  final int? bannerColor;
  final String? customStatus;
  final String? customEmoji;
  final String? publicKey;
  final Presenca presence;

  /// Só vem preenchido no próprio perfil (o status escolhido, inclusive invisível).
  final Presenca? status;
  final DateTime? lastSeen;
  final DateTime? createdAt;

  const SocialProfile({
    required this.userKey,
    required this.username,
    required this.displayName,
    this.bio,
    this.avatarPath,
    this.bannerColor,
    this.customStatus,
    this.customEmoji,
    this.publicKey,
    this.presence = Presenca.offline,
    this.status,
    this.lastSeen,
    this.createdAt,
  });

  factory SocialProfile.fromJson(Map<String, dynamic> j) => SocialProfile(
        userKey: '${j['user_key']}',
        username: '${j['username'] ?? ''}',
        displayName: '${j['display_name'] ?? 'Colega'}',
        bio: _str(j['bio']),
        avatarPath: _str(j['avatar_path']),
        bannerColor: j['banner_color'] is num ? (j['banner_color'] as num).toInt() : null,
        customStatus: _str(j['custom_status']),
        customEmoji: _str(j['custom_emoji']),
        publicKey: _str(j['public_key']),
        presence: Presenca.de(j['presence'] as String?),
        status: j['status'] == null ? null : Presenca.de(j['status'] as String?),
        lastSeen: _date(j['last_seen']),
        createdAt: _date(j['created_at']),
      );

  static SocialProfile placeholder(String key) => SocialProfile(userKey: key, username: '', displayName: 'Colega');

  bool get online => presence != Presenca.offline;

  String get statusLinha {
    final custom = [customEmoji, customStatus].whereType<String>().join(' ');
    return custom.isNotEmpty ? custom : presence.rotulo;
  }
}

enum TipoConversa { grupo, materia, direta }

TipoConversa _tipo(String? v) => switch (v) { 'course' => TipoConversa.materia, 'dm' => TipoConversa.direta, _ => TipoConversa.grupo };

enum Cargo {
  owner('Dono'),
  admin('Admin'),
  member('Membro');

  final String rotulo;
  const Cargo(this.rotulo);
  static Cargo de(String? v) => Cargo.values.firstWhere((c) => c.name == v, orElse: () => Cargo.member);
  int get nivel => switch (this) { Cargo.owner => 3, Cargo.admin => 2, Cargo.member => 1 };
  bool get gerencia => nivel >= 2;
}

class SocialChannel {
  final String id;
  final String conversationId;
  final String name;
  final String? topic;
  final int position;
  final bool onlyAdmins;
  final int unread;
  final int mentions;
  final DateTime? lastAt;

  const SocialChannel({
    required this.id,
    required this.conversationId,
    required this.name,
    this.topic,
    this.position = 0,
    this.onlyAdmins = false,
    this.unread = 0,
    this.mentions = 0,
    this.lastAt,
  });

  factory SocialChannel.fromJson(Map<String, dynamic> j, String conversationId) => SocialChannel(
        id: '${j['id']}',
        conversationId: '${j['conversation_id'] ?? conversationId}',
        name: '${j['name']}',
        topic: _str(j['topic']),
        position: _int(j['position']),
        onlyAdmins: j['only_admins'] == true,
        unread: _int(j['unread']),
        mentions: _int(j['mentions']),
        lastAt: _date(j['last_at']),
      );
}

class SocialConversation {
  final String id;
  final String title;
  final String? description;
  final String? iconPath;
  final TipoConversa tipo;
  final String? courseName;
  final Cargo role;
  final bool muted;
  final String? nickname;
  final int memberCount;
  final List<SocialChannel> channels;
  final SocialProfile? peer;
  final DateTime createdAt;
  final DateTime sortAt;

  /// Prévia já decifrada ("Ana: oi") ou aviso quando falta a chave.
  final String preview;
  final DateTime? lastAt;
  final bool hasKey;

  const SocialConversation({
    required this.id,
    required this.title,
    this.description,
    this.iconPath,
    this.tipo = TipoConversa.grupo,
    this.courseName,
    this.role = Cargo.member,
    this.muted = false,
    this.nickname,
    this.memberCount = 1,
    this.channels = const [],
    this.peer,
    required this.createdAt,
    required this.sortAt,
    this.preview = '',
    this.lastAt,
    this.hasKey = true,
  });

  bool get direta => tipo == TipoConversa.direta;
  String get nome => direta ? (peer?.displayName ?? 'Conversa') : title;
  int get unread => channels.fold(0, (s, c) => s + c.unread);
  int get mentions => channels.fold(0, (s, c) => s + c.mentions);
  SocialChannel? get primeiroCanal => channels.isEmpty ? null : channels.first;

  SocialConversation copyWith({String? preview, bool? hasKey, List<SocialChannel>? channels, bool? muted}) => SocialConversation(
        id: id,
        title: title,
        description: description,
        iconPath: iconPath,
        tipo: tipo,
        courseName: courseName,
        role: role,
        muted: muted ?? this.muted,
        nickname: nickname,
        memberCount: memberCount,
        channels: channels ?? this.channels,
        peer: peer,
        createdAt: createdAt,
        sortAt: sortAt,
        preview: preview ?? this.preview,
        lastAt: lastAt,
        hasKey: hasKey ?? this.hasKey,
      );

  factory SocialConversation.fromJson(Map<String, dynamic> j) {
    final id = '${j['id']}';
    final channels = (j['channels'] as List? ?? const [])
        .map((c) => SocialChannel.fromJson(Map<String, dynamic>.from(c as Map), id))
        .toList()
      ..sort((a, b) => a.position != b.position ? a.position.compareTo(b.position) : a.name.compareTo(b.name));
    final created = _date(j['created_at']) ?? DateTime.now();
    final last = j['last_message'] is Map ? _date((j['last_message'] as Map)['created_at']) : null;
    return SocialConversation(
      id: id,
      title: '${j['title'] ?? 'Grupo'}',
      description: _str(j['description']),
      iconPath: _str(j['icon_path']),
      tipo: _tipo(j['group_kind'] as String?),
      courseName: _str(j['moodle_course_name']),
      role: Cargo.de(j['role'] as String?),
      muted: j['muted'] == true,
      nickname: _str(j['nickname']),
      memberCount: _int(j['member_count']),
      channels: channels,
      peer: j['peer'] is Map ? SocialProfile.fromJson(Map<String, dynamic>.from(j['peer'] as Map)) : null,
      createdAt: created,
      sortAt: _date(j['sort_at']) ?? last ?? created,
      lastAt: last,
    );
  }
}

class SocialMember {
  final String userKey;
  final Cargo role;
  final String? nickname;
  final DateTime? joinedAt;
  final SocialProfile profile;

  const SocialMember({required this.userKey, required this.role, this.nickname, this.joinedAt, required this.profile});

  String get nome => nickname ?? profile.displayName;

  factory SocialMember.fromJson(Map<String, dynamic> j) {
    final key = '${j['user_key']}';
    return SocialMember(
      userKey: key,
      role: Cargo.de(j['role'] as String?),
      nickname: _str(j['nickname']),
      joinedAt: _date(j['joined_at']),
      profile: j['profile'] is Map ? SocialProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map)) : SocialProfile.placeholder(key),
    );
  }
}

class SocialGroupInfo {
  final SocialConversation conversation;
  final Cargo myRole;
  final bool muted;
  final String? nickname;
  final List<SocialChannel> channels;
  final List<SocialMember> members;
  final List<SocialMember> bans;
  final int activeInvites;

  const SocialGroupInfo({
    required this.conversation,
    required this.myRole,
    required this.muted,
    this.nickname,
    required this.channels,
    required this.members,
    required this.bans,
    required this.activeInvites,
  });

  SocialMember? member(String key) {
    for (final m in members) {
      if (m.userKey == key) return m;
    }
    return null;
  }

  factory SocialGroupInfo.fromJson(Map<String, dynamic> j) {
    final conv = Map<String, dynamic>.from(j['conversation'] as Map);
    final id = '${conv['id']}';
    final channels = (j['channels'] as List).map((c) => SocialChannel.fromJson(Map<String, dynamic>.from(c as Map), id)).toList();
    return SocialGroupInfo(
      conversation: SocialConversation.fromJson({...conv, 'role': j['myRole'], 'muted': j['muted'], 'channels': j['channels'], 'member_count': (j['members'] as List).length}),
      myRole: Cargo.de(j['myRole'] as String?),
      muted: j['muted'] == true,
      nickname: _str(j['nickname']),
      channels: channels,
      members: (j['members'] as List).map((m) => SocialMember.fromJson(Map<String, dynamic>.from(m as Map))).toList(),
      bans: (j['bans'] as List? ?? const []).map((m) => SocialMember.fromJson({...Map<String, dynamic>.from(m as Map), 'role': 'member'})).toList(),
      activeInvites: _int(j['activeInvites']),
    );
  }
}

/// Anexo dentro do conteúdo cifrado da mensagem.
class SocialAttachment {
  final String path;
  final String name;
  final String mime;
  final int size;
  final int? width;
  final int? height;

  const SocialAttachment({required this.path, required this.name, required this.mime, required this.size, this.width, this.height});

  bool get imagem => mime.startsWith('image/');

  Map<String, dynamic> toJson() => {'p': path, 'n': name, 'm': mime, 's': size, if (width != null) 'w': width, if (height != null) 'h': height};

  static SocialAttachment? fromJson(dynamic j) {
    if (j is! Map || j['p'] is! String) return null;
    return SocialAttachment(
      path: j['p'] as String,
      name: '${j['n'] ?? 'arquivo'}',
      mime: '${j['m'] ?? 'application/octet-stream'}',
      size: _int(j['s']),
      width: j['w'] is num ? (j['w'] as num).toInt() : null,
      height: j['h'] is num ? (j['h'] as num).toInt() : null,
    );
  }
}

class SocialReaction {
  final String emoji;
  final List<String> users;
  const SocialReaction(this.emoji, this.users);
}

enum EstadoEnvio { enviado, enviando, falhou }

class SocialMessage {
  final String id;
  final String conversationId;
  final String channelId;
  final String senderId;
  final String text;
  final List<SocialAttachment> attachments;
  final String? replyTo;
  final List<String> mentions;
  final DateTime createdAt;
  final DateTime? editedAt;
  final bool deleted;
  final DateTime? pinnedAt;
  final List<SocialReaction> reactions;
  final int rev;

  /// Não foi possível abrir (sem a chave da conversa).
  final bool locked;
  final EstadoEnvio estado;

  /// Id temporário de mensagem enviada daqui e ainda sem confirmação.
  final String? localId;

  const SocialMessage({
    required this.id,
    required this.conversationId,
    required this.channelId,
    required this.senderId,
    required this.text,
    this.attachments = const [],
    this.replyTo,
    this.mentions = const [],
    required this.createdAt,
    this.editedAt,
    this.deleted = false,
    this.pinnedAt,
    this.reactions = const [],
    this.rev = 0,
    this.locked = false,
    this.estado = EstadoEnvio.enviado,
    this.localId,
  });

  SocialMessage copyWith({EstadoEnvio? estado, List<SocialReaction>? reactions, String? text, DateTime? editedAt, bool? deleted, DateTime? pinnedAt, bool clearPin = false}) => SocialMessage(
        id: id,
        conversationId: conversationId,
        channelId: channelId,
        senderId: senderId,
        text: text ?? this.text,
        attachments: attachments,
        replyTo: replyTo,
        mentions: mentions,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        deleted: deleted ?? this.deleted,
        pinnedAt: clearPin ? null : pinnedAt ?? this.pinnedAt,
        reactions: reactions ?? this.reactions,
        rev: rev,
        locked: locked,
        estado: estado ?? this.estado,
        localId: localId,
      );

  static List<SocialReaction> reactionsFrom(dynamic raw) {
    final map = <String, List<String>>{};
    for (final r in (raw as List? ?? const [])) {
      if (r is! Map) continue;
      map.putIfAbsent('${r['emoji']}', () => []).add('${r['user_key']}');
    }
    return [for (final e in map.entries) SocialReaction(e.key, e.value)];
  }
}

class SocialFriend {
  final SocialProfile profile;

  /// friends, incoming (recebido) ou outgoing (enviado).
  final String status;
  final DateTime? since;
  const SocialFriend({required this.profile, required this.status, this.since});
}

class SocialProfileView {
  final SocialProfile profile;
  final String friendship;
  final DateTime? friendsSince;
  final bool blockedByMe;
  final bool blockedMe;
  final List<({String id, String title, String? iconPath})> mutualGroups;

  const SocialProfileView({
    required this.profile,
    required this.friendship,
    this.friendsSince,
    this.blockedByMe = false,
    this.blockedMe = false,
    this.mutualGroups = const [],
  });

  factory SocialProfileView.fromJson(Map<String, dynamic> j) => SocialProfileView(
        profile: SocialProfile.fromJson(Map<String, dynamic>.from(j['profile'] as Map)),
        friendship: '${j['friendship'] ?? 'none'}',
        friendsSince: _date(j['friendsSince']),
        blockedByMe: j['blockedByMe'] == true,
        blockedMe: j['blockedMe'] == true,
        mutualGroups: [
          for (final g in (j['mutualGroups'] as List? ?? const []))
            (id: '${(g as Map)['id']}', title: '${g['title']}', iconPath: _str(g['icon_path'])),
        ],
      );
}

class SocialCourse {
  final int id;
  final String name;
  const SocialCourse({required this.id, required this.name});
}

class SocialInvite {
  final String conversationId;
  final String token;
  final String conversationKey;
  final int? membersCount;

  const SocialInvite({required this.conversationId, required this.token, required this.conversationKey, this.membersCount});
}
