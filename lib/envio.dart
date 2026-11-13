import 'dart:math';
import 'dart:typed_data';

import 'moodle.dart';
import 'sync.dart';
import 'util.dart';

/// Situacao atual da tarefa, lida AO VIVO no Moodle (nao do snapshot).
class SituacaoEntrega {
  final String status;
  final List<String> arquivos;
  final String? nota;
  SituacaoEntrega(this.status, this.arquivos, this.nota);
  String get texto => situacoes[status] ?? status;
}

class PedidoEnvio {
  final int tarefaId;
  final List<({String nome, Uint8List bytes})> arquivos;
  final String texto;
  final bool finalizar;
  final bool aceitouDeclaracao;
  final bool exigeDeclaracao;
  final String confirmacao;
  PedidoEnvio({
    required this.tarefaId,
    required this.arquivos,
    this.texto = '',
    this.finalizar = false,
    this.aceitouDeclaracao = false,
    this.exigeDeclaracao = false,
    required this.confirmacao,
  });

  /// Regras checadas antes de tocar no Moodle. Devolve o motivo, ou null se pode enviar.
  String? problema() {
    if (confirmacao.trim() != 'ENVIAR') return 'Digite ENVIAR para confirmar.';
    if (arquivos.isEmpty && texto.trim().isEmpty) return 'Escolha ao menos um arquivo ou escreva um texto.';
    if (finalizar && exigeDeclaracao && !aceitouDeclaracao) {
      return 'Para enviar para avaliação, você precisa marcar a declaração de autoria.';
    }
    return null;
  }
}

/// Entrega de tarefas. So roda quando a pessoa aperta o botao na tela de envio,
/// depois de digitar ENVIAR. Nunca e chamada em segundo plano.
class Envio {
  static Future<SituacaoEntrega> situacao(Moodle m, int tarefaId, dynamic userid) async {
    final st = mapa(await m.call('mod_assign_get_submission_status', {'assignid': tarefaId, 'userid': userid}));
    final sub = mapa(mapa(st['lastattempt'])['submission']);
    final arqs = <String>[];
    for (final pl in lista(sub['plugins']).map(mapa)) {
      for (final fa in lista(pl['fileareas']).map(mapa)) {
        for (final f in lista(fa['files']).map(mapa)) {
          arqs.add('${f['filename']}');
        }
      }
    }
    return SituacaoEntrega('${sub['status'] ?? 'new'}', arqs, mapa(st['feedback'])['gradefordisplay']?.toString());
  }

  static void _avisos(dynamic r, String etapa) {
    final w = lista(r is Map ? r['warnings'] : r).map(mapa).toList();
    if (w.isNotEmpty) {
      throw MoodleErro('$etapa: ${w.map((x) => x['message'] ?? x['item'] ?? x).join('; ')}');
    }
  }

  static Future<SituacaoEntrega> executar(Moodle m, PedidoEnvio p, dynamic userid) async {
    final motivo = p.problema();
    if (motivo != null) throw MoodleErro(motivo);

    final plugindata = <String, dynamic>{};
    if (p.arquivos.isNotEmpty) {
      plugindata['files_filemanager'] = await m.upload(p.arquivos);
    }
    if (p.texto.trim().isNotEmpty) {
      final livre = mapa(await m.tentar('core_files_get_unused_draft_itemid', {}));
      final itemid = livre['itemid'] ?? (100000000 + Random().nextInt(800000000));
      plugindata['onlinetext_editor'] = {'text': p.texto, 'format': 1, 'itemid': itemid};
    }
    _avisos(await m.call('mod_assign_save_submission', {'assignmentid': p.tarefaId, 'plugindata': plugindata}),
        'Salvar a entrega');
    if (p.finalizar) {
      _avisos(
          await m.call('mod_assign_submit_for_grading',
              {'assignmentid': p.tarefaId, 'acceptsubmissionstatement': p.aceitouDeclaracao}),
          'Enviar para avaliação');
    }
    return situacao(m, p.tarefaId, userid);
  }
}
