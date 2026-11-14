import 'package:material_ui/material_ui.dart';

import 'armazenamento.dart';
import 'classificar.dart';
import 'config.dart';
import 'fundo.dart';
import 'moodle.dart';
import 'qacademico.dart';
import 'sync.dart';
import 'util.dart';

/// Estado global das telas: snapshot carregado, sincronizacao em andamento, erros.
class AppEstado extends ChangeNotifier {
  Map<String, dynamic> snap = {};
  Map<String, dynamic> estado = {};
  bool logado = false;
  bool carregando = true;
  bool sincronizando = false;
  String progresso = '';
  String? erro;

  String? token;

  /// Q-Academico: disciplinas importadas, quando, e o aviso da ultima tentativa.
  List<Disciplina> academico = [];
  List<Aula> horario = [];
  int academicoEm = 0;
  String? academicoAviso;

  /// Preenchido pela tela inicial (WebView oculto). Devolve null se deu certo, ou a mensagem.
  Future<String?> Function()? atualizarAcademico;

  /// Guarda o que veio do Q-Academico e avisa o que mudou. Devolve quantas disciplinas.
  Future<int> salvarAcademico(List<Disciplina> novas, {List<Aula> horario = const []}) async {
    final mud = mudancasAcademico(academico, novas);
    academico = novas;
    if (horario.isNotEmpty) this.horario = horario;
    academicoEm = agoraSeg();
    academicoAviso = null;
    await QAcademico.salvar({
      'atualizado_em': academicoEm,
      'disciplinas': [for (final d in novas) d.toJson()],
      'horario': [for (final a in this.horario) a.toJson()],
    });
    if (mud.isNotEmpty) {
      final hist = lista(estado['historico']).map(mapa).toList();
      hist.insertAll(0, [for (final t in mud) {'ts': academicoEm, 'curso': 'Q-Acadêmico', 'texto': t, 'tipo': 'nota'}]);
      estado['historico'] = hist.take(300).toList();
      await Store.salvarEstado(estado);
      if (Cfg.notificacoes) {
        final corpo = mud.take(6).map((t) => '• $t').join('\n');
        try {
          await Notif.mostrar(3, '${mud.length} novidade(s) no Q-Acadêmico', corpo);
        } catch (_) {}
      }
    }
    notifyListeners();
    return novas.length;
  }

  /// Todas as materias sincronizadas.
  List<Map<String, dynamic>> get todosCursos => lista(snap['cursos']).map(mapa).toList();

  bool ehAtual(Map<String, dynamic> c) {
    final man = Cfg.atualManual['${c['id']}'];
    return man is bool ? man : c['atual'] != false;
  }

  /// Materias visiveis: so as do semestre atual, a nao ser que "ver todas" esteja ligado.
  List<Map<String, dynamic>> get cursos => Cfg.verTodas ? todosCursos : todosCursos.where(ehAtual).toList();

  /// Frequencia da disciplina, contando a falta de um dia inteiro de aula.
  Frequencia freqDe(Disciplina d) => frequencia(d,
      minima: Cfg.frequenciaMinima.toDouble(), aulasPorDia: aulasPorDia(d.nome, horario, padrao: Cfg.faltasPorDia));

  /// Algo do perfil/ajustes mudou: redesenha as telas.
  void avisarMudanca() => notifyListeners();

  Future<void> alternarVerTodas() async {
    await Cfg.setVerTodas(!Cfg.verTodas);
    notifyListeners();
  }

  Future<void> marcarAtual(dynamic cursoId, bool? v) async {
    await Cfg.setAtualManual(cursoId, v);
    notifyListeners();
  }

  Future<void> marcarCategoria(String chave, String? v) async {
    await Cfg.setCategoriaManual(chave, v);
    notifyListeners();
  }

  Future<void> carregar() async {
    token = await Cfg.token();
    logado = token != null && Cfg.site.isNotEmpty;
    snap = await Store.snapshot();
    estado = await Store.estado();
    final qa = await QAcademico.carregar();
    academico = lista(qa['disciplinas']).map(mapa).map(Disciplina.fromJson).toList();
    academicoEm = (qa['atualizado_em'] as num?)?.toInt() ?? 0;
    horario = lista(qa['horario']).map(mapa).map(Aula.fromJson).toList();
    carregando = false;
    notifyListeners();
  }

  Future<void> sincronizar() async {
    if (sincronizando) return;
    sincronizando = true;
    erro = null;
    progresso = 'Iniciando...';
    notifyListeners();
    try {
      final r = await Sync.rodar(progresso: (p) {
        progresso = p;
        notifyListeners();
      });
      snap = r.snapshot;
      estado = await Store.estado();
      await avisar(r);
      await _sincronizarAcademico();
    } on MoodleErro catch (e) {
      erro = e.msg;
      if (e.sessao) {
        await Cfg.apagarToken();
        logado = false;
      }
    } catch (e) {
      erro = 'Falha ao sincronizar: $e';
    } finally {
      sincronizando = false;
      notifyListeners();
    }
  }

  /// Q-Academico junto com o AVA: so com o app aberto e se a pessoa ja configurou.
  Future<void> _sincronizarAcademico() async {
    final f = atualizarAcademico;
    if (f == null || !Cfg.qaAuto || Cfg.qaLogin.isEmpty) return;
    progresso = 'Lendo Q-Acadêmico...';
    notifyListeners();
    try {
      academicoAviso = await f();
    } catch (e) {
      academicoAviso = 'Falha ao ler o Q-Acadêmico: $e';
    }
  }

  Future<void> aposLogin() async {
    token = await Cfg.token();
    logado = true;
    notifyListeners();
    await agendar();
    await sincronizar();
  }

  Future<void> sair() async {
    await Cfg.sair();
    logado = false;
    notifyListeners();
  }

  /// Tarefas, questionarios e eventos das materias visiveis, futuros (e o que venceu ha
  /// menos de 1 dia), em ordem. Cada item: tipo, item, ts, cat (prova/atividade), curso.
  List<Map<String, dynamic>> prazos() {
    final limite = agoraSeg() - 86400;
    final out = <Map<String, dynamic>>[];
    final visiveis = cursos;
    for (final c in visiveis) {
      final it = itensDoCurso(c);
      out.addAll([...it.atividades, ...it.provas].where((e) => (e['ts'] as int) > limite));
    }
    // eventos de acao do Moodle que nao vieram por outro caminho (ex.: forum com prazo)
    final nomes = visiveis.map((c) => c['nome']).toSet();
    final ids = out.map((e) => '${e['tipo']}:${mapa(e['item'])['id']}').toSet();
    for (final e in lista(snap['eventos']).map(mapa)) {
      final ts = (e['ts'] as num?)?.toInt() ?? 0;
      if (ts <= limite || !nomes.contains(e['curso'])) continue;
      if (e['modulo'] == 'assign' && ids.contains('tarefa:${e['instancia']}')) continue;
      if (e['modulo'] == 'quiz' && ids.contains('quiz:${e['instancia']}')) continue;
      out.add({'tipo': 'acao', 'ts': ts, 'item': e, 'cat': 'atividade', 'curso': {'nome': e['curso']}});
    }
    out.sort((a, b) => (a['ts'] as int).compareTo(b['ts'] as int));
    return out;
  }

  Map<String, dynamic>? cursoPorId(dynamic id) => todosCursos.where((c) => c['id'] == id).firstOrNull;
}

final app = AppEstado();
