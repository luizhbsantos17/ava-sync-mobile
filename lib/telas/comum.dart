import 'dart:io';

import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../config.dart';
import '../estado_app.dart';
import '../moodle.dart';
import '../util.dart';
import 'navegacao.dart';

void aviso(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

Future<void> abrirLinkExterno(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) aviso(context, 'Não consegui abrir o link.');
}

/// Qualquer link tocado no app: arquivo local, atividade do Moodle (abre dentro do app),
/// arquivo do Moodle (baixa e abre) ou site externo (navegador).
Future<void> abrirLink(BuildContext context, String? url) async {
  if (url == null || url.isEmpty) return;
  if (url.startsWith('/')) return abrirLocal(context, url);
  if (await abrirUrlDoMoodle(context, url)) return;
  if (context.mounted) await abrirLinkExterno(context, url);
}

/// Abre um arquivo do celular. HTML abre no leitor interno (com imagens e estilos).
Future<void> abrirLocal(BuildContext context, String caminho, {String? titulo}) async {
  final f = File(caminho);
  if (!await f.exists()) {
    if (context.mounted) aviso(context, 'Arquivo ainda não baixado. Sincronize de novo.');
    return;
  }
  final ext = caminho.toLowerCase().split('.').last;
  if (ext == 'html' || ext == 'htm') {
    if (context.mounted) {
      Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => WebLeitorTela(titulo: titulo ?? caminho.split('/').last, arquivo: caminho)));
    }
    return;
  }
  final r = await OpenFilex.open(caminho);
  if (r.type != ResultType.done && context.mounted) {
    aviso(context, 'Nenhum app para abrir este arquivo (${r.message}).');
  }
}

/// Abre um arquivo do Moodle. Se ainda nao foi baixado, baixa agora.
Future<void> abrirArquivo(BuildContext context, Map<String, dynamic> arq) async {
  final f = File('${arq['caminho']}');
  if (!await f.exists()) {
    final url = '${arq['url'] ?? ''}';
    final tok = app.token ?? await Cfg.token();
    if (url.isEmpty || tok == null) {
      if (context.mounted) aviso(context, 'Arquivo ainda não baixado.');
      return;
    }
    if (context.mounted) aviso(context, 'Baixando ${arq['nome']}...');
    try {
      await Moodle(Cfg.site, tok).baixar(url, f, maxMb: 2000);
    } catch (e) {
      if (context.mounted) aviso(context, 'Falha ao baixar: $e');
      return;
    }
  }
  if (context.mounted) await abrirLocal(context, f.path, titulo: '${arq['nome']}');
}

/// Tira cores e fundos fixos do HTML do professor. Assim o texto segue o tema do app
/// (sem texto preto em fundo escuro, ou fundo preto atras de texto preto).
String semCoresFixas(String h) {
  var t = h.replaceAllMapped(RegExp(r'''style\s*=\s*(["'])(.*?)\1''', caseSensitive: false, dotAll: true), (m) {
    final limpo = m[2]!
        .split(';')
        .where((d) => !RegExp(r'^\s*(color|background(-color)?|background-image)\s*:', caseSensitive: false).hasMatch(d))
        .join(';');
    return 'style=${m[1]}$limpo${m[1]}';
  });
  t = t.replaceAll(RegExp(r'''\s(bgcolor|color)\s*=\s*(["']).*?\2''', caseSensitive: false), '');
  return t;
}

/// HTML do Moodle. Imagens locais (caminho "/...") vem do celular; imagens do Moodle
/// ainda nao baixadas sao carregadas pela internet com o token.
class HtmlView extends StatelessWidget {
  final String html;
  final String? baseDir; // para src relativo (HTML salvo em pasta)
  const HtmlView(this.html, {super.key, this.baseDir});

  Widget? _img(BuildContext context, String src) {
    Widget? w;
    if (src.startsWith('/')) {
      w = Image.file(File(src), errorBuilder: (_, _, _) => const Icon(Icons.broken_image));
    } else if (baseDir != null && !src.contains(':')) {
      w = Image.file(File('$baseDir/${Uri.decodeFull(src)}'), errorBuilder: (_, _, _) => const Icon(Icons.broken_image));
    } else if (src.startsWith('http') && app.token != null && Uri.tryParse(src)?.host == Uri.tryParse(Cfg.site)?.host) {
      w = Image.network(Moodle(Cfg.site, app.token!).comToken(src),
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image));
    }
    if (w == null) return null;
    final img = w;
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => Scaffold(appBar: AppBar(), body: InteractiveViewer(maxScale: 6, child: Center(child: img))))),
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 6), child: img),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (html.trim().isEmpty) {
      return Text('(sem descrição)', style: TextStyle(color: Theme.of(context).hintColor));
    }
    final cs = Theme.of(context).colorScheme;
    return HtmlWidget(
      semCoresFixas(html),
      textStyle: TextStyle(fontSize: 15, height: 1.45, color: cs.onSurface),
      customStylesBuilder: (el) => switch (el.localName) {
        'a' => {'color': '#${(cs.primary.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}'},
        'td' || 'th' => {'border': '1px solid #8888', 'padding': '4px'},
        'table' => {'border-collapse': 'collapse'},
        _ => null,
      },
      customWidgetBuilder: (el) => el.localName == 'img' ? _img(context, el.attributes['src'] ?? '') : null,
      onTapUrl: (url) async {
        await abrirLink(context, url);
        return true;
      },
    );
  }
}

/// Le um .html salvo pelo app (livro, pagina) e mostra com o visual do app.
class LeitorTela extends StatelessWidget {
  final String titulo;
  final String caminho;
  final String? link;
  const LeitorTela({super.key, required this.titulo, required this.caminho, this.link});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo, maxLines: 2), actions: [
        IconButton(
            tooltip: 'Ver original (página completa)',
            icon: const Icon(Icons.web),
            onPressed: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => WebLeitorTela(titulo: titulo, arquivo: caminho)))),
        if (link != null)
          IconButton(
              tooltip: 'Abrir no AVA', icon: const Icon(Icons.open_in_new), onPressed: () => abrirLinkExterno(context, link)),
      ]),
      body: FutureBuilder<String>(
        future: File(caminho).readAsString(),
        builder: (context, s) {
          if (!s.hasData) {
            return s.hasError
                ? const Center(child: Text('Arquivo não encontrado. Sincronize de novo.'))
                : const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), child: HtmlView(s.data!, baseDir: File(caminho).parent.path));
        },
      ),
    );
  }
}

/// HTML "de verdade" (notas de aula, pacotes de conteudo): abre num navegador interno,
/// com acesso as imagens/estilos da mesma pasta.
class WebLeitorTela extends StatefulWidget {
  final String titulo;
  final String arquivo;
  const WebLeitorTela({super.key, required this.titulo, required this.arquivo});
  @override
  State<WebLeitorTela> createState() => _WebLeitorTelaState();
}

class _WebLeitorTelaState extends State<WebLeitorTela> {
  late final WebViewController _c;

  @override
  void initState() {
    super.initState();
    _c = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.white)
      ..setNavigationDelegate(NavigationDelegate(onNavigationRequest: (req) {
        if (req.url.startsWith('file:')) return NavigationDecision.navigate;
        abrirLink(context, req.url);
        return NavigationDecision.prevent;
      }));
    final p = _c.platform;
    if (p is AndroidWebViewController) {
      p.setAllowFileAccess(true);
    }
    _c.loadFile(widget.arquivo);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo, maxLines: 2), actions: [
        IconButton(
            tooltip: 'Abrir com outro app',
            icon: const Icon(Icons.open_in_browser),
            onPressed: () => OpenFilex.open(widget.arquivo)),
      ]),
      body: WebViewWidget(controller: _c),
    );
  }
}

/// Tela generica de detalhe (aviso, evento).
class DetalheTela extends StatelessWidget {
  final String titulo;
  final List<String> linhas;
  final String html;
  final String? link;
  final List<Widget> extras;
  const DetalheTela(
      {super.key, required this.titulo, required this.linhas, required this.html, this.link, this.extras = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo, maxLines: 2)),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final l in linhas)
          Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(l, style: Theme.of(context).textTheme.bodyMedium)),
        ...extras,
        const Divider(height: 24),
        HtmlView(html),
        if (link != null) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
              onPressed: () => abrirLinkExterno(context, link), icon: const Icon(Icons.open_in_new), label: const Text('Abrir no AVA')),
        ],
      ]),
    );
  }
}

/// Cor e rotulo por urgencia do prazo.
({Color cor, String rotulo}) urgencia(BuildContext context, int ts, {bool entregue = false}) {
  final cs = Theme.of(context).colorScheme;
  if (entregue) return (cor: Colors.green, rotulo: 'entregue');
  final diff = ts - agoraSeg();
  if (diff < 0) return (cor: cs.error, rotulo: 'atrasado');
  if (diff < 86400) return (cor: Colors.deepOrange, rotulo: 'menos de 24 h');
  if (diff < 3 * 86400) return (cor: Colors.orange, rotulo: 'em breve');
  if (diff < 7 * 86400) return (cor: Colors.amber.shade700, rotulo: 'esta semana');
  return (cor: cs.primary, rotulo: 'depois');
}

Widget etiqueta(String txt, Color cor) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(txt, style: TextStyle(color: cor, fontSize: 12, fontWeight: FontWeight.w600)),
    );

Widget chipSituacao(BuildContext context, String situacao) {
  final (cor, txt) = switch (situacao) {
    'submitted' => (Colors.green, 'Entregue'),
    'draft' => (Colors.orange, 'Rascunho'),
    'reopened' => (Colors.purple, 'Reaberta'),
    _ => (Theme.of(context).colorScheme.error, 'Não entregue'),
  };
  return etiqueta(txt, cor);
}

class Vazio extends StatelessWidget {
  final IconData icone;
  final String texto;
  const Vazio(this.icone, this.texto, {super.key});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: 48, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ]),
        ),
      );
}
