import 'dart:async';
import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import '../navegador_web.dart';

import '../config.dart';
import '../estado_app.dart';
import '../qacademico.dart';
import 'questionarios.dart';

/// Situacao de uma coleta no Q-Academico.
/// [questionarios]: o Q-Acadêmico bloqueou o sistema até responder a avaliação docente.
enum SituacaoQA { ok, precisaLogin, verificacao, falhou, questionarios }

class ResultadoQA {
  final SituacaoQA situacao;
  final String mensagem;
  final int disciplinas;
  /// Boletim lido, mas diario e/ou horario nao: os dados estao incompletos.
  final bool parcial;
  /// Questionários obrigatórios pendentes (situação [SituacaoQA.questionarios]).
  final List<QuestionarioQA> questionarios;
  const ResultadoQA(this.situacao, this.mensagem, {this.disciplinas = 0, this.parcial = false, this.questionarios = const []});
}

/// Mensagem final da importacao (dizendo o que nao foi lido, sem aparentar sucesso completo).
ResultadoQA resultadoImportacao(int disciplinas, LeituraDiarios? diarios, int blocosHorario) {
  final semDiario = diarios == null || diarios.disciplinas == 0;
  final semHorario = blocosHorario == 0;
  final partes = [
    '$disciplinas disciplina(s)',
    if (!semDiario) 'frequência de ${diarios.disciplinas}',
    if (!semDiario && diarios.avaliacoes > 0) '${diarios.avaliacoes} avaliação(ões)',
    if (!semHorario) '$blocosHorario aula(s) no horário',
  ];
  final faltou = [
    if (semDiario) 'os diários (frequência e avaliações)',
    if (semHorario) 'o horário',
  ];
  final msg = faltou.isEmpty
      ? 'Q-Acadêmico atualizado: ${partes.join(', ')}.'
      : 'Importação parcial: li ${partes.join(', ')}, mas não consegui ler ${faltou.join(' nem ')}.';
  return ResultadoQA(SituacaoQA.ok, msg, disciplinas: disciplinas, parcial: faltou.isNotEmpty);
}

/// So guarda matricula/senha depois de uma importacao que deu certo. A senha so fica
/// salva se a pessoa marcou "lembrar"; desmarcado, apaga a que estava salva.
Future<void> guardarCredenciaisQA(ResultadoQA r,
    {required String login, required String senha, required bool lembrar}) async {
  if (r.situacao != SituacaoQA.ok) return;
  if (login.isNotEmpty) await Cfg.setQaLogin(login);
  await Cfg.setQaSenha(lembrar && senha.isNotEmpty ? senha : null);
}

/// Le o Q-Academico num WebView de verdade (o mesmo navegador do Android): o site roda
/// os proprios scripts, inclusive a protecao anti-robo. Se o site pedir verificacao,
/// a coleta para e a pessoa resolve na tela do Q-Academico. O app nunca tenta contornar.
class ColetorQA {
  late final NavegadorWeb web;
  Completer<String>? _carregou;
  bool _ocupado = false;

  ColetorQA() {
    web = NavegadorWeb(
      aoTerminar: (url) {
        final c = _carregou;
        if (c != null && !c.isCompleted) c.complete(url);
      },
      aoFalhar: (erro) {
        final c = _carregou;
        if (c != null && !c.isCompleted) c.completeError(Exception(erro));
      },
    );
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

  Future<void> abrir(String url) => _esperar(() => web.carregar(url));

  Future<String> _js(String codigo) async {
    final r = await web.rodarJsComResultado(codigo);
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
    final url = (await web.urlAtual() ?? '').toLowerCase();
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
    await _esperar(() => web.rodarJs('''(function(){
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
      // fim de semestre: o Q-Acadêmico pode exigir a avaliação docente antes de liberar o resto
      var boletim = await html();
      if (!ehBloqueioQuestionarios(boletim) && lerBoletim(boletim).isEmpty) {
        try {
          await abrir('$_base${QAcademico.paginaQuestionarios}');
          final h = await html();
          if (ehBloqueioQuestionarios(h)) boletim = h;
        } catch (_) {}
      }
      if (ehBloqueioQuestionarios(boletim)) {
        final qs = lerQuestionariosPendentes(boletim, base: _base).where((q) => q.obrigatorio).toList();
        if (qs.isNotEmpty) {
          return ResultadoQA(SituacaoQA.questionarios,
              'O Q-Acadêmico está pedindo a avaliação de ${qs.length} disciplina(s) antes de liberar notas e faltas.',
              questionarios: qs);
        }
      }
      // o boletim do t=2032 e o formato conhecido; o menu so ajuda a achar diarios e horario
      final links = await _linksDoMenu();
      boletim = await html();
      await QAcademico.guardarPagina('boletim', boletim);
      final disc = lerBoletim(boletim);
      if (disc.isEmpty) {
        return const ResultadoQA(SituacaoQA.falhou,
            'Entrei, mas não reconheci o boletim. Em Perfil, use "Exportar páginas do Q-Acadêmico" e me mande os arquivos.');
      }
      LeituraDiarios? diarios;
      try {
        await abrir(links['diarios'] ?? '$_base${QAcademico.paginaDiarios}');
        if (await _estado() == 'pagina') {
          final h = await html();
          await QAcademico.guardarPagina('diarios', h);
          diarios = lerDiarios(h, disc);
        }
      } catch (_) {}
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
      return resultadoImportacao(n, diarios, horario.length);
    } catch (e) {
      return ResultadoQA(SituacaoQA.falhou, 'Falha ao ler o Q-Acadêmico: ${'$e'.replaceFirst('Exception: ', '')}');
    } finally {
      _ocupado = false;
    }
  }

  /// Responde os questionários obrigatórios com as notas que a pessoa escolheu na tela
  /// do app: abre cada um, marca as opções e clica em "Enviar respostas", como ela faria.
  /// Devolve quantos foram enviados; para no primeiro que der errado (com a mensagem).
  Future<int> responderQuestionarios(List<RespostaQuestionario> respostas, {void Function(int feitos, int total)? progresso}) async {
    if (_ocupado) throw Exception('Já está lendo o Q-Acadêmico. Tente de novo em instantes.');
    _ocupado = true;
    var feitos = 0;
    try {
      for (final r in respostas) {
        progresso?.call(feitos, respostas.length);
        final q = r.questionario;
        await abrir(q.url);
        final est = await _estado();
        if (est != 'pagina') {
          throw Exception(est == 'login'
              ? 'A sessão do Q-Acadêmico caiu. Entre de novo e tente outra vez.'
              : 'O Q-Acadêmico pediu uma verificação. Abra a tela do Q-Acadêmico e conclua.');
        }
        final perguntas = lerFormularioQuestionario(await html());
        if (perguntas.isEmpty) throw Exception('Não reconheci o formulário de ${q.disciplina}. Responda esse pelo site.');
        final escolhas = escolherRespostas(perguntas, r.pontos);
        final semResposta = perguntas.where((p) => !p.deTexto && !escolhas.containsKey(p.campo)).length;
        if (semResposta > 0) {
          throw Exception('${q.disciplina}: $semResposta pergunta(s) com opções diferentes de "pontos". Responda esse pelo site.');
        }
        final textos = {
          for (final p in perguntas.where((p) => p.deTexto)) p.campo: '',
        };
        if (textos.isNotEmpty && r.comentario.trim().isNotEmpty) textos[textos.keys.first] = r.comentario.trim();
        final esc = jsonEncode(escolhas), txt = jsonEncode(textos);
        String? falha;
        try {
          await _esperar(() async {
            final res = await _js('''(function(){
              window.alert = function(){}; window.confirm = function(){ return true; };
              window.onbeforeunload = null; if (document.body) document.body.onbeforeunload = null;
              var f = document.getElementById('frmquestionario') || document.forms['frmquestionario'];
              if (!f) return 'sem-form';
              var esc = $esc, txt = $txt;
              for (var n in esc) {
                var r = f.querySelector('input[name="' + n + '"][value="' + esc[n] + '"]');
                if (!r) return 'faltou:' + n;
                if (!r.disabled) r.click();
              }
              for (var n in txt) { var t = f.elements[n]; if (t) t.value = txt[n]; }
              if (typeof validateAndSubmit === 'function') { validateAndSubmit(f); }
              else { var b = document.getElementById('Enviar'); if (b) b.click(); else f.submit(); }
              return 'ok';
            })()''');
            if (res != 'ok') falha = res;
          }, limite: const Duration(seconds: 30));
        } on TimeoutException {
          falha = 'sem-resposta';
        } catch (e) {
          if ('$e'.contains('demorou')) falha = 'sem-resposta';
          if (falha == null) rethrow;
        }
        if (falha != null) {
          throw Exception('O Q-Acadêmico não aceitou as respostas de ${q.disciplina} ($falha). Responda esse pelo site.');
        }
        // continua no mesmo formulário: não foi aceito
        final depois = await html();
        if (lerFormularioQuestionario(depois).isNotEmpty && depois.contains(q.url.split('codAvaliado=').last.split('&').first)) {
          throw Exception('O Q-Acadêmico não aceitou as respostas de ${q.disciplina}. Responda esse pelo site.');
        }
        feitos++;
      }
      progresso?.call(feitos, respostas.length);
      return feitos;
    } finally {
      _ocupado = false;
    }
  }

  /// Le os links da pagina atual (menu do Q-Academico) e escolhe boletim/diarios/horario.
  Future<Map<String, String>> _linksDoMenu() async {
    try {
      await QAcademico.guardarPagina('menu', await html());
      final r = await _js('JSON.stringify(Array.from(document.querySelectorAll("a[href]")).map(function(a){'
          'var img = a.querySelector("img[title]");'
          'return [a.innerText || a.title || (img ? img.title : "") || "", a.href];}))');
      final links = (jsonDecode(r) as List).map((e) => (norm('${e[0]}'), '${e[1]}')).where((e) => e.$2.startsWith('http'));
      String? achar(bool Function(String) f) => links.where((e) => f(e.$1)).map((e) => e.$2).firstOrNull;
      return {
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
    if (!NavegadorWeb.suportado) return;
    app.atualizarAcademico = () async {
      final c = _c ??= ColetorQA();
      if (mounted) setState(() {});
      final r = await c.coletar();
      app.questionariosQA = r.situacao == SituacaoQA.questionarios ? r.questionarios : [];
      return r.situacao == SituacaoQA.ok && !r.parcial ? null : r.mensagem;
    };
    app.responderQuestionariosQA = (respostas, progresso) {
      final c = _c ??= ColetorQA();
      if (mounted) setState(() {});
      return c.responderQuestionarios(respostas, progresso: progresso);
    };
  }

  @override
  void dispose() {
    app.atualizarAcademico = null;
    app.responderQuestionariosQA = null;
    _c?.web.descartar();
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
        child: c == null ? const SizedBox.shrink() : IgnorePointer(child: c.web.widget()));
  }
}

/// Tela do Q-Academico: o site de verdade, com os campos de login do app em cima.
class QAcademicoTela extends StatelessWidget {
  const QAcademicoTela({super.key});
  @override
  Widget build(BuildContext context) {
    if (NavegadorWeb.suportado) return const _QAcademicoNavegador();
    return Scaffold(
      appBar: AppBar(title: const Text('Q-Acadêmico')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('A leitura do Q-Acadêmico ainda não funciona nesta plataforma. '
              'Use o app no celular, no Windows ou no macOS para importar notas, faltas e horário.',
              textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class _QAcademicoNavegador extends StatefulWidget {
  const _QAcademicoNavegador();
  @override
  State<_QAcademicoNavegador> createState() => _QAcademicoTelaState();
}

class _QAcademicoTelaState extends State<_QAcademicoNavegador> {
  final _c = ColetorQA();
  final _login = TextEditingController(text: Cfg.qaLogin);
  final _senha = TextEditingController();
  bool _lembrar = false;
  bool _ocupado = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    Cfg.qaSenha().then((s) {
      if (s != null && mounted) {
        setState(() {
          _senha.text = s;
          _lembrar = true;
        });
      }
    });
    _c.abrir(ColetorQA.urlLogin).catchError((_) {});
  }

  @override
  void dispose() {
    _c.web.descartar();
    _login.dispose();
    _senha.dispose();
    super.dispose();
  }

  Future<void> _importar() async {
    setState(() {
      _ocupado = true;
      _msg = 'Entrando e lendo boletim e diários...';
    });
    final login = _login.text.trim();
    final senha = _senha.text;
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
    await guardarCredenciaisQA(r, login: login, senha: senha, lembrar: _lembrar);
    if (!mounted) return;
    if (r.situacao == SituacaoQA.questionarios) {
      // guarda o login: a pessoa entrou certo, só falta a avaliação
      if (login.isNotEmpty) await Cfg.setQaLogin(login);
      if (_lembrar && senha.isNotEmpty) await Cfg.setQaSenha(senha);
      if (!mounted) return;
      setState(() {
        _ocupado = false;
        _msg = r.mensagem;
      });
      final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(
          builder: (_) => QuestionariosTela(
                questionarios: r.questionarios,
                responder: (rs, p) => _c.responderQuestionarios(rs, progresso: p),
              )));
      if (ok == true && mounted) await _importar(); // liberado: importa de novo
      return;
    }
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
        IconButton(tooltip: 'Recarregar', icon: const Icon(Icons.refresh), onPressed: () => _c.web.recarregar()),
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
        Expanded(child: _c.web.widget()),
      ]),
    );
  }
}
