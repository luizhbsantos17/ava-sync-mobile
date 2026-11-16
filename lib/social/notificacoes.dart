import 'dart:convert';

import '../config.dart';
import '../fundo.dart';
import 'api.dart';
import 'formatacao.dart';
import 'supabase_crypto.dart';

/// Uma mensagem já decifrada, pronta para aparecer na notificação.
class LinhaNotif {
  final String nome;
  final String texto;
  final int quando; // ms desde 1970
  /// A mensagem marcou você (@você, @cargo seu ou @todos).
  final bool mencao;
  const LinhaNotif(this.nome, this.texto, this.quando, {this.mencao = false});

  Map<String, dynamic> toJson() => {'n': nome, 't': texto, 'q': quando, if (mencao) 'm': true};
  static LinhaNotif fromJson(Map<String, dynamic> j) =>
      LinhaNotif('${j['n']}', '${j['t']}', (j['q'] as num?)?.toInt() ?? 0, mencao: j['m'] == true);
}

/// A mensagem marca esta pessoa? (puro, testável)
bool marcaVoce(List<String> mentions, {required String eu, Iterable<String> meusCargos = const []}) =>
    eu.isNotEmpty &&
    (mentions.contains(eu) || mentions.contains('everyone') || meusCargos.any((r) => mentions.contains('role:$r')));

/// Notificação de uma conversa (grupo + canal, ou mensagem direta).
class ConversaNotif {
  final String conversa;
  final String canal;
  final String titulo;
  final bool direta;
  final List<LinhaNotif> linhas; // da mais antiga para a mais nova
  final int total; // quantas mensagens chegaram desde a última leitura

  const ConversaNotif({
    required this.conversa,
    required this.canal,
    required this.titulo,
    required this.direta,
    required this.linhas,
    required this.total,
  });

  String get chave => '$conversa:$canal';
  int get id => chave.hashCode;
  String get payload => 'social:$conversa:$canal';

  /// Mensagens que não cabem na notificação ("+3 mensagens").
  int get escondidas => total - linhas.length;

  /// Alguma mensagem acumulada marcou você: a notificação vira de menção (#7).
  bool get temMencao => linhas.any((l) => l.mencao);

  Map<String, dynamic> toJson() => {
        'c': conversa,
        'ch': canal,
        'ti': titulo,
        'dm': direta,
        'to': total,
        'l': [for (final l in linhas) l.toJson()],
      };

  static ConversaNotif fromJson(Map<String, dynamic> j) => ConversaNotif(
        conversa: '${j['c']}',
        canal: '${j['ch']}',
        titulo: '${j['ti']}',
        direta: j['dm'] == true,
        total: (j['to'] as num?)?.toInt() ?? 0,
        linhas: [for (final l in (j['l'] as List? ?? const [])) LinhaNotif.fromJson(Map<String, dynamic>.from(l as Map))],
      );
}

typedef MensagemNova = ({String conversa, String canal, String titulo, bool direta, LinhaNotif linha});

/// Junta as mensagens novas às que já estavam na notificação (puro, testável).
/// Guarda só as [maxLinhas] mais recentes de cada conversa, mas conta todas.
Map<String, ConversaNotif> acumular(Map<String, ConversaNotif> antes, List<MensagemNova> novas, {int maxLinhas = 7}) {
  final out = Map<String, ConversaNotif>.of(antes);
  for (final n in novas) {
    final chave = '${n.conversa}:${n.canal}';
    final atual = out[chave];
    final linhas = [...?atual?.linhas, n.linha]..sort((a, b) => a.quando.compareTo(b.quando));
    out[chave] = ConversaNotif(
      conversa: n.conversa,
      canal: n.canal,
      titulo: n.titulo,
      direta: n.direta,
      linhas: linhas.length > maxLinhas ? linhas.sublist(linhas.length - maxLinhas) : linhas,
      total: (atual?.total ?? 0) + 1,
    );
  }
  return out;
}

/// Texto de uma notificação para sistemas sem estilo de conversa (Windows, Linux, macOS):
/// "Ana: oi" uma por linha (sem o nome na mensagem direta) e "+N mensagens" no fim.
String corpoSimples(ConversaNotif n) {
  final linhas = [for (final l in n.linhas) '${l.mencao ? '📣 ' : ''}${n.direta ? l.texto : '${l.nome}: ${l.texto}'}'];
  if (n.escondidas > 0) linhas.insert(0, '+${n.escondidas} mensagens antes');
  return linhas.join('\n');
}

/// Título e texto da notificação de um evento do Social (#1). Puro, testável.
({String titulo, String corpo})? textoDoEvento(String kind, Map<String, dynamic> d) {
  final nome = '${d['nome'] ?? 'Alguém'}';
  final grupo = '${d['titulo'] ?? 'um grupo'}';
  final por = d['por'] == null ? '' : ' por ${d['por']}';
  return switch (kind) {
    'amizade_pedido' => (titulo: 'Pedido de amizade', corpo: '$nome quer ser seu amigo no Social.'),
    'amizade_aceita' => (titulo: 'Pedido aceito', corpo: '$nome aceitou seu pedido de amizade.'),
    'adicionado' => (titulo: 'Você entrou em $grupo', corpo: 'Você foi adicionado ao grupo$por.'),
    'removido' => (titulo: 'Você saiu de $grupo', corpo: 'Você foi removido do grupo$por.'),
    'banido' => (titulo: 'Você foi banido de $grupo', corpo: 'Você foi removido e não pode voltar$por.'),
    'cargo' => d['ganhou'] == false
        ? (titulo: 'Cargo alterado em $grupo', corpo: 'Você não é mais ${d['cargo']}.')
        : (titulo: 'Novo cargo em $grupo', corpo: 'Você agora é ${d['cargo']}.'),
    _ => null,
  };
}

/// Notificações do Social: uma por conversa, com quem mandou e o texto de cada mensagem,
/// acumulando até a pessoa abrir a conversa (como WhatsApp e Discord).
class NotifSocial {
  /// Canal que a pessoa está olhando agora (com a janela visível): não notifica.
  static String? Function()? canalVisivel;

  static Map<String, ConversaNotif> _ler() {
    try {
      final m = jsonDecode(Cfg.socialNotifPendentes) as Map;
      return {for (final e in m.entries) '${e.key}': ConversaNotif.fromJson(Map<String, dynamic>.from(e.value as Map))};
    } catch (_) {
      return {};
    }
  }

  static Future<void> _salvar(Map<String, ConversaNotif> m) =>
      Cfg.setSocialNotifPendentes(jsonEncode({for (final e in m.entries) e.key: e.value.toJson()}));

  /// Trata a resposta de `inbox`/`notifications`: decifra, acumula e mostra.
  static Future<void> processar(Map<String, dynamic> r) async {
    final todasLinhas = (r['messages'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    final eventos = (r['events'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    if (todasLinhas.isEmpty && eventos.isEmpty) return;
    await Cfg.recarregar(); // o push do Android roda em outro isolate
    // as linhas vêm da mais nova para a mais antiga; o cursor é a mais nova de todas
    final datas = [for (final x in [...todasLinhas, ...eventos]) '${x['created_at']}']..sort();
    if (datas.last.compareTo(Cfg.socialUltimaNotif) > 0) await Cfg.setSocialUltimaNotif(datas.last);
    // o push e a escuta em tempo real podem trazer a mesma coisa: avisa uma vez só
    final vistas = Cfg.socialNotifIds.toSet();
    final eventosNovos = eventos.where((e) => !vistas.contains('e:${e['id']}')).toList();
    if (eventosNovos.isNotEmpty) {
      await Cfg.setSocialNotifIds([...Cfg.socialNotifIds, for (final e in eventosNovos) 'e:${e['id']}']);
      for (final e in eventosNovos.reversed) {
        final t = textoDoEvento('${e['kind']}', e['data'] is Map ? Map<String, dynamic>.from(e['data'] as Map) : const {});
        if (t != null) await Notif.mostrar(9000 + ('${e['id']}'.hashCode.abs() % 900), t.titulo, t.corpo, payload: 'social:evento');
      }
    }
    final rows = todasLinhas.where((m) => m['id'] == null || !vistas.contains('${m['id']}')).toList();
    if (rows.isEmpty) return;
    await Cfg.setSocialNotifIds([...Cfg.socialNotifIds, for (final m in rows.reversed) if (m['id'] != null) '${m['id']}']);

    final convs = {for (final c in (r['conversations'] as List? ?? const [])) '${(c as Map)['id']}': c};
    final canais = {for (final c in (r['channels'] as List? ?? const [])) '${(c as Map)['id']}': '${c['name']}'};
    final perfis = r['profiles'] is Map ? r['profiles'] as Map : const {};
    // "@usuário" e "@cargo" viram o nome que aparece no chat (#7)
    final nomePorUsuario = <String, String>{
      for (final p in perfis.values)
        if (p is Map && '${p['username'] ?? ''}'.isNotEmpty) '${p['username']}'.toLowerCase(): '${p['display_name']}',
      for (final c in (r['roles'] as List? ?? const []))
        if (c is Map) apelidoCargo('${c['name']}'): '${c['name']}',
    };
    String nomes(String t) => trocarMencoes(t, (u) => nomePorUsuario[u]);
    final visivel = canalVisivel?.call();
    final eu = Cfg.socialMeuId;
    final meusCargos = Cfg.socialMeusCargos;

    final novas = <MensagemNova>[];
    for (final row in rows.reversed) {
      final conversa = '${row['conversation_id']}';
      final canal = '${row['channel_id']}';
      if (canal == visivel) continue; // já está vendo essa conversa
      final p = perfis['${row['sender_id']}'];
      final nome = p is Map ? '${p['display_name']}' : 'Colega';
      String texto;
      try {
        final c = await SupabaseSocialCrypto.decryptRow(row);
        texto = c.texto.trim().isNotEmpty
            ? nomes(c.texto.trim())
            : c.anexos.isEmpty
                ? 'Mensagem'
                : c.anexos.first.imagem
                    ? '📷 Foto'
                    : '📎 ${c.anexos.first.name}';
      } catch (_) {
        texto = '🔒 Mensagem protegida (abra a conversa para receber a chave)';
      }
      final c = convs[conversa];
      final direta = c is Map && c['group_kind'] == 'dm';
      final nomeCanal = canais[canal];
      final titulo = direta ? nome : '${c is Map ? c['title'] : 'Grupo'}${nomeCanal == null ? '' : ' · #$nomeCanal'}';
      final quando = DateTime.tryParse('${row['created_at']}')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      final mencoes = [for (final m in (row['mentions'] as List? ?? const [])) '$m'];
      final cargos = [for (final r in (meusCargos[conversa] as List? ?? const [])) '$r'];
      final mencao = !direta && marcaVoce(mencoes, eu: eu, meusCargos: cargos);
      novas.add((conversa: conversa, canal: canal, titulo: titulo, direta: direta, linha: LinhaNotif(nome, texto, quando, mencao: mencao)));
    }
    if (novas.isEmpty) return;

    final todas = acumular(_ler(), novas);
    await _salvar(todas);
    for (final chave in novas.map((n) => '${n.conversa}:${n.canal}').toSet()) {
      final n = todas[chave];
      if (n != null) await Notif.mostrarConversa(n);
    }
  }

  /// A pessoa abriu a conversa: apaga a notificação e o que estava acumulado.
  static Future<void> lida(String conversa, String canal) async {
    final m = _ler();
    final n = m.remove('$conversa:$canal');
    if (n == null) return;
    await _salvar(m);
    try {
      await Notif.cancelar(n.id);
    } catch (_) {}
  }
}

/// Uma rodada de verificação (segundo plano do Android a cada ~15 min, sem tempo real).
Future<void> verificarSocial() async {
  if (!Cfg.socialUsado || !Cfg.socialNotificacoes || !SocialApi.configured) return;
  if ((await Cfg.token()) == null) return;
  final since = Cfg.socialUltimaNotif.isEmpty
      ? DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String()
      : Cfg.socialUltimaNotif;
  final r = Map<String, dynamic>.from(await SocialApi().call('notifications', {'since': since}) as Map);
  await NotifSocial.processar(r);
}
