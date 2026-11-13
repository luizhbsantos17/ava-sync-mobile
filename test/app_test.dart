// Testes com respostas SIMULADAS da API (nao acessam nenhum Moodle).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/envio.dart';
import 'package:ava_sync_mobile/midia.dart';
import 'package:ava_sync_mobile/moodle.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:ava_sync_mobile/util.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const site = 'https://moodle.exemplo';

final api = <String, dynamic>{
  'core_webservice_get_site_info': {'userid': 5, 'fullname': 'Aluno Teste'},
  'core_course_get_enrolled_courses_by_timeline_classification': {
    'courses': [
      {'id': 10, 'fullname': 'Redes de Computadores', 'enddate': 0},
      {'id': 11, 'fullname': 'Biblioteca Virtual', 'enddate': 0},
      {'id': 12, 'fullname': 'Calculo Antigo', 'enddate': 1000},
    ]
  },
  'mod_assign_get_assignments': {
    'courses': [
      {
        'id': 10,
        'assignments': [
          {
            'id': 1, 'cmid': 99, 'name': 'Relatório Lab', 'duedate': 4102444800, 'grade': 10,
            'intro': '<p>Faça o relatório</p><img src="$site/pluginfile.php/5/mod_assign/intro/fig.png">',
            'introattachments': [{'filename': 'roteiro.pdf', 'fileurl': '$site/webservice/pluginfile.php/5/roteiro.pdf', 'filesize': 3}],
            'requiresubmissionstatement': 1, 'submissiondrafts': 1,
          }
        ]
      }
    ]
  },
  'mod_assign_get_submission_status': {
    'lastattempt': {'submission': {'status': 'new', 'plugins': []}}
  },
  'mod_quiz_get_quizzes_by_courses': {
    'quizzes': [
      {'id': 2, 'course': 10, 'name': 'Prova 1', 'timeopen': 4102444800, 'timeclose': 4102531200, 'coursemodule': 3}
    ]
  },
  'mod_page_get_pages_by_courses': {
    'pages': [
      {'course': 10, 'coursemodule': 21, 'name': 'Leitura', 'intro': '', 'content': '<p>Oi</p><img src="https://fora.exemplo/a.png">'}
    ]
  },
  'mod_forum_get_forums_by_courses': [
    {'id': 3, 'course': 10, 'name': 'Avisos'}
  ],
  'mod_forum_get_forum_discussions': {
    'discussions': [
      {'discussion': 8, 'name': 'Aula cancelada', 'created': 1794900000, 'message': '<p>Sem aula</p>', 'userfullname': 'Prof'}
    ]
  },
  'core_calendar_get_action_events_by_timesort': {'events': []},
  'core_course_get_contents': [
    {
      'name': 'Semana 1',
      'summary': '<p>Leia</p>',
      'modules': [
        {
          'id': 20, 'name': 'Slides', 'modname': 'resource',
          'contents': [{'type': 'file', 'filename': 'slides.pdf', 'filepath': '/', 'fileurl': '$site/webservice/pluginfile.php/7/slides.pdf', 'filesize': 3}]
        },
        {'id': 21, 'name': 'Leitura', 'modname': 'page'},
        {
          'id': 22, 'name': 'Livro de Redes', 'modname': 'book',
          'contents': [
            {
              'type': 'content', 'filename': 'structure',
              'content': jsonEncode([
                {'title': 'Introdução', 'href': '31/index.html', 'subitems': [{'title': 'Detalhe', 'href': '32/index.html'}]}
              ])
            },
            {'type': 'file', 'filename': 'index.html', 'filepath': '/32/', 'fileurl': '$site/webservice/pluginfile.php/9/mod_book/chapter/32/index.html'},
            {'type': 'file', 'filename': 'index.html', 'filepath': '/31/', 'fileurl': '$site/webservice/pluginfile.php/9/mod_book/chapter/31/index.html'},
          ]
        },
        {
          'id': 23, 'name': 'Lista em PDF', 'modname': 'url',
          'contents': [{'type': 'url', 'fileurl': 'https://prof.exemplo/lista.pdf'}]
        },
        {
          'id': 24, 'name': 'Vídeo', 'modname': 'url',
          'contents': [{'type': 'url', 'fileurl': 'https://www.youtube.com/watch?v=x'}]
        },
        {'id': 25, 'name': '', 'modname': 'label', 'description': '<img src="$site/pluginfile.php/5/mod_label/intro/esquema.png">'},
        {'id': 26, 'name': 'Oculto', 'modname': 'resource', 'uservisible': false},
      ]
    }
  ],
};

final chamadas = <String>[];
final externos = <String>[];

http.Client clienteMoodle() => MockClient((req) async {
      final url = req.url.toString();
      expect(req.url.host, 'moodle.exemplo', reason: 'cliente do Moodle so fala com o Moodle');
      if (req.url.path.endsWith('/webservice/rest/server.php')) {
        final f = req.bodyFields['wsfunction']!;
        chamadas.add(f);
        expect(req.bodyFields['wstoken'], 'TOK');
        return http.Response(jsonEncode(api[f] ?? {}), 200, headers: {'content-type': 'application/json'});
      }
      expect(url, contains('token=TOK'));
      if (url.contains('/mod_book/chapter/')) {
        final cap = url.split('/chapter/')[1].split('/').first;
        return http.Response('<p>Capítulo $cap</p><img src="$site/webservice/pluginfile.php/9/mod_book/chapter/$cap/f.png">', 200,
            headers: {'content-type': 'text/html; charset=utf-8'});
      }
      return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'application/octet-stream'});
    });

http.Client clienteExterno() => MockClient((req) async {
      externos.add(req.url.toString());
      expect(req.url.toString(), isNot(contains('token')), reason: 'token nunca vai para site externo');
      expect(req.url.host, isNot('moodle.exemplo'));
      final ct = req.url.path.endsWith('.pdf') ? 'application/pdf' : 'image/png';
      return http.Response.bytes([9, 9], 200, headers: {'content-type': ct});
    });

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'site': site});
    await Cfg.init();
    tmp = await Directory.systemTemp.createTemp('avasync_');
    Store.baseTeste = tmp;
    chamadas.clear();
    externos.clear();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('parametros aninhados viram formulario do Moodle', () {
    expect(
        Moodle.achatar({
          'courseids': [10, 11],
          'plugindata': {
            'files_filemanager': 7,
            'onlinetext_editor': {'text': 'oi', 'format': 1}
          },
          'aceito': true,
        }),
        {
          'courseids[0]': '10',
          'courseids[1]': '11',
          'plugindata[files_filemanager]': '7',
          'plugindata[onlinetext_editor][text]': 'oi',
          'plugindata[onlinetext_editor][format]': '1',
          'aceito': '1',
        });
  });

  test('url de arquivo do Moodle recebe token via webservice', () {
    final m = Moodle(site, 'TOK', cliente: clienteMoodle());
    expect(m.comToken('$site/pluginfile.php/1/a.png'), '$site/webservice/pluginfile.php/1/a.png?token=TOK');
    expect(m.comToken('$site/webservice/pluginfile.php/1/a.png?forcedownload=1'),
        '$site/webservice/pluginfile.php/1/a.png?forcedownload=1&token=TOK');
    expect(() => m.baixar('https://outro.exemplo/x.pdf', File('${tmp.path}/x')), throwsA(isA<MoodleErro>()));
  });

  test('token invalido vira erro de sessao', () async {
    final m = Moodle(site, 'TOK',
        cliente: MockClient((_) async => http.Response(jsonEncode({'exception': 'x', 'errorcode': 'invalidtoken'}), 200)));
    expect(() => m.call('core_webservice_get_site_info'), throwsA(predicate((e) => e is MoodleErro && e.sessao)));
  });

  test('imagens: do Moodle com token, externas sem token, data: intacta', () async {
    final m = Moodle(site, 'TOK', cliente: clienteMoodle());
    final mi = Midia(m, Directory('${tmp.path}/_imagens'), externo: clienteExterno());
    final h = await mi.html('<img src="$site/pluginfile.php/5/x/diagrama%20A.png"><img src=\'https://fora.exemplo/f.jpg\'>'
        '<img src="data:image/png;base64,AAA">');
    expect(RegExp('src="${RegExp.escape(tmp.path)}/_imagens/').allMatches(h).length, 1);
    expect(h, contains("src='${tmp.path}/_imagens/"));
    expect(h, contains('data:image/png;base64,AAA'));
    expect(externos, ['https://fora.exemplo/f.jpg']);
  });

  test('sync completo: filtro, livro, links, imagens e novidades', () async {
    final m = Moodle(site, 'TOK', cliente: clienteMoodle());
    final r1 = await Sync.rodar(moodle: m, externo: clienteExterno(), baixarArquivos: true);
    final cursos = lista(r1.snapshot['cursos']).map(mapa).toList();
    expect(cursos.map((c) => c['nome']), ['Redes de Computadores']);
    expect(r1.novidades, isEmpty, reason: 'primeira sincronizacao nao notifica tudo como novo');

    final c = cursos.first;
    final mods = lista(mapa(lista(c['secoes']).first)['modulos']).map(mapa).toList();
    expect(mods.map((x) => x['nome']), isNot(contains('Oculto')));

    final slides = mods.firstWhere((x) => x['nome'] == 'Slides');
    expect(File('${mapa(lista(slides['arquivos']).first)['caminho']}').existsSync(), isTrue);

    final livro = File('${mods.firstWhere((x) => x['tipo'] == 'book')['html']}').readAsStringSync();
    expect(livro.indexOf('Introdução</h2>'), lessThan(livro.indexOf('Detalhe</h3>')));
    expect(livro.indexOf('Capítulo 31'), lessThan(livro.indexOf('Capítulo 32')));
    expect(livro, contains('src="${tmp.path}/'));

    final pdf = mods.firstWhere((x) => x['nome'] == 'Lista em PDF');
    expect(lista(pdf['arquivos']), hasLength(1));
    final video = mods.firstWhere((x) => x['nome'] == 'Vídeo');
    expect(video['externo'], contains('youtube'));
    expect(lista(video['arquivos']), isEmpty);
    expect(externos.any((u) => u.contains('youtube')), isFalse);

    final pagina = File('${mods.firstWhere((x) => x['tipo'] == 'page')['html']}').readAsStringSync();
    expect(pagina, contains('src="${tmp.path}/'));

    final t = mapa(lista(c['tarefas']).first);
    expect(t['situacao'], 'new');
    expect(t['declaracao'], isTrue);
    expect('${t['html']}', contains(tmp.path));
    expect(File('${mapa(lista(t['anexos']).first)['caminho']}').existsSync(), isTrue);

    // segunda vez: nada novo; depois aparece um aviso novo
    final r2 = await Sync.rodar(moodle: m, externo: clienteExterno(), baixarArquivos: true);
    expect(r2.novidades, isEmpty);
    (api['mod_forum_get_forum_discussions']['discussions'] as List)
        .add({'discussion': 9, 'name': 'Prova adiada', 'created': 1794990000, 'message': 'x'});
    final r3 = await Sync.rodar(moodle: m, externo: clienteExterno(), baixarArquivos: true);
    expect(r3.novidades.map((n) => n['texto']), ['Aviso: Prova adiada']);
    expect(lista((await Store.estado())['historico']).length, 2);
  });

  test('envio: confirmacao, declaracao e warnings', () async {
    final arq = (nome: 'a.pdf', bytes: Uint8List.fromList([1]));
    expect(PedidoEnvio(tarefaId: 1, arquivos: [arq], confirmacao: 'enviar').problema(), contains('ENVIAR'));
    expect(PedidoEnvio(tarefaId: 1, arquivos: [], confirmacao: 'ENVIAR').problema(), isNotNull);
    expect(
        PedidoEnvio(tarefaId: 1, arquivos: [arq], finalizar: true, exigeDeclaracao: true, confirmacao: 'ENVIAR').problema(),
        contains('declaração'));
    expect(PedidoEnvio(tarefaId: 1, arquivos: [arq], confirmacao: 'ENVIAR').problema(), isNull);

    // sem confirmacao nao chama o Moodle
    var chamou = false;
    final mNada = Moodle(site, 'TOK', cliente: MockClient((_) async {
      chamou = true;
      return http.Response('[]', 200);
    }));
    await expectLater(Envio.executar(mNada, PedidoEnvio(tarefaId: 1, arquivos: [arq], confirmacao: ''), 5),
        throwsA(isA<MoodleErro>()));
    expect(chamou, isFalse);

    final funcs = <String>[];
    final m = Moodle(site, 'TOK', cliente: MockClient((req) async {
      if (req.url.path.endsWith('/upload.php')) return http.Response(jsonEncode([{'itemid': 77}]), 200);
      final f = req.bodyFields['wsfunction']!;
      funcs.add(f);
      if (f == 'mod_assign_save_submission') {
        expect(req.bodyFields['plugindata[files_filemanager]'], '77');
        return http.Response('[]', 200);
      }
      if (f == 'mod_assign_submit_for_grading') {
        expect(req.bodyFields['acceptsubmissionstatement'], '1');
        return http.Response(jsonEncode([{'item': 'x', 'message': 'Prazo encerrado'}]), 200);
      }
      return http.Response(jsonEncode({'lastattempt': {'submission': {'status': 'submitted'}}}), 200);
    }));
    final rascunho = await Envio.executar(m, PedidoEnvio(tarefaId: 1, arquivos: [arq], confirmacao: 'ENVIAR'), 5);
    expect(rascunho.status, 'submitted');
    expect(funcs, isNot(contains('mod_assign_submit_for_grading')));
    await expectLater(
        Envio.executar(
            m,
            PedidoEnvio(
                tarefaId: 1, arquivos: [arq], finalizar: true, exigeDeclaracao: true, aceitouDeclaracao: true, confirmacao: 'ENVIAR'),
            5),
        throwsA(predicate((e) => '$e'.contains('Prazo encerrado'))));
  });

  test('filtro de cursos', () {
    final c = [
      {'fullname': 'Redes 2026/2', 'enddate': 0},
      {'fullname': 'Biblioteca Virtual', 'enddate': 0},
      {'fullname': 'Velho', 'enddate': 10},
    ];
    expect(Sync.filtrarCursos(c, 100, ignorar: ['biblioteca'], somente: []).map((x) => x['fullname']), ['Redes 2026/2']);
    expect(Sync.filtrarCursos(c, 100, ignorar: [], somente: ['bibli']).map((x) => x['fullname']), ['Biblioteca Virtual']);
  });
}
