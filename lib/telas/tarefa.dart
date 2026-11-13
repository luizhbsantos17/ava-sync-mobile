import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../classificar.dart';
import '../estado_app.dart';
import '../ia.dart';
import '../util.dart';
import 'comum.dart';
import 'envio_tela.dart';
import 'ia_tela.dart';
import 'navegacao.dart';

({Map<String, dynamic> t, Map<String, dynamic> c})? acharTarefa(dynamic id) {
  for (final c in app.todosCursos) {
    for (final t in lista(c['tarefas']).map(mapa)) {
      if (t['id'] == id) return (t: t, c: c);
    }
  }
  return null;
}

class TarefaTela extends StatelessWidget {
  final dynamic tarefaId;
  const TarefaTela({super.key, required this.tarefaId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final r = acharTarefa(tarefaId);
        if (r == null) return Scaffold(appBar: AppBar(), body: const Vazio(Icons.error_outline, 'Tarefa não encontrada.'));
        final t = r.t;
        final cat = categoria('tarefa', t);
        final e = (t['entrega'] as num?)?.toInt() ?? 0;
        final u = urgencia(context, e, entregue: t['situacao'] == 'submitted');
        final anexos = lista(t['anexos']).map(mapa).toList();
        final enviados = lista(t['enviados']).map((x) => '$x').toList();
        final tt = Theme.of(context).textTheme;
        return Scaffold(
          appBar: AppBar(title: Text('${t['nome']}', maxLines: 2), actions: [
            IconButton(
                tooltip: 'Mover entre Atividades e Provas',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => menuCategoria(context, 'tarefa', t)),
            IconButton(tooltip: 'Abrir no AVA', icon: const Icon(Icons.open_in_new), onPressed: () => abrirLinkExterno(context, t['link'])),
          ]),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EnvioTela(tarefa: t))),
            icon: const Icon(Icons.upload_file),
            label: const Text('Enviar atividade'),
          ),
          body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
            Text('${r.c['nome']}', style: tt.bodyMedium?.copyWith(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              etiqueta(cat == 'prova' ? 'Prova / avaliação' : 'Atividade', cat == 'prova' ? Colors.deepPurple : Colors.teal),
              etiqueta('tarefa com entrega', Theme.of(context).colorScheme.primary),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.schedule, color: u.cor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(e == 0 ? 'Sem prazo' : 'Entrega: ${fmtData(e)} (${fmtRelativo(e)})',
                          style: TextStyle(color: u.cor, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    chipSituacao(context, '${t['situacao']}'),
                    if (t['nota'] != null && '${t['nota']}' != '-') Text('Nota: ${t['nota']}'),
                    if ((t['notaMax'] ?? 0) != 0) Text('vale ${t['notaMax']}'),
                  ]),
                  if ((t['corte'] ?? 0) != 0)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Data limite (atraso): ${fmtData(t['corte'])}')),
                  if ((t['abre'] ?? 0) != 0) Text('Abre em: ${fmtData(t['abre'])}'),
                  if (enviados.isNotEmpty)
                    Padding(padding: const EdgeInsets.only(top: 6), child: Text('Enviado: ${enviados.join(', ')}')),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            IaAtalho(
                curso: r.c,
                chave: chaveItem('tarefa', t['id']),
                kind: cat == 'prova' ? 'prova' : 'atividade',
                nome: '${t['nome']}',
                tipo: 'tarefa',
                item: t),
            const SizedBox(height: 16),
            Text('Enunciado', style: tt.titleMedium),
            const SizedBox(height: 8),
            HtmlView('${t['html']}'),
            if (anexos.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('Anexos do professor', style: tt.titleMedium),
              for (final a in anexos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(File('${a['caminho']}').existsSync() ? Icons.download_done : Icons.cloud_download_outlined),
                  title: Text('${a['nome']}'),
                  onTap: () => abrirArquivo(context, a),
                ),
            ],
          ]),
        );
      },
    );
  }
}
