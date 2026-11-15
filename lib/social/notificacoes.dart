import '../config.dart';
import '../fundo.dart';
import 'api.dart';
import 'supabase_crypto.dart';

/// Roda em segundo plano (workmanager, a cada ~15 min): busca mensagens novas
/// das conversas não silenciadas, abre no aparelho e mostra uma notificação por conversa.
Future<void> verificarSocial() async {
  if (!Cfg.socialUsado || !Cfg.socialNotificacoes || !SocialApi.configured) return;
  if ((await Cfg.token()) == null) return;
  final since = Cfg.socialUltimaNotif.isEmpty
      ? DateTime.now().toUtc().subtract(const Duration(minutes: 20)).toIso8601String()
      : Cfg.socialUltimaNotif;
  final api = SocialApi();
  final r = Map<String, dynamic>.from(await api.call('notifications', {'since': since}) as Map);
  final rows = (r['messages'] as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  if (rows.isEmpty) return;
  await Cfg.setSocialUltimaNotif('${rows.first['created_at']}');

  final titles = {for (final c in (r['conversations'] as List? ?? const [])) '${(c as Map)['id']}': c};
  final channels = {for (final c in (r['channels'] as List? ?? const [])) '${(c as Map)['id']}': '${c['name']}'};
  final profiles = r['profiles'] is Map ? r['profiles'] as Map : const {};

  final porConversa = <String, List<String>>{};
  final canalDe = <String, String>{};
  for (final row in rows.reversed) {
    final conv = '${row['conversation_id']}';
    final p = profiles['${row['sender_id']}'];
    final nome = p is Map ? '${p['display_name']}' : 'Colega';
    String texto;
    try {
      final c = await SupabaseSocialCrypto.decryptRow(row);
      texto = c.texto.isNotEmpty ? c.texto : (c.anexos.isNotEmpty ? (c.anexos.first.imagem ? '📷 Foto' : '📎 ${c.anexos.first.name}') : '');
    } catch (_) {
      texto = 'Nova mensagem';
    }
    porConversa.putIfAbsent(conv, () => []).add('$nome: $texto');
    canalDe[conv] = '${row['channel_id']}';
  }
  for (final e in porConversa.entries) {
    final c = titles[e.key];
    final dm = c is Map && c['group_kind'] == 'dm';
    final canal = channels[canalDe[e.key]];
    final titulo = dm
        ? e.value.first.split(':').first
        : '${c is Map ? c['title'] : 'Grupo'}${canal == null ? '' : ' · #$canal'}';
    final linhas = dm ? e.value.map((l) => l.substring(l.indexOf(':') + 1).trim()).toList() : e.value;
    final corpo = linhas.length > 5 ? '${linhas.sublist(linhas.length - 5).join('\n')}\n+${linhas.length - 5} mensagens' : linhas.join('\n');
    await Notif.mostrarSocial(e.key.hashCode, titulo, corpo, payload: 'social:${e.key}:${canalDe[e.key]}');
  }
}
