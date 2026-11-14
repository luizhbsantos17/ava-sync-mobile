import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../estado_app.dart';
import '../qacademico.dart';

/// Situacao de uma coleta no Q-Academico.
enum SituacaoQA { ok, precisaLogin, verificacao, falhou }

class ResultadoQA {
  final SituacaoQA situacao;
  final String mensagem;
  final int disciplinas;
  const ResultadoQA(this.situacao, this.mensagem, {this.disciplinas = 0});
}

/// Le o Q-Academico num WebView de verdade (o mesmo navegador do Android): o site roda
/// os proprios scripts, inclusive a protecao anti-robo. Se o site pedir verificacao,
/// a coleta para e a pessoa resolve na tela do Q-Academico. O app nunca tenta contornar.
class ColetorQA {
  final WebViewController web = WebViewController();
  Completer<String>? _carregou;
  bool _ocupado = false;

  ColetorQA() {
    web
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageFinished: (url) {
          final c = _carregou;
          if (c != null && !c.isCompleted) c.complete(url);
        },
        onWebResourceError: (e) {
          final c = _carregou;
          if (e.isForMainFrame == true && c != null && !c.isCompleted) c.completeError(Exception(e.description));
        },
      ));
  }

  static String get _base {
    final u = Cfg.qaUrl.isEmpty ? QAcademico.urlPadrao : Cfg.qaUrl;
    final i = u.indexOf('/qacademico/');
    return i < 0 ? u : u.substring(0, i + '/qacademico/'.length);
  }

  static String get urlLogin => Cfg.qaUrl.isEmpty ? QAcademico.urlPadrao : Cfg.qaUrl;

  /// Espera a pagina terminar (e o que ela redireciona em seguida).
  Future<String> _esperar(Future<void> Function() acao, {Duration limite = const Duration(seconds: 40)}) async {
    _carregou = Completer<String>();
    await acao();
    var url = await _carregou!.future.timeout(limite, onTimeout: () => throw Exception('O Q-Acadêmico demorou demais para responder.'));
    // redirecionamentos e paginas que se recarregam: espera estabilizar
    for (var i = 0; i < 4; i++) {
      _carregou = Completer<String>();
      try {
        url = await _carregou!.future.timeout(const Duration(milliseconds: 1500));
      } on TimeoutException {
        break;
      }
    }
    _carregou = null;
    return url;
  }

  Future<void> abrir(String url) => _esperar(() => web.loadRequest(Uri.parse(url)));

  Future<String> _js(String codigo) async {
    final r = await web.runJavaScriptReturningResult(codigo);
    if (r is String) {
      if (r.length >= 2 && r.startsWith('"')) {
        try {
          return '${jsonDecode(r)}';
        } catch (_) {}
      }
      return r;
    }
    return '$r';
  }

  Future<String> html() => _js('document.documentElement.outerHTML');

  /// login | verificacao | pagina
  Future<String> _estado() async {
    final url = (await web.currentUrl() ?? '').toLowerCase();
    if (url.contains('perfdrive') || url.contains('captcha')) return 'verificacao';
    final r = await _js('''(function(){
      if (document.forms['frmLogin'] || document.getElementById('txtSenha')) return 'login';
      var t = (document.body && document.body.innerText || '').toLowerCase();
      if (t.indexOf('captcha') >= 0 || t.indexOf('verifique que voc') >= 0 || t.indexOf('not a robot') >= 0) return 'verificacao';
      return 'pagina';
    })()''');
    return r;
  }

  /// Preenche o formulario de login da propria pagina e clica em OK
  /// (como um gerenciador de senhas faria). A pagina criptografa e envia.
  Future<void> entrar(String login, String senha) async {
    final l = jsonEncode(login), s = jsonEncode(senha);
    await _esperar(() => web.runJavaScript('''(function(){
      var f = document.forms['frmLogin'];
      var u = document.getElementById('txtLogin') || (f && f.LOGIN);
      var p = document.getElementById('txtSenha') || (f && f.SENHA);
      if (!u || !p) return;
      u.value = $l; p.value = $s;
      var b = document.getElementById('btnOk') || (f && f.Submit);
      if (b) { b.click(); } else if (f) { f.onsubmit ? f.onsubmit() : f.submit(); }
    })()'''), limite: const Duration(seconds: 60));
  }

  /// Le boletim e diarios e salva. [entrarSozinho]: usa a senha lembrada se a sessao caiu.
  Future<ResultadoQA> coletar({bool entrarSozinho = true}) async {
    if (_ocupado) return const ResultadoQA(SituacaoQA.falhou, 'Já está lendo o Q-Acadêmico.');
    _ocupado = true;
    try {
      await abrir('$_base${QAcademico.paginaBoletim}');
      var est = await _estado();
      if (est == 'verificacao') {
        return const ResultadoQA(SituacaoQA.verificacao, 'O Q-Acadêmico pediu uma verificação. Abra a tela do Q-Acadêmico e conclua.');
      }
      if (est == 'login') {
        final senha = await Cfg.qaSenha();
        if (!entrarSozinho || Cfg.qaLogin.isEmpty || senha == null) {
          return const ResultadoQA(SituacaoQA.precisaLogin, 'Entre no Q-Acadêmico para atualizar notas e faltas.');
        }
        await entrar(Cfg.qaLogin, senha);
        est = await _estado();
        if (est == 'verificacao') {
          return const ResultadoQA(SituacaoQA.verificacao, 'O Q-Acadêmico pediu uma verificação. Abra a tela do Q-Acadêmico e conclua.');
        }
        if (est == 'login') return const ResultadoQA(SituacaoQA.precisaLogin, 'Matrícula ou senha do Q-Acadêmico não aceitas.');
        await abrir('$_base${QAcademico.paginaBoletim}');
      }
      // os links do menu dizem onde ficam boletim, diarios e horario nesta instituicao
      final links = await _linksDoMenu();
      final urlBoletim = links['boletim'] ?? '$_base${QAcademico.paginaBoletim}';
      if (links['boletim'] != null) await abrir(urlBoletim);
      final boletim = await html();
      await QAcademico.guardarPagina('boletim', boletim);
      final disc = lerBoletim(boletim);
      if (disc.isEmpty) {
        return const ResultadoQA(SituacaoQA.falhou,
            'Entrei, mas não reconheci o boletim. Em Perfil, use "Exportar páginas do Q-Acadêmico" e me mande os arquivos.');
      }
      try {
        await abrir(links['diarios'] ?? '$_base${QAcademico.paginaDiarios}');
        if (await _estado() == 'pagina') {
          final h = await html();
          await QAcademico.guardarPagina('diarios', h);
          lerDiarios(h, disc);
        }
      } catch (_) {} // diarios sao extra: o boletim ja vale
      var horario = <Aula>[];
      try {
        await abrir(links['horario'] ?? '$_base${QAcademico.paginaHorario}');
        if (await _estado() == 'pagina') {
          final h = await html();
          await QAcademico.guardarPagina('horario', h);
          horario = lerHorario(h, disc);
        }
      } catch (_) {}
      final n = await app.salvarAcademico(disc, horario: horario);
      return ResultadoQA(SituacaoQA.ok,
          'Q-Acadêmico atualizado: $n disciplina(s)${horario.isEmpty ? '' : ' e ${horario.length} aula(s) no horário'}.',
          disciplinas: n);
    } catch (e) {
      return ResultadoQA(SituacaoQA.falhou, 'Falha ao ler o Q-Acadêmico: ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      _ocupado = false;
    }
  }

  /// Le os links da pagina atual (menu do Q-Academico) e escolhe boletim/diarios/horario.
  Future<Map<String, String>> _linksDoMenu() async {
    try {
      await QAcademico.guardarPagina('menu', await html());
      final r = await _js('JSON.stringify(Array.from(document.querySelectorAll("a[href]")).map(function(a){'
          'return [a.innerText || a.title || "", a.href];}))');
      final links = (jsonDecode(r) as List).map((e) => (norm('${e[0]}'), '${e[1]}')).where((e) => e.$2.startsWith('http'));
      String? achar(bool Function(String) f) => links.where((e) => f(e.$1)).map((e) => e.$2).firstOrNull;
      return {
        'boletim': ?achar((t) => t.contains('boletim')),
        'diarios': ?achar((t) => t.contains('diario')),
        'horario': ?achar((t) => t.contains('horario') && !t.contains('prova')),
      };
    } catch (_) {
      return const {};
    }
  }
}

/// WebView invisivel (1x1) que permite atualizar o Q-Academico junto com a sincronizacao
/// do AVA enquanto o app esta aberto.
class ColetorOculto extends StatefulWidget {
  const ColetorOculto({super.key});
  @override
  State<ColetorOculto> createState() => _ColetorOcultoState();
}

class _ColetorOcultoState extends State<ColetorOculto> {
  ColetorQA? _c;

  @override
  void initState() {
    super.initState();
    app.atualizarAcademico = () async {
      final c = _c ??= ColetorQA();
      if (mounted) setState(() {});
      final r = await c.coletar();
      return r.situacao == SituacaoQA.ok ? null : r.mensagem;
    };
  }

  @override
  void dispose() {
    app.atualizarAcademico = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: c == null ? const SizedBox.shrink() : IgnorePointer(child: WebViewWidget(controller: c.web)));
  }
}

/// Tela do Q-Academico: o site de verdade, com os campos de login do app em cima.
class QAcademicoTela extends StatefulWidget {
  const QAcademicoTela({super.key});
  @override
  State<QAcademicoTela> createState() => _QAcademicoTelaState();
}

class _QAcademicoTelaState extends State<QAcademicoTela> {
  final _c = ColetorQA();
  final _login = TextEditingController(text: Cfg.qaLogin);
  final _senha = TextEditingController();
  bool _lembrar = true;
  bool _ocupado = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    Cfg.qaSenha().then((s) {
      if (s != null && mounted) setState(() => _senha.text = s);
    });
    _c.abrir(ColetorQA.urlLogin).catchError((_) {});
  }

  Future<void> _importar() async {
    setState(() {
      _ocupado = true;
      _msg = 'Entrando e lendo boletim e diários...';
    });
    final login = _login.text.trim();
    final senha = _senha.text;
    if (login.isNotEmpty) await Cfg.setQaLogin(login);
    // a senha so fica salva se marcar "lembrar"; senao, so e usada agora
    await Cfg.setQaSenha(_lembrar ? senha : null);
    ResultadoQA r;
    if (senha.isNotEmpty && login.isNotEmpty) {
      try {
        await _c.abrir(ColetorQA.urlLogin);
        await _c.entrar(login, senha);
      } catch (_) {}
      r = await _c.coletar(entrarSozinho: false);
    } else {
      r = await _c.coletar(entrarSozinho: false); // ja entrou pela pagina
    }
    if (!mounted) return;
    setState(() {
      _ocupado = false;
      _msg = r.mensagem;
    });
    if (r.situacao == SituacaoQA.ok) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.mensagem)));
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Q-Acadêmico'), actions: [
        IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: () => _c.web.reload()),
      ]),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: TextField(
                    controller: _login,
                    decoration: const InputDecoration(labelText: 'Matrícula', isDense: true),
                    keyboardType: TextInputType.text),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                    controller: _senha,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Senha', isDense: true)),
              ),
            ]),
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _lembrar,
              onChanged: (v) => setState(() => _lembrar = v ?? false),
              title: const Text('Lembrar senha (criptografada) para atualizar junto com o AVA'),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _ocupado ? null : _importar,
                icon: _ocupado
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download_rounded),
                label: const Text('Entrar e importar notas e faltas'),
              ),
            ),
            if (_msg != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_msg!, textAlign: TextAlign.center)),
            const SizedBox(height: 4),
            Text('Se o site pedir verificação, resolva abaixo e toque no botão de novo.',
                style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        const Divider(height: 1),
        Expanded(child: WebViewWidget(controller: _c.web)),
      ]),
    );
  }
}
