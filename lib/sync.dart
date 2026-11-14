import 'dart:io';

import 'package:http/http.dart' as http;

import 'armazenamento.dart';
import 'classificar.dart';
import 'config.dart';
import 'midia.dart';
import 'moodle.dart';
import 'util.dart';

const situacoes = {
  'new': 'Não entregue',
  'draft': 'Rascunho (não enviado)',
  'submitted': 'Entregue',
  'reopened': 'Reaberta',
};

const versaoAvisos = 2;

/// Compara a tarefa com o que ja foi visto e devolve as novidades (texto + tipo).
/// Registra as chaves em [vistos]. Com [silencioso], so registra.
List<Map<String, dynamic>> mudancasTarefa(Map<String, dynamic> t, Map<String, dynamic> vistos, int agora,
    {bool silencioso = false}) {
  final out = <Map<String, dynamic>>[];
  final id = t['id'];
  final nome = t['nome'];
  void marca(String chave, String texto, String tipo) {
    if (!vistos.containsKey(chave) && !silencioso) out.add({'texto': texto, 'tipo': tipo});
    vistos[chave] = agora;
  }

  final entrega = (t['entrega'] as num?)?.toInt() ?? 0;
  final corte = (t['corte'] as num?)?.toInt() ?? 0;
  final entregue = t['situacao'] == 'submitted';
  if (entregue) marca('entregue:$id', 'Entrega registrada: $nome', 'entrega');
  final nota = '${t['nota'] ?? ''}'.trim();
  if (nota.isNotEmpty && nota != '-') marca('nota:$id:$nota', 'Nota publicada em $nome: $nota', 'nota');

  // prazo alterado: compara com o ultimo prazo registrado desta tarefa
  final chavePrazo = 'prazo:$id';
  final antes = (vistos['${chavePrazo}_ts'] as num?)?.toInt();
  if (antes != null && entrega > 0 && antes != entrega && !silencioso) {
    out.add({'texto': 'Prazo alterado: $nome (agora ${fmtData(entrega)})', 'tipo': 'tarefa'});
  }
  if (entrega > 0) vistos['${chavePrazo}_ts'] = entrega;

  // venceu sem entrega
  if (!entregue && entrega > 0 && entrega <= agora && agora - entrega < 7 * 86400) {
    final aindaAceita = corte > agora;
    marca(
        'vencida:$id:$entrega',
        aindaAceita
            ? 'Prazo encerrado sem entrega: $nome (ainda aceita até ${fmtData(corte)})'
            : 'Prazo encerrado sem entrega: $nome',
        'tarefa');
  }
  return out;
}

class ResultadoSync {
  final List<Map<String, dynamic>> novidades;
  final Map<String, dynamic> snapshot;
  ResultadoSync(this.novidades, this.snapshot);
}

/// Sincronizacao: le o Moodle (somente leitura) e grava snapshot.json + arquivos.
class Sync {
  static bool rodando = false;

  static List<Map<String, dynamic>> filtrarCursos(List<Map<String, dynamic>> cursos, int agora,
      {List<String>? ignorar, List<String>? somente}) {
    final ign = (ignorar ?? Cfg.ignorarCursos).map((s) => s.toLowerCase()).where((s) => s.isNotEmpty);
    final som = (somente ?? Cfg.somenteCursos).map((s) => s.toLowerCase()).where((s) => s.isNotEmpty).toList();
    return cursos.where((c) {
      final nome = '${c['fullname'] ?? ''}'.toLowerCase();
      if (som.isNotEmpty && !som.any(nome.contains)) return false;
      if (ign.any(nome.contains)) return false;
      return true; // encerrado ou nao, quem decide e a deteccao de semestre atual
    }).toList();
  }

  static Future<ResultadoSync> rodar({
    void Function(String)? progresso,
    Moodle? moodle,
    http.Client? externo,
    bool? baixarArquivos,
  }) async {
    if (rodando) throw MoodleErro('Já existe uma sincronização em andamento.');
    rodando = true;
    try {
      final tok = moodle == null ? await Cfg.token() : 'x';
      if (tok == null || Cfg.site.isEmpty) throw MoodleErro('Faça login primeiro.', sessao: true);
      final m = moodle ?? Moodle(Cfg.site, tok);
      return await _rodar(m, progresso ?? (_) {}, externo, baixarArquivos ?? Cfg.baixarArquivos);
    } finally {
      rodando = false;
    }
  }

  static Future<ResultadoSync> _rodar(
      Moodle m, void Function(String) progresso, http.Client? externo, bool baixarGeral) async {
    final agora = agoraSeg();
    final base = await Store.base();
    final estado = await Store.estado();
    final vistos = mapa(estado['vistos']);
    final primeiraVez = vistos.isEmpty;
    // versoes antigas nao registravam entrega/nota/prazo: na primeira vez so registra, sem avisar
    final silencioso = primeiraVez || estado['v_avisos'] != versaoAvisos;
    final novidades = <Map<String, dynamic>>[];
    progresso('Conectando...');
    final site = mapa(await m.call('core_webservice_get_site_info'));
    final userid = site['userid'];
    await Cfg.setUsuarioNome('${site['fullname'] ?? ''}');

    // TODAS as materias em que a pessoa esta inscrita. A lista "em andamento" do Moodle
    // deixa de fora curso com data de inicio no futuro, data de fim errada ou que a pessoa
    // escondeu do painel. Quem decide o que aparece e a deteccao de semestre atual.
    var todos = lista(await m.tentar('core_enrol_get_users_courses', null, {'userid': userid})).map(mapa).toList();
    if (todos.isEmpty) {
      final vistosIds = <dynamic>{};
      for (final cl in ['inprogress', 'future', 'past', 'hidden']) {
        final r = lista(mapa(await m.tentar('core_course_get_enrolled_courses_by_timeline_classification', {},
                {'classification': cl}))['courses'])
            .map(mapa);
        todos.addAll(r.where((c) => vistosIds.add(c['id'])));
      }
    }
    // cursos muito antigos (mais de ~2 anos) nem entram, para nao pesar a sincronizacao
    todos = todos.where((c) {
      final ini = (c['startdate'] as num?)?.toInt() ?? 0;
      return ini == 0 || ini > agora - 730 * 86400;
    }).toList();
    final cursos = filtrarCursos(todos, agora);
    final ids = cursos.map((c) => c['id']).toList();

    progresso('Lendo tarefas, provas e avisos...');
    final assigns = mapa(await m.tentar('mod_assign_get_assignments', {}, {'courseids': ids}));
    final quizzes = mapa(await m.tentar('mod_quiz_get_quizzes_by_courses', {}, {'courseids': ids}));
    final pages = mapa(await m.tentar('mod_page_get_pages_by_courses', {}, {'courseids': ids}));
    final foruns = lista(await m.tentar('mod_forum_get_forums_by_courses', [], {'courseids': ids})).map(mapa);
    final eventos = mapa(await m.tentar('core_calendar_get_action_events_by_timesort', {},
        {'timesortfrom': agora - 7 * 86400, 'limitnum': 50}));
    // todos os eventos dos cursos (inclui provas presenciais marcadas pelo professor)
    final calendario = mapa(await m.tentar('core_calendar_get_calendar_events', {}, {
      'events': {'courseids': ids},
      'options': {'userevents': 0, 'siteevents': 0, 'timestart': agora - 150 * 86400, 'timeend': agora + 240 * 86400},
    }));

    // semestre atual: so estas baixam arquivos e geram notificacoes
    final atividade = <String, int>{};
    void marca(dynamic cid, dynamic ts) {
      final v = (ts as num?)?.toInt() ?? 0;
      if (v > (atividade['$cid'] ?? 0)) atividade['$cid'] = v;
    }
    for (final c in cursos) {
      marca(c['id'], c['lastaccess']);
    }
    for (final c in lista(assigns['courses']).map(mapa)) {
      for (final a in lista(c['assignments']).map(mapa)) {
        marca(c['id'], a['duedate']);
      }
    }
    for (final q in lista(quizzes['quizzes']).map(mapa)) {
      marca(q['course'], q['timeclose']);
    }
    final atuais = cursosAtuais(cursos, atividade, agora);

    final assignPorCurso = {
      for (final c in lista(assigns['courses']).map(mapa)) c['id']: lista(c['assignments']).map(mapa).toList()
    };
    final paginaPorCm = {for (final p in lista(pages['pages']).map(mapa)) p['coursemodule']: p};
    final maxMb = Cfg.maxMb;

    final cursosOut = <Map<String, dynamic>>[];
    for (final c in cursos) {
      final cid = c['id'];
      final nomeCurso = '${c['fullname'] ?? c['shortname'] ?? 'Curso'}';
      final atual = atuais['$cid'] ?? true;
      final baixar = baixarGeral && atual;
      progresso(nomeCurso);
      final pasta = Directory('${base.path}/${nomeSeguro(nomeCurso)}');
      final midia = Midia(m, Directory('${pasta.path}/_imagens'), externo: externo, baixar: baixar, maxMb: maxMb);
      void nova(String chave, String curso, String texto, {String tipo = '', Map<String, dynamic>? ref}) {
        if (!vistos.containsKey(chave) && atual) {
          novidades.add({'ts': agora, 'curso': curso, 'texto': texto, 'tipo': tipo, ...?ref});
        }
        vistos[chave] = agora;
      }

      // 1) conteudo: secoes e modulos
      final secoesOut = <Map<String, dynamic>>[];
      final secoes = lista(await m.tentar('core_course_get_contents', [], {'courseid': cid})).map(mapa).toList();
      for (final sec in secoes) {
        final nomeSec = '${sec['name'] ?? 'Seção'}';
        final pastaSec = '${pasta.path}/Materiais/${nomeSeguro(nomeSec, 50)}';
        final mods = <Map<String, dynamic>>[];
        for (final mod in lista(sec['modules']).map(mapa)) {
          if (mod['uservisible'] == false) continue;
          final tipo = '${mod['modname'] ?? ''}';
          final nomeMod = '${mod['name'] ?? ''}';
          final mo = <String, dynamic>{
            'id': mod['id'],
            'nome': nomeMod,
            'tipo': tipo,
            'link': mod['url'],
            'desc': await midia.html(mod['description']),
            'arquivos': <Map<String, dynamic>>[],
          };
          try {
            if (tipo == 'book' && baixar) {
              final f = File('$pastaSec/${nomeSeguro(nomeMod)}/LIVRO.html');
              if (await midia.salvarLivro(mod, f)) {
                nova('livro:${mod['id']}:${await f.length()}', nomeCurso, 'Livro novo/atualizado: $nomeMod',
                    tipo: 'material');
              }
              if (await f.exists()) mo['html'] = f.path;
            } else if (tipo == 'page') {
              final p = paginaPorCm[mod['id']];
              if (p != null) {
                final f = File('${pasta.path}/Materiais/Paginas/${nomeSeguro(nomeMod)}.html');
                final corpo = '${await midia.html(p['intro'])}\n${await midia.html(p['content'])}';
                await escreverSeMudou(f, corpo);
                mo['html'] = f.path;
              }
            } else if (tipo == 'url') {
              final arq = lista(mod['contents']).map(mapa).where((x) => x['type'] == 'url').firstOrNull;
              final url = '${arq?['fileurl'] ?? ''}';
              if (url.isNotEmpty) {
                mo['externo'] = url;
                if (Cfg.baixarLinks && baixar) {
                  final f = await midia.baixarLink(url, nomeMod, Directory('$pastaSec/Links'), maxMb);
                  if (f != null) {
                    mo['arquivos'].add({'nome': f.uri.pathSegments.last, 'caminho': f.path, 'tamanho': await f.length()});
                    nova('link:${mod['id']}', nomeCurso, 'Arquivo de link salvo: $nomeMod', tipo: 'material');
                  }
                }
              }
            } else if (tipo == 'resource' || tipo == 'folder' || tipo == 'imscp') {
              for (final arq in lista(mod['contents']).map(mapa).where((x) => x['type'] == 'file')) {
                // mantem as subpastas: um HTML com imagens/CSS em pastas continua abrindo
                final sub = '${arq['filepath'] ?? '/'}'
                    .split('/')
                    .where((s) => s.isNotEmpty)
                    .map((s) => nomeSeguro(s, 60))
                    .join('/');
                var dir = pastaSec;
                if (tipo == 'imscp') dir = '$dir/${nomeSeguro(nomeMod, 60)}';
                if (sub.isNotEmpty) dir = '$dir/$sub';
                final f = File('$dir/${nomeSeguro('${arq['filename']}', 120)}');
                final tam = (arq['filesize'] as num?)?.toInt() ?? 0;
                if (baixar) {
                  try {
                    if (await m.baixar('${arq['fileurl']}', f, tamanho: tam, maxMb: maxMb)) {
                      nova('arq:${f.path}:$tam', nomeCurso, 'Material novo: ${arq['filename']}', tipo: 'material');
                    }
                  } on MoodleErro catch (e) {
                    if (e.sessao) rethrow;
                  } catch (_) {}
                }
                vistos.putIfAbsent('arq:${f.path}:$tam', () => agora);
                mo['arquivos'].add({
                  'nome': '${arq['filename']}',
                  'caminho': f.path,
                  'url': arq['fileurl'],
                  'tamanho': tam,
                });
              }
            }
          } on MoodleErro catch (e) {
            if (e.sessao) rethrow;
          } catch (_) {}
          mods.add(mo);
        }
        secoesOut.add({'nome': nomeSec, 'resumo': await midia.html(sec['summary']), 'modulos': mods});
      }

      // 2) tarefas
      final tarefasOut = <Map<String, dynamic>>[];
      for (final a in assignPorCurso[cid] ?? const <Map<String, dynamic>>[]) {
        final st = mapa(await m.tentar('mod_assign_get_submission_status', {}, {'assignid': a['id'], 'userid': userid}));
        final sub = mapa(mapa(st['lastattempt'])['submission']);
        final enviados = <String>[];
        for (final pl in lista(sub['plugins']).map(mapa)) {
          for (final fa in lista(pl['fileareas']).map(mapa)) {
            for (final f in lista(fa['files']).map(mapa)) {
              enviados.add('${f['filename']}');
            }
          }
        }
        final pastaAnexos = '${pasta.path}/Atividades/${nomeSeguro('${a['name']}')}_anexos';
        final anexos = <Map<String, dynamic>>[];
        for (final f in lista(a['introattachments']).map(mapa)) {
          final dest = File('$pastaAnexos/${nomeSeguro('${f['filename']}', 120)}');
          if (baixar) {
            try {
              await m.baixar('${f['fileurl']}', dest, tamanho: (f['filesize'] as num?)?.toInt(), maxMb: maxMb);
            } on MoodleErro catch (e) {
              if (e.sessao) rethrow;
            } catch (_) {}
          }
          anexos.add({'nome': '${f['filename']}', 'caminho': dest.path, 'url': f['fileurl'], 'tamanho': f['filesize']});
        }
        final atividade = a['activity'] == null || '${a['activity']}'.isEmpty
            ? ''
            : '<h3>Instruções da atividade</h3>${a['activity']}';
        final t = {
          'id': a['id'],
          'cmid': a['cmid'],
          'nome': '${a['name']}',
          'curso': nomeCurso,
          'cursoId': cid,
          'entrega': a['duedate'],
          'corte': a['cutoffdate'],
          'abre': a['allowsubmissionsfromdate'],
          'notaMax': a['grade'],
          'situacao': '${sub['status'] ?? 'new'}',
          'nota': mapa(st['feedback'])['gradefordisplay'],
          'html': await midia.html('${a['intro'] ?? ''}$atividade'),
          'anexos': anexos,
          'enviados': enviados,
          'declaracao': a['requiresubmissionstatement'] == 1 || a['requiresubmissionstatement'] == true,
          'textoDeclaracao': semHtml('${a['submissionstatement'] ?? ''}'),
          'rascunhos': a['submissiondrafts'] == 1 || a['submissiondrafts'] == true,
          'link': '${m.site}/mod/assign/view.php?id=${a['cmid']}',
        };
        // mudancas em tarefa que ja conhecemos: entrega registrada, nota, prazo alterado, prazo vencido
        if (vistos.containsKey('assign:${a['id']}')) {
          for (final mud in mudancasTarefa(t, vistos, agora, silencioso: silencioso)) {
            if (atual) novidades.add({'ts': agora, 'curso': nomeCurso, ...mud, 'tarefaId': a['id']});
          }
        }
        nova('assign:${a['id']}', nomeCurso, 'Tarefa nova: ${a['name']} (entrega ${fmtData(a['duedate'])})',
            tipo: 'tarefa', ref: {'tarefaId': a['id']});
        tarefasOut.add(t);
      }

      // 3) questionarios / provas
      final provasOut = <Map<String, dynamic>>[];
      for (final q in lista(quizzes['quizzes']).map(mapa).where((q) => q['course'] == cid)) {
        provasOut.add({
          'id': q['id'],
          'nome': '${q['name']}',
          'curso': nomeCurso,
          'abre': q['timeopen'],
          'fecha': q['timeclose'],
          'limite': q['timelimit'],
          'tentativas': q['attempts'],
          'html': await midia.html(q['intro']),
          'link': '${m.site}/mod/quiz/view.php?id=${q['coursemodule']}',
        });
        nova('quiz:${q['id']}', nomeCurso, 'Questionário/prova: ${q['name']} (fecha ${fmtData(q['timeclose'])})',
            tipo: 'prova');
      }

      // 4) avisos e foruns
      final avisosOut = <Map<String, dynamic>>[];
      for (final fo in foruns.where((f) => f['course'] == cid)) {
        final disc = mapa(await m.tentar('mod_forum_get_forum_discussions', {},
            {'forumid': fo['id'], 'sortorder': 1, 'page': 0, 'perpage': 15}));
        for (final d in lista(disc['discussions']).map(mapa)) {
          avisosOut.add({
            'id': d['discussion'],
            'titulo': '${d['name']}',
            'forum': '${fo['name']}',
            'autor': '${d['userfullname'] ?? ''}',
            'data': d['created'],
            'html': await midia.html(d['message']),
            'link': '${m.site}/mod/forum/discuss.php?d=${d['discussion']}',
          });
          nova('post:${d['discussion']}', nomeCurso, 'Aviso: ${d['name']}', tipo: 'aviso');
        }
      }
      avisosOut.sort((a, b) => ((b['data'] ?? 0) as num).compareTo((a['data'] ?? 0) as num));

      final eventosCurso = <Map<String, dynamic>>[];
      // provas presenciais que so aparecem no cronograma (tabela no texto do curso)
      final inicio = deSeg(c['startdate']) ?? DateTime.now();
      final textosCurso = [
        for (final s in secoes) ...[
          '${s['summary'] ?? ''}',
          for (final mo in lista(s['modules']).map(mapa)) '${mo['description'] ?? ''}',
        ]
      ].join('\n');
      final doCalendario = lista(calendario['events']).map(mapa).where((e) => e['courseid'] == cid).toList();
      for (final p in provasDoCronograma(textosCurso, inicio)) {
        final dia = fmtData(p['ts'], hora: false);
        if (doCalendario.any((e) => fmtData(e['timestart'], hora: false) == dia && pareceProva('${e['name']}'))) continue;
        eventosCurso.add({...p, 'link': '${m.site}/course/view.php?id=$cid'});
        nova('evento:${p['id']}', nomeCurso, 'Prova no cronograma: ${p['nome']} (${fmtData(p['ts'], hora: false)})',
            tipo: 'prova');
      }
      for (final e in lista(calendario['events']).map(mapa).where((e) => e['courseid'] == cid)) {
        final mod = '${e['modulename'] ?? ''}';
        if (mod == 'assign' || mod == 'quiz') continue; // ja aparecem como tarefa/questionario
        eventosCurso.add({
          'id': e['id'],
          'nome': '${e['name']}',
          'ts': e['timestart'],
          'duracao': e['timeduration'],
          'html': await midia.html(e['description']),
          'link': '${m.site}/calendar/view.php?view=day&course=$cid&time=${e['timestart']}',
        });
        if (pareceProva('${e['name']}')) {
          nova('evento:${e['id']}', nomeCurso, 'Prova no calendário: ${e['name']} (${fmtData(e['timestart'])})',
              tipo: 'prova');
        }
      }

      cursosOut.add({
        'id': cid,
        'nome': nomeCurso,
        'atual': atual,
        'inicio': c['startdate'],
        'eventos': eventosCurso,
        'pasta': pasta.path,
        'link': '${m.site}/course/view.php?id=$cid',
        'secoes': secoesOut,
        'tarefas': tarefasOut,
        'provas': provasOut,
        'avisos': avisosOut,
      });
    }

    final eventosOut = [
      for (final e in lista(eventos['events']).map(mapa))
        {
          'nome': '${e['name']}',
          'ts': e['timesort'],
          'curso': '${mapa(e['course'])['fullname'] ?? ''}',
          'link': e['url'],
          'modulo': e['modulename'],
          'instancia': e['instance'],
        }
    ];

    final snap = {
      'gerado_em': agora,
      'usuario': site['fullname'],
      'userid': userid,
      'site': m.site,
      'cursos': cursosOut,
      'eventos': eventosOut,
    };
    await Store.salvarSnapshot(snap);

    // na primeira sincronizacao tudo e "novo": registra, mas nao enche o historico
    final hist = lista(estado['historico']).map(mapa).toList();
    if (primeiraVez) {
      hist.insert(0, {'ts': agora, 'curso': '', 'texto': 'Primeira sincronização: ${cursos.length} matérias', 'tipo': 'info'});
    } else {
      hist.insertAll(0, novidades);
    }
    estado['historico'] = hist.take(300).toList();
    estado['vistos'] = vistos;
    estado['v_avisos'] = versaoAvisos;
    estado['ultima'] = agora;
    await Store.salvarEstado(estado);
    progresso('Pronto');
    return ResultadoSync(primeiraVez ? [] : novidades, snap);
  }
}
