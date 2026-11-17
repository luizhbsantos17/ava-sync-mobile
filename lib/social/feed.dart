import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'formatacao.dart';
import 'models.dart';
import 'service.dart';
import 'supabase_crypto.dart';

/// Mensagens de um canal, quase em tempo real.
///
/// Usa "long polling": o servidor segura a chamada até chegar mensagem, edição,
/// reação ou alguém começar a digitar (até 20 s). Em segundo plano o laço para;
/// ao voltar, retoma de onde parou. Erro de rede nunca fecha o canal: tenta de
/// novo com espera crescente e mostra "Reconectando".
class ChannelFeed extends ChangeNotifier {
  final SocialService service;
  final SocialConversation conversation;
  final SocialChannel channel;

  ChannelFeed(this.service, this.conversation, this.channel);

  SocialApi get _api => service.api;
  String get _me => service.me?.userKey ?? '';

  final Map<String, SocialMessage> _byId = {};
  List<SocialMessage> messages = const [];
  List<String> typing = const [];
  bool loading = true;
  bool loadingOlder = false;
  bool hasMore = false;
  bool offline = false;
  String? error;

  /// Mensagem mais antiga não lida quando o canal abriu (para a linha "Novas").
  DateTime? unreadSince;

  int _rev = 0;
  int _generation = 0;
  bool _disposed = false;
  bool _running = false;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastRead = DateTime.fromMillisecondsSinceEpoch(0);
  int _localSeq = 0;

  // ------------------------------------------------------------ abrir e laço
  Future<void> open() async {
    try {
      final r = Map<String, dynamic>.from(await _api.call('messages', {'channelId': channel.id, 'limit': 50}) as Map);
      service.mergeProfiles(r['profiles']);
      await _absorb(r['messages'], r['refs']);
      _rev = (r['rev'] as num?)?.toInt() ?? 0;
      hasMore = r['hasMore'] == true;
      typing = [for (final t in (r['typing'] as List? ?? const [])) '$t'];
      if (channel.unread > 0) {
        final others = messages.where((m) => m.senderId != _me).toList();
        if (others.length >= channel.unread) unreadSince = others[others.length - channel.unread].createdAt;
      }
      error = null;
    } on SocialApiException catch (e) {
      error = e.message;
    } catch (e) {
      error = '$e';
    } finally {
      loading = false;
      _notify();
    }
    markRead(force: true);
    resume();
  }

  /// Retoma o laço (chamado ao abrir e ao voltar do segundo plano).
  void resume() {
    if (_disposed || _running) return;
    final gen = ++_generation;
    unawaited(_loop(gen));
  }

  /// Para o laço sem perder as mensagens (segundo plano).
  void pause() {
    _generation++;
    _running = false;
  }

  Future<void> _loop(int gen) async {
    _running = true;
    var failures = 0;
    var first = true;
    while (!_disposed && gen == _generation) {
      try {
        final r = Map<String, dynamic>.from(await _api.call(
          'poll',
          {'channelId': channel.id, 'rev': _rev, 'typing': typing, 'wait': !first},
          const Duration(seconds: 35),
        ) as Map);
        if (_disposed || gen != _generation) break;
        first = false;
        service.mergeProfiles(r['profiles']);
        final changed = await _absorb(r['messages'], r['refs']);
        _rev = max(_rev, (r['rev'] as num?)?.toInt() ?? _rev);
        final t = [for (final x in (r['typing'] as List? ?? const [])) '$x'];
        final typingChanged = t.join(',') != typing.join(',');
        typing = t;
        final wasOffline = offline;
        offline = false;
        failures = 0;
        if (changed || typingChanged || wasOffline) _notify();
        if (changed) markRead();
      } catch (e) {
        if (_disposed || gen != _generation) break;
        failures++;
        if (e is SocialApiException && (e.status == 403 || e.status == 404)) {
          error = e.message;
          _notify();
          break;
        }
        if (!offline && failures >= 2) {
          offline = true;
          _notify();
        }
        await Future<void>.delayed(Duration(milliseconds: min(15000, 1000 * (1 << min(failures, 4)))));
      }
    }
    if (gen == _generation) _running = false;
  }

  Future<void> loadOlder() async {
    if (loadingOlder || !hasMore || messages.isEmpty) return;
    loadingOlder = true;
    _notify();
    try {
      final r = Map<String, dynamic>.from(await _api.call('messages', {
        'channelId': channel.id,
        'limit': 50,
        'before': messages.first.createdAt.toUtc().toIso8601String(),
      }) as Map);
      service.mergeProfiles(r['profiles']);
      await _absorb(r['messages'], r['refs']);
      hasMore = r['hasMore'] == true;
    } catch (_) {
    } finally {
      loadingOlder = false;
      _notify();
    }
  }

  // ------------------------------------------------------------ conversão
  Future<SocialMessage> _decode(Map<String, dynamic> row) async {
    final deleted = row['deleted_at'] != null;
    var text = '';
    var attachments = const <SocialAttachment>[];
    var locked = false;
    if (!deleted) {
      try {
        final c = await SupabaseSocialCrypto.decryptRow(row);
        text = c.texto;
        attachments = c.anexos;
      } catch (_) {
        locked = true;
      }
    }
    return SocialMessage(
      id: '${row['id']}',
      conversationId: '${row['conversation_id']}',
      channelId: '${row['channel_id']}',
      senderId: '${row['sender_id']}',
      text: text,
      attachments: attachments,
      replyTo: row['reply_to'] as String?,
      mentions: [for (final m in (row['mentions'] as List? ?? const [])) '$m'],
      createdAt: DateTime.parse('${row['created_at']}').toLocal(),
      editedAt: row['edited_at'] == null ? null : DateTime.tryParse('${row['edited_at']}')?.toLocal(),
      deleted: deleted,
      pinnedAt: row['pinned_at'] == null ? null : DateTime.tryParse('${row['pinned_at']}')?.toLocal(),
      reactions: SocialMessage.reactionsFrom(row['reactions']),
      rev: (row['rev'] as num?)?.toInt() ?? 0,
      locked: locked,
    );
  }

  final Map<String, SocialMessage> _refs = {};

  /// Mensagem respondida (pode estar fora da página carregada).
  SocialMessage? find(String id) => _byId[id] ?? _refs[id];

  Future<bool> _absorb(dynamic rows, dynamic refs) async {
    var changed = false;
    for (final raw in (refs as List? ?? const [])) {
      final m = await _decode(Map<String, dynamic>.from(raw as Map));
      _refs[m.id] = m;
    }
    for (final raw in (rows as List? ?? const [])) {
      final m = await _decode(Map<String, dynamic>.from(raw as Map));
      final old = _byId[m.id];
      if (old != null && old.rev >= m.rev && m.rev != 0) continue;
      _byId[m.id] = m;
      changed = true;
    }
    if (changed) _sort();
    return changed;
  }

  void _sort() {
    final list = _byId.values.toList()..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    messages = list;
  }

  // ------------------------------------------------------------ ações
  List<String> _mentionsIn(String text, Map<String, String> usernames) {
    final out = <String>{};
    for (final m in RegExp(r'@([a-z0-9_.]{2,24})', caseSensitive: false).allMatches(text)) {
      final name = m.group(1)!.toLowerCase();
      if (ehTodos(name)) {
        out.add('everyone');
      } else if (usernames[name] != null) {
        out.add(usernames[name]!);
      }
    }
    return out.toList();
  }

  /// Envia já mostrando a mensagem (estado "enviando"); em caso de falha, ela fica
  /// marcada para tentar de novo.
  Future<void> send(String text, {List<SocialAttachment> attachments = const [], String? replyTo, Map<String, String> usernames = const {}}) async {
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}-${_localSeq++}';
    final pending = SocialMessage(
      id: localId,
      conversationId: conversation.id,
      channelId: channel.id,
      senderId: _me,
      text: text,
      attachments: attachments,
      replyTo: replyTo,
      createdAt: DateTime.now(),
      estado: EstadoEnvio.enviando,
      localId: localId,
    );
    _byId[localId] = pending;
    _sort();
    _notify();
    await _deliver(pending, usernames);
  }

  Future<void> retry(SocialMessage m, {Map<String, String> usernames = const {}}) async {
    _byId[m.id] = m.copyWith(estado: EstadoEnvio.enviando);
    _notify();
    await _deliver(_byId[m.id]!, usernames);
  }

  void discard(SocialMessage m) {
    _byId.remove(m.id);
    _sort();
    _notify();
  }

  Future<void> _deliver(SocialMessage pending, Map<String, String> usernames) async {
    try {
      final sealed = await SupabaseSocialCrypto.encryptMessage(
        conversationId: conversation.id,
        channelId: channel.id,
        senderId: _me,
        text: pending.text,
        attachments: pending.attachments,
      );
      final r = Map<String, dynamic>.from(await _api.call('send_message', {
        'channelId': channel.id,
        ...sealed,
        'replyTo': ?pending.replyTo,
        'mentions': _mentionsIn(pending.text, usernames),
      }) as Map);
      final row = Map<String, dynamic>.from(r['message'] as Map);
      final real = await _decode(row);
      _byId.remove(pending.id);
      _byId[real.id] = real;
      _sort();
      _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);
    } catch (e) {
      if (_byId.containsKey(pending.id)) _byId[pending.id] = pending.copyWith(estado: EstadoEnvio.falhou);
      error = e is SocialApiException ? e.message : null;
    }
    _notify();
  }

  Future<void> edit(SocialMessage m, String text, {Map<String, String> usernames = const {}}) async {
    final before = _byId[m.id];
    _byId[m.id] = m.copyWith(text: text, editedAt: DateTime.now());
    _sort();
    _notify();
    try {
      final sealed = await SupabaseSocialCrypto.encryptMessage(
        conversationId: conversation.id,
        channelId: channel.id,
        senderId: _me,
        text: text,
        attachments: m.attachments,
      );
      await _api.call('edit_message', {'messageId': m.id, ...sealed, 'mentions': _mentionsIn(text, usernames)});
    } catch (e) {
      if (before != null) _byId[m.id] = before;
      _sort();
      _notify();
      rethrow;
    }
  }

  Future<void> delete(SocialMessage m) async {
    final before = _byId[m.id];
    _byId[m.id] = m.copyWith(deleted: true, text: '');
    _sort();
    _notify();
    try {
      await _api.call('delete_message', {
        'messageId': m.id,
        if (m.senderId == _me) 'paths': [for (final a in m.attachments) a.path],
      });
    } catch (e) {
      if (before != null) _byId[m.id] = before;
      _sort();
      _notify();
      rethrow;
    }
  }

  Future<void> toggleReaction(SocialMessage m, String emoji) async {
    final current = _byId[m.id] ?? m;
    final mine = current.reactions.any((r) => r.emoji == emoji && r.users.contains(_me));
    final next = <SocialReaction>[];
    var found = false;
    for (final r in current.reactions) {
      if (r.emoji == emoji) {
        found = true;
        final users = mine ? (r.users.where((u) => u != _me).toList()) : [...r.users, _me];
        if (users.isNotEmpty) next.add(SocialReaction(emoji, users));
      } else {
        next.add(r);
      }
    }
    if (!found && !mine) next.add(SocialReaction(emoji, [_me]));
    _byId[m.id] = current.copyWith(reactions: next);
    _sort();
    _notify();
    unawaited(service.useEmoji(emoji));
    try {
      await _api.call('react', {'messageId': m.id, 'emoji': emoji, 'on': !mine});
    } catch (_) {
      _byId[m.id] = current;
      _sort();
      _notify();
    }
  }

  Future<void> pin(SocialMessage m, bool pinned) async {
    await _api.call('pin', {'messageId': m.id, 'pinned': pinned});
    _byId[m.id] = m.copyWith(pinnedAt: pinned ? DateTime.now() : null, clearPin: !pinned);
    _notify();
  }

  Future<List<SocialMessage>> pins() async {
    final r = Map<String, dynamic>.from(await _api.call('pins', {'channelId': channel.id}) as Map);
    service.mergeProfiles(r['profiles']);
    return [for (final row in (r['messages'] as List)) await _decode(Map<String, dynamic>.from(row as Map))];
  }

  /// Avisa que estou digitando (no máximo a cada 4 s).
  void typingNow({bool active = true}) {
    final now = DateTime.now();
    if (active && now.difference(_lastTypingSent).inSeconds < 4) return;
    _lastTypingSent = active ? now : DateTime.fromMillisecondsSinceEpoch(0);
    unawaited(_api.call('typing', {'channelId': channel.id, 'active': active}).catchError((_) => null));
  }

  void markRead({bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastRead).inSeconds < 3) return;
    _lastRead = now;
    service.markChannelSeen(conversation.id, channel.id);
    unawaited(_api.call('read', {'channelId': channel.id}).catchError((_) => null));
  }

  /// Busca no que já foi carregado (o servidor não consegue ler as mensagens).
  /// [nome] troca "@usuário" pelo nome que aparece, para achar "Mikame" e não só
  /// "@ifes_..." (#7).
  List<SocialMessage> search(String query, {String? Function(String usuario)? nome}) {
    final q = query.trim().toLowerCase().replaceFirst(RegExp(r'^@'), '');
    if (q.isEmpty) return const [];
    bool acha(SocialMessage m) {
      final t = m.text.toLowerCase();
      if (t.contains(q)) return true;
      if (nome != null && trocarMencoes(m.text, nome).toLowerCase().contains(q)) return true;
      return m.attachments.any((a) => a.name.toLowerCase().contains(q));
    }

    return messages.reversed.where((m) => !m.deleted && acha(m)).toList();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
