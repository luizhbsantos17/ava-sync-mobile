import 'dart:io';

import 'package:material_ui/material_ui.dart';

import '../classificar.dart';
import '../config.dart';
import '../estado_app.dart';
import '../ia.dart';
import '../util.dart';
import 'comum.dart';
import 'ia_tela.dart';
import 'navegacao.dart';

class CursoTela extends StatelessWidget {
  final dynamic cursoId;
  const CursoTela({super.key, required this.cursoId});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final c = app.cursoPorId(cursoId);
        if (c == null) return Scaffold(appBar: AppBar(), body: const Vazio(Icons.error_outline, 'Matéria não encontrada.'));
        final itens = itensDoCurso(c);
        final avisos = lista(c['avisos']).map(mapa).toList();
        final secoes = lista(c['secoes']).map(mapa).toList();
        return DefaultTabController(
          length: 6,
          initialIndex: 1,
          child: Scaffold(
            appBar: AppBar(
              title: Text('${c['nome']}', maxLines: 2),
              actions: [
                IconButton(
                    tooltip: 'Abrir no AVA', icon: const Icon(Icons.open_in_new), onPressed: () => abrirLinkExterno(context, c['link'])),
              ],
              bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
                Tab(icon: Icon(Icons.auto_awesome, size: 18), text: 'Estudar'),
                Tab(text: 'Atividades'),
                Tab(text: 'Provas'),
                Tab(text: 'Avisos'),
                Tab(text: 'Conteúdo'),
                Tab(text: 'Arquivos'),
              ]),
            ),
            body: TabBarView(children: [
              _Estudar(c, itens),
              _listaItens(context, itens.atividades, 'Nenhuma atividade.'),
              _listaItens(context, itens.provas, 'Nenhuma prova encontrada.\nSe alguma atividade for prova, toque e segure nela para mover.'),
              avisos.isEmpty
                  ? const Vazio(Icons.inbox_outlined, 'Nenhum aviso.')
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: avisos.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final a = avisos[i];
                        return ListTile(
                          leading: const Icon(Icons.campaign_outlined),
                          title: Text('${a['titulo']}'),
                          subtitle: Text('${a['autor']} · ${fmtData(a['data'])}\n${semHtml('${a['html']}').replaceAll('\n', ' ')}',
                              maxLines: 3, overflow: TextOverflow.ellipsis),
                          isThreeLine: true,
                          onTap: () => Navigator.of(context).push(MaterialPageRoute(
                              builder: (_) => DetalheTela(
                                  titulo: '${a['titulo']}',
                                  linhas: ['Fórum: ${a['forum']}', 'Autor: ${a['autor']}', 'Data: ${fmtData(a['data'])}'],
                                  html: '${a['html']}',
                                  link: a['link']))),
                        );
                      }),
              _Conteudo(c, secoes),
              _Arquivos(secoes, lista(c['tarefas']).map(mapa).toList()),
            ]),
          ),
        );
      },
    );
  }
}

Widget _listaItens(BuildContext context, List<Map<String, dynamic>> l, String vazio) {
  if (l.isEmpty) return Vazio(Icons.inbox_outlined, vazio);
  return ListView.separated(
    padding: const EdgeInsets.only(top: 4, bottom: 24),
    itemCount: l.length + 1,
    separatorBuilder: (_, _) => const Divider(height: 1),
    itemBuilder: (_, i) {
      if (i == 0) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Text('Toque e segure para mover entre Atividades e Provas.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        );
      }
      return ItemLinha(l[i - 1]);
    },
  );
}

/// Linha de tarefa/questionario/evento, usada nas listas e nos prazos.
class ItemLinha extends StatelessWidget {
  final Map<String, dynamic> e;
  final bool mostrarCurso;
  const ItemLinha(this.e, {super.key, this.mostrarCurso = false});

  @override
  Widget build(BuildContext context) {
    final item = mapa(e['item']);
    final tipo = '${e['tipo']}';
    final ts = e['ts'] as int;
    final entregue = tipo == 'tarefa' && item['situacao'] == 'submitted';
    final u = urgencia(context, ts, entregue: entregue);
    final prova = e['cat'] == 'prova';
    final icone = prova
        ? Icons.quiz_outlined
        : switch (tipo) {
            'tarefa' => Icons.assignment_outlined,
            'quiz' => Icons.checklist,
            _ => Icons.event_outlined,
          };
    final menu = tipo == 'acao' ? null : () => menuCategoria(context, tipo, item);
    // clique direito no computador = segurar no celular
    return GestureDetector(onSecondaryTap: menu, child: ListTile(
      leading: CircleAvatar(backgroundColor: u.cor.withValues(alpha: 0.15), child: Icon(icone, color: u.cor)),
      title: Text('${item['nome']}', maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (mostrarCurso) Text('${mapa(e['curso'])['nome'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 2),
        Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(ts == 0 ? 'sem data' : fmtRelativo(ts), style: TextStyle(color: u.cor, fontWeight: FontWeight.w600)),
          if (prova) etiqueta('prova', Colors.deepPurple),
          if (tipo != 'acao') etiqueta(rotuloTipo(tipo), Colors.blueGrey),
          if (tipo == 'tarefa') chipSituacao(context, '${item['situacao']}'),
        ]),
      ]),
      onTap: () => abrirItem(context, e),
      onLongPress: menu,
    ));
  }
}

class _Estudar extends StatelessWidget {
  final Map<String, dynamic> c;
  final ({List<Map<String, dynamic>> atividades, List<Map<String, dynamic>> provas}) itens;
  const _Estudar(this.c, this.itens);

  @override
  Widget build(BuildContext context) {
    final ativa = Cfg.iaAtiva;
    final agora = agoraSeg();
    final futuras = [
      ...itens.provas.where((e) => (e['ts'] as int) > agora - 86400),
      ...itens.atividades.where((e) => (e['ts'] as int) > agora - 86400),
    ];
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (ativa == 'nenhum')
        const Card(
          child: Padding(
            padding: EdgeInsets.all(12),
            child: Text('Sem IA por API? Abra um guia e use "Fazer num app de chat": o pedido vai para o app do '
                'Claude (ou ChatGPT/Gemini) e você cola a resposta de volta. Para gerar direto, configure uma API em Ajustes.'),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text('IA ativa: ${nomeSlot(ativa)}', style: TextStyle(color: Theme.of(context).hintColor)),
        ),
      IaAtalho(curso: c, chave: 'materia', kind: 'materia', nome: '${c['nome']}'),
      const SizedBox(height: 8),
      Text('Dica: gere primeiro o guia da matéria. Os guias de atividades e provas usam ele como base.',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
      if (futuras.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Próximas provas e atividades', style: Theme.of(context).textTheme.titleSmall),
        for (final e in futuras)
          IaAtalho(
            curso: c,
            chave: chaveItem('${e['tipo']}', mapa(e['item'])['id']),
            kind: e['cat'] == 'prova' ? 'prova' : 'atividade',
            nome: '${mapa(e['item'])['nome']}',
            tipo: '${e['tipo']}',
            item: mapa(e['item']),
          ),
      ],
    ]);
  }
}

class _Conteudo extends StatelessWidget {
  final Map<String, dynamic> curso;
  final List<Map<String, dynamic>> secoes;
  const _Conteudo(this.curso, this.secoes);

  IconData _icone(String tipo) => switch (tipo) {
        'resource' => Icons.description_outlined,
        'folder' => Icons.folder_outlined,
        'url' => Icons.link,
        'page' => Icons.article_outlined,
        'book' => Icons.auto_stories_outlined,
        'assign' => Icons.assignment_outlined,
        'quiz' => Icons.quiz_outlined,
        'forum' => Icons.forum_outlined,
        'imscp' => Icons.web_outlined,
        'label' => Icons.notes,
        _ => Icons.extension_outlined,
      };

  @override
  Widget build(BuildContext context) {
    if (secoes.isEmpty) return const Vazio(Icons.inbox_outlined, 'Sem conteúdo.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final s in secoes)
          ExpansionTile(
            title: Text('${s['nome']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            initiallyExpanded: secoes.length <= 3,
            childrenPadding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              if ('${s['resumo']}'.trim().isNotEmpty)
                Padding(padding: const EdgeInsets.only(bottom: 8), child: HtmlView('${s['resumo']}')),
              for (final mo in lista(s['modulos']).map(mapa)) _modulo(context, mo),
            ],
          ),
      ],
    );
  }

  Widget _modulo(BuildContext context, Map<String, dynamic> mo) {
    final tipo = '${mo['tipo']}';
    if (tipo == 'label') {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: HtmlView('${mo['desc']}'));
    }
    final arquivos = lista(mo['arquivos']).map(mapa).toList();
    final baixado = arquivos.isNotEmpty && File('${arquivos.first['caminho']}').existsSync();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(_icone(tipo)),
        title: Text('${mo['nome']}'),
        subtitle: switch (tipo) {
          'book' => Text(mo['html'] != null ? 'Livro · abre offline' : 'Livro · abre no AVA'),
          'page' => const Text('Página · abre offline'),
          'url' when arquivos.isNotEmpty => const Text('Link · arquivo salvo'),
          'url' => Text('${mo['externo'] ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
          'resource' || 'imscp' when arquivos.isNotEmpty => Text(
              '${baixado ? 'baixado' : 'toque para baixar'} · ${fmtTamanho(arquivos.fold<int>(0, (s, a) => s + ((a['tamanho'] as num?)?.toInt() ?? 0)))}'),
          'folder' => Text('${arquivos.length} arquivo(s)'),
          _ => null,
        },
        onTap: () => abrirModulo(context, mo, curso),
      ),
      if ('${mo['desc']}'.trim().isNotEmpty)
        Padding(padding: const EdgeInsets.only(left: 40, bottom: 4), child: HtmlView('${mo['desc']}')),
      if (tipo == 'folder')
        for (final a in arquivos)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.insert_drive_file_outlined, size: 20),
              title: Text('${a['nome']}'),
              onTap: () => abrirArquivo(context, a),
            ),
          ),
    ]);
  }
}

class _Arquivos extends StatelessWidget {
  final List<Map<String, dynamic>> secoes;
  final List<Map<String, dynamic>> tarefas;
  const _Arquivos(this.secoes, this.tarefas);

  @override
  Widget build(BuildContext context) {
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final s in secoes) {
      for (final mo in lista(s['modulos']).map(mapa)) {
        for (final a in lista(mo['arquivos']).map(mapa)) {
          grupos.putIfAbsent('${s['nome']}', () => []).add(a);
        }
        if (mo['html'] != null && mo['tipo'] == 'book') {
          grupos.putIfAbsent('${s['nome']}', () => []).add({'nome': '${mo['nome']} (livro)', 'caminho': mo['html'], 'livro': true});
        }
      }
    }
    for (final t in tarefas) {
      for (final a in lista(t['anexos']).map(mapa)) {
        grupos.putIfAbsent('Anexos das atividades', () => []).add(a);
      }
    }
    if (grupos.isEmpty) return const Vazio(Icons.folder_off_outlined, 'Nenhum arquivo.');
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final g in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(g.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          for (final a in g.value)
            ListTile(
              dense: true,
              leading: Icon(File('${a['caminho']}').existsSync() ? Icons.download_done : Icons.cloud_download_outlined),
              title: Text('${a['nome']}'),
              subtitle: (a['tamanho'] as num? ?? 0) > 0 ? Text(fmtTamanho((a['tamanho'] as num).toInt())) : null,
              onTap: () => a['livro'] == true
                  ? Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => LeitorTela(titulo: '${a['nome']}', caminho: '${a['caminho']}')))
                  : abrirArquivo(context, a),
            ),
        ],
      ],
    );
  }
}
