import 'package:material_ui/material_ui.dart';

import '../estado_app.dart';
import '../util.dart';
import 'comum.dart';
import 'curso.dart';
import 'navegacao.dart';
import 'tarefa.dart';

class BuscaTela extends StatefulWidget {
  const BuscaTela({super.key});
  @override
  State<BuscaTela> createState() => _BuscaTelaState();
}

class _BuscaTelaState extends State<BuscaTela> {
  String _q = '';

  List<({String titulo, String sub, IconData icone, VoidCallback abrir})> _resultados(BuildContext context) {
    final q = _q.toLowerCase().trim();
    if (q.length < 2) return [];
    bool tem(String s) => s.toLowerCase().contains(q);
    final out = <({String titulo, String sub, IconData icone, VoidCallback abrir})>[];
    for (final c in app.cursos) {
      final nc = '${c['nome']}';
      for (final t in lista(c['tarefas']).map(mapa)) {
        if (tem('${t['nome']} ${semHtml('${t['html']}')}')) {
          out.add((
            titulo: '${t['nome']}',
            sub: '$nc · tarefa',
            icone: Icons.assignment_outlined,
            abrir: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TarefaTela(tarefaId: t['id']))),
          ));
        }
      }
      for (final p in lista(c['provas']).map(mapa)) {
        if (tem('${p['nome']} ${semHtml('${p['html']}')}')) {
          out.add((
            titulo: '${p['nome']}',
            sub: '$nc · questionário',
            icone: Icons.quiz_outlined,
            abrir: () => abrirItem(context, {'tipo': 'quiz', 'item': p, 'curso': c}),
          ));
        }
      }
      for (final a in lista(c['avisos']).map(mapa)) {
        if (tem('${a['titulo']} ${semHtml('${a['html']}')}')) {
          out.add((
            titulo: '${a['titulo']}',
            sub: '$nc · aviso',
            icone: Icons.campaign_outlined,
            abrir: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => DetalheTela(
                    titulo: '${a['titulo']}',
                    linhas: ['Autor: ${a['autor']}', 'Data: ${fmtData(a['data'])}'],
                    html: '${a['html']}',
                    link: a['link']))),
          ));
        }
      }
      for (final s in lista(c['secoes']).map(mapa)) {
        for (final mo in lista(s['modulos']).map(mapa)) {
          final arqs = lista(mo['arquivos']).map(mapa).toList();
          if (tem('${mo['nome']} ${semHtml('${mo['desc']}')} ${arqs.map((a) => a['nome']).join(' ')}')) {
            out.add((
              titulo: '${mo['nome']}'.isEmpty ? '(rótulo)' : '${mo['nome']}',
              sub: '$nc · ${s['nome']}',
              icone: Icons.description_outlined,
              abrir: () => mo['tipo'] == 'folder' || mo['tipo'] == 'label'
                  ? Navigator.of(context).push(MaterialPageRoute(builder: (_) => CursoTela(cursoId: c['id'])))
                  : abrirModulo(context, mo, c),
            ));
          }
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final r = _resultados(context);
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Buscar em tudo...', border: InputBorder.none),
          onChanged: (v) => setState(() => _q = v),
        ),
      ),
      body: _q.trim().length < 2
          ? const Vazio(Icons.search, 'Digite pelo menos 2 letras.')
          : r.isEmpty
              ? const Vazio(Icons.search_off, 'Nada encontrado.')
              : ListView.builder(
                  itemCount: r.length,
                  itemBuilder: (_, i) => ListTile(
                    leading: Icon(r[i].icone),
                    title: Text(r[i].titulo),
                    subtitle: Text(r[i].sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: r[i].abrir,
                  ),
                ),
    );
  }
}
