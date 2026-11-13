import 'package:material_ui/material_ui.dart';

import '../armazenamento.dart';
import '../classificar.dart';
import '../config.dart';
import '../estado_app.dart';
import '../util.dart';
import 'comum.dart';
import 'curso.dart';
import 'prova.dart';
import 'tarefa.dart';

/// Abre um item de prazo/lista (tarefa, questionario, evento).
void abrirItem(BuildContext context, Map<String, dynamic> e) {
  final item = mapa(e['item']);
  final curso = mapa(e['curso']);
  switch (e['tipo']) {
    case 'tarefa':
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TarefaTela(tarefaId: item['id'])));
    case 'quiz':
    case 'evento':
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => ProvaTela(tipo: '${e['tipo']}', itemId: item['id'], cursoId: curso['id'])));
    default:
      abrirLinkExterno(context, item['link']);
  }
}

/// Toque longo num item: mover entre Atividades e Provas.
Future<void> menuCategoria(BuildContext context, String tipo, Map<String, dynamic> item) async {
  final chave = '$tipo:${item['id']}';
  final atual = categoria(tipo, item);
  final manual = Cfg.categoriaManual.containsKey(chave);
  final r = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text('${item['nome']}', maxLines: 2), subtitle: Text('Hoje em: ${atual == 'prova' ? 'Provas' : 'Atividades'}')),
        ListTile(
            leading: const Icon(Icons.quiz_outlined),
            title: const Text('É prova / avaliação'),
            onTap: () => Navigator.pop(ctx, 'prova')),
        ListTile(
            leading: const Icon(Icons.assignment_outlined),
            title: const Text('É atividade'),
            onTap: () => Navigator.pop(ctx, 'atividade')),
        if (manual)
          ListTile(
              leading: const Icon(Icons.auto_mode), title: const Text('Voltar ao automático'), onTap: () => Navigator.pop(ctx, 'auto')),
      ]),
    ),
  );
  if (r == null) return;
  await app.marcarCategoria(chave, r == 'auto' ? null : r);
}

/// Acha um modulo do Moodle (pelo id da pagina mod/x/view.php?id=N) no que ja foi sincronizado.
({Map<String, dynamic> mod, Map<String, dynamic> curso})? moduloPorCmid(int cmid) {
  for (final c in app.todosCursos) {
    for (final s in lista(c['secoes']).map(mapa)) {
      for (final mo in lista(s['modulos']).map(mapa)) {
        if (mo['id'] == cmid) return (mod: mo, curso: c);
      }
    }
  }
  return null;
}

/// Abre um modulo do conteudo da materia dentro do app.
void abrirModulo(BuildContext context, Map<String, dynamic> mo, Map<String, dynamic> curso) {
  final tipo = '${mo['tipo']}';
  final arquivos = lista(mo['arquivos']).map(mapa).toList();
  if (mo['html'] != null) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => LeitorTela(titulo: '${mo['nome']}', caminho: '${mo['html']}', link: mo['link'])));
    return;
  }
  if (arquivos.isNotEmpty && (tipo == 'resource' || tipo == 'url' || tipo == 'imscp')) {
    // o primeiro arquivo e o principal (o que o professor marcou para abrir)
    final html = arquivos.where((a) => '${a['nome']}'.toLowerCase().endsWith('.html')).firstOrNull;
    abrirArquivo(context, tipo == 'imscp' && html != null ? html : arquivos.first);
    return;
  }
  if (tipo == 'url') {
    abrirLinkExterno(context, mo['externo']);
    return;
  }
  if (tipo == 'assign') {
    final t = lista(curso['tarefas']).map(mapa).where((t) => t['cmid'] == mo['id']).firstOrNull;
    if (t != null) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => TarefaTela(tarefaId: t['id'])));
      return;
    }
  }
  if (tipo == 'quiz') {
    final q = lista(curso['provas']).map(mapa).where((q) => '${q['link']}'.endsWith('id=${mo['id']}')).firstOrNull;
    if (q != null) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ProvaTela(tipo: 'quiz', itemId: q['id'], cursoId: curso['id'])));
      return;
    }
  }
  if (tipo == 'folder') return; // os arquivos aparecem logo abaixo
  abrirLinkExterno(context, mo['link']);
}

/// Link do proprio Moodle tocado num texto. Devolve true se o app cuidou dele.
Future<bool> abrirUrlDoMoodle(BuildContext context, String url) async {
  final u = Uri.tryParse(url);
  final site = Uri.tryParse(Cfg.site);
  if (u == null || site == null || u.host != site.host) return false;
  final mod = RegExp(r'/mod/(\w+)/view\.php').firstMatch(u.path);
  final id = int.tryParse(u.queryParameters['id'] ?? '');
  if (mod != null && id != null) {
    final r = moduloPorCmid(id);
    if (r != null) {
      abrirModulo(context, r.mod, r.curso);
      return true;
    }
    return false;
  }
  if (u.path.endsWith('/course/view.php') && id != null && app.cursoPorId(id) != null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => CursoTela(cursoId: id)));
    return true;
  }
  if (u.path.contains('pluginfile.php')) {
    final nome = u.pathSegments.isEmpty ? 'arquivo' : Uri.decodeComponent(u.pathSegments.last);
    final dir = '${(await _pastaTemp())}/${hashCurto(u.path)}_${nomeSeguro(nome, 80)}';
    if (context.mounted) await abrirArquivo(context, {'nome': nome, 'url': url, 'caminho': dir});
    return true;
  }
  return false;
}

Future<String> _pastaTemp() async => '${(await Store.base()).path}/_links';
