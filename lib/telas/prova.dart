import 'package:material_ui/material_ui.dart';

import '../classificar.dart';
import '../estado_app.dart';
import '../ia.dart';
import '../util.dart';
import 'comum.dart';
import 'ia_tela.dart';
import 'navegacao.dart';

/// Questionario do Moodle ou evento do calendario (ex.: prova presencial).
class ProvaTela extends StatelessWidget {
  final String tipo; // quiz | evento
  final dynamic itemId;
  final dynamic cursoId;
  const ProvaTela({super.key, required this.tipo, required this.itemId, required this.cursoId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.cursoPorId(cursoId);
        final lst = c == null ? const [] : lista(tipo == 'quiz' ? c['provas'] : c['eventos']);
        final q = lst.map(mapa).where((x) => x['id'] == itemId).firstOrNull;
        if (c == null || q == null) {
          return Scaffold(appBar: AppBar(), body: const Vazio(Icons.error_outline, 'Item não encontrado.'));
        }
        final cat = categoria(tipo, q);
        final limite = (q['limite'] as num?)?.toInt() ?? 0;
        final ts = tipo == 'quiz' ? (q['fecha'] ?? q['abre']) : q['ts'];
        final u = urgencia(context, (ts as num?)?.toInt() ?? 0);
        return Scaffold(
          appBar: AppBar(title: Text('${q['nome']}', maxLines: 2), actions: [
            IconButton(
                tooltip: 'Mover entre Atividades e Provas',
                icon: const Icon(Icons.swap_horiz),
                onPressed: () => menuCategoria(context, tipo, q)),
            IconButton(tooltip: 'Abrir no AVA', icon: const Icon(Icons.open_in_new), onPressed: () => abrirLinkExterno(context, q['link'])),
          ]),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            Text('${c['nome']}', style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              etiqueta(cat == 'prova' ? 'Prova / avaliação' : 'Atividade', cat == 'prova' ? Colors.deepPurple : Colors.teal),
              etiqueta(rotuloTipo(tipo), Theme.of(context).colorScheme.primary),
            ]),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (tipo == 'quiz') ...[
                    Text('Abre: ${fmtData(q['abre'])}'),
                    Text('Fecha: ${fmtData(q['fecha'])} (${fmtRelativo(q['fecha'])})',
                        style: TextStyle(color: u.cor, fontWeight: FontWeight.w600)),
                    Text('Tempo limite: ${limite == 0 ? 'sem limite' : '${limite ~/ 60} min'}'),
                    Text('Tentativas: ${(q['tentativas'] ?? 0) == 0 ? 'ilimitadas' : q['tentativas']}'),
                  ] else
                    Text('Data: ${fmtData(q['ts'])} (${fmtRelativo(q['ts'])})',
                        style: TextStyle(color: u.cor, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            IaAtalho(
                curso: c,
                chave: chaveItem(tipo, q['id']),
                kind: cat == 'prova' ? 'prova' : 'atividade',
                nome: '${q['nome']}',
                tipo: tipo,
                item: q),
            const SizedBox(height: 12),
            Text('Descrição', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            HtmlView('${q['html'] ?? ''}'),
            if (tipo == 'quiz') ...[
              const SizedBox(height: 16),
              Text('Questionários são respondidos no AVA.', style: TextStyle(color: Theme.of(context).hintColor)),
            ],
          ]),
        );
      },
    );
  }
}
