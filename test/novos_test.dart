// Semestre atual, atividade x prova, links do Moodle, cores e IAs separadas.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:ava_sync_mobile/classificar.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/ia.dart';
import 'package:ava_sync_mobile/midia.dart';
import 'package:ava_sync_mobile/moodle.dart';
import 'package:ava_sync_mobile/util.dart';
import 'package:ava_sync_mobile/telas/comum.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const site = 'https://moodle.exemplo';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'site': site});
    FlutterSecureStorage.setMockInitialValues({});
    await Cfg.init();
    tmp = Directory.systemTemp.createTempSync('avasync_n_');
    Store.baseTeste = tmp;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  maisTestes();

  test('semestre no nome', () {
    expect(semestreDoNome('Projeto de Sistemas (2026-2)'), 20262);
    expect(semestreDoNome('Redes 2026/1'), 20261);
    expect(semestreDoNome('Calculo 2025.2 turma A'), 20252);
    expect(semestreDoNome('Álgebra Linear'), isNull);
  });

  test('semestre atual: nome, data de inicio, atividade e ajuste manual', () {
    const dia = 86400;
    final agora = 1800000000;
    final cursos = [
      {'id': 1, 'fullname': 'PS (2026-2)', 'startdate': agora - 90 * dia},
      {'id': 2, 'fullname': 'Sociologia (2026-1)', 'startdate': agora - 260 * dia},
      {'id': 3, 'fullname': 'Redes', 'startdate': agora - 95 * dia},
      {'id': 4, 'fullname': 'Comunicação', 'startdate': agora - 280 * dia},
      {'id': 5, 'fullname': 'Sem data', 'startdate': 0},
    ];
    final r = cursosAtuais(cursos, {'5': agora - 200 * dia}, agora, manual: {});
    expect(r, {'1': true, '2': false, '3': true, '4': false, '5': false});
    final m = cursosAtuais(cursos, {}, agora, manual: {'4': true, '1': false});
    expect(m['4'], isTrue);
    expect(m['1'], isFalse);
  });

  test('atividade x prova', () async {
    expect(categoria('tarefa', {'id': 1, 'nome': 'Relatório de laboratório'}), 'atividade');
    expect(categoria('tarefa', {'id': 2, 'nome': 'Avaliação 3 - relatório'}), 'atividade');
    expect(categoria('tarefa', {'id': 3, 'nome': 'Prova 1 - envio das respostas'}), 'prova');
    expect(categoria('quiz', {'id': 4, 'nome': 'Questionário semana 2'}), 'atividade');
    expect(categoria('quiz', {'id': 5, 'nome': 'Questionário semana 3', 'limite': 3600}), 'prova');
    expect(categoria('quiz', {'id': 6, 'nome': 'Avaliação N2'}), 'prova');
    expect(categoria('evento', {'id': 7, 'nome': 'N5 - prova presencial'}), 'prova');
    expect(categoria('evento', {'id': 8, 'nome': 'Feriado'}), 'atividade');
    await Cfg.setCategoriaManual('tarefa:1', 'prova');
    expect(categoria('tarefa', {'id': 1, 'nome': 'Relatório de laboratório'}), 'prova');
  });

  test('link para arquivo do Moodle dentro do texto e baixado', () async {
    final urls = <String>[];
    final m = Moodle(site, 'TOK', cliente: MockClient((req) async {
      urls.add(req.url.toString());
      return http.Response.bytes([1, 2, 3], 200, headers: {'content-type': 'application/pdf'});
    }));
    final mi = Midia(m, Directory('${tmp.path}/c/_imagens'));
    final h = await mi.html('<p><a href="$site/pluginfile.php/9/mod_label/intro/notas%20aula.pdf">Notas</a> '
        '<a href="$site/mod/page/view.php?id=4">Página</a> <a href="https://fora.exemplo/x">Fora</a></p>');
    expect(h, contains('href="${tmp.path}/c/_arquivos/'));
    expect(h, contains('href="$site/mod/page/view.php?id=4"'));
    expect(h, contains('href="https://fora.exemplo/x"'));
    expect(urls.single, contains('/webservice/pluginfile.php/9/'));
    expect(urls.single, contains('token=TOK'));

    final semBaixar = Midia(m, Directory('${tmp.path}/d/_imagens'), baixar: false);
    final orig = '<img src="$site/pluginfile.php/1/a.png">';
    expect(await semBaixar.html(orig), orig);
  });

  test('cores fixas do professor sao removidas', () {
    final h = semCoresFixas('<td style="color: #000; background-color:black; font-weight:bold">x</td>'
        '<font color="black">y</font><table bgcolor="#000">');
    expect(h, isNot(contains('color')));
    expect(h, contains('font-weight:bold'));
  });

  test('IAs separadas: cada uma grava na sua pasta e le as outras como contexto', () async {
    final curso = {
      'id': 10,
      'nome': 'Redes',
      'pasta': '${tmp.path}/Redes',
      'secoes': [
        {'nome': 'Semana 1', 'resumo': '<p>Modelo OSI</p>', 'modulos': []}
      ],
      'tarefas': [
        {'id': 1, 'nome': 'Relatório', 'entrega': 4102444800, 'html': '<p>Faça o relatório</p>', 'anexos': []}
      ],
      'provas': [],
      'avisos': [],
      'eventos': [],
    };
    FlutterSecureStorage.setMockInitialValues({'ia_chave_gemini': 'G', 'ia_chave_openai': 'O'});
    await Cfg.setIaModelo('gemini', 'gem-x');
    await Cfg.setIaModelo('openai', 'gpt-x');
    final pedidos = <String, String>{};
    final cliente = MockClient((req) async {
      if (req.url.host.contains('googleapis')) {
        pedidos['gemini'] = req.body;
        expect(req.headers['x-goog-api-key'], 'G');
        return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': '# Guia do Gemini'}
                    ]
                  }
                }
              ]
            }),
            200);
      }
      pedidos['openai'] = req.body;
      expect(req.headers['authorization'], 'Bearer O');
      return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '# Guia do GPT'}
              }
            ]
          }),
          200);
    });

    await gerarGuia(curso: curso, slot: 'gemini', chave: 'tarefa_1', kind: 'atividade', nome: 'Relatório', item: (curso['tarefas'] as List).first, tipo: 'tarefa', cliente: cliente);
    await gerarGuia(curso: curso, slot: 'openai', chave: 'tarefa_1', kind: 'atividade', nome: 'Relatório', item: (curso['tarefas'] as List).first, tipo: 'tarefa', cliente: cliente);

    final todos = await guiasDeTodas(curso, 'tarefa_1');
    expect(todos.keys.toSet(), {'gemini', 'openai'});
    expect(todos['gemini']!.texto, '# Guia do Gemini'); // o GPT nao mexeu no do Gemini
    expect(todos['openai']!.texto, '# Guia do GPT');
    expect(todos['gemini']!.modelo, 'gem-x');
    // o GPT recebeu o do Gemini como contexto, marcado como de outra IA
    expect(pedidos['openai'], contains('Guia do Gemini'));
    expect(pedidos['openai'], contains('OUTRA IA'));
    expect(pedidos['gemini'], isNot(contains('Guia do GPT')));
    expect(pedidos['gemini'], contains('Modelo OSI'));
  });

  test('se o modelo recusa PDF, tenta de novo so com texto', () async {
    final pdf = File('${tmp.path}/Redes/Materiais/aula.pdf')..createSync(recursive: true);
    pdf.writeAsBytesSync([37, 80, 68, 70]);
    final curso = {
      'id': 10,
      'nome': 'Redes',
      'pasta': '${tmp.path}/Redes',
      'secoes': [
        {
          'nome': 'S1',
          'resumo': '',
          'modulos': [
            {'nome': 'Aula', 'tipo': 'resource', 'arquivos': [
              {'nome': 'aula.pdf', 'caminho': pdf.path}
            ]}
          ]
        }
      ],
      'tarefas': [],
      'provas': [],
      'avisos': [],
      'eventos': [],
    };
    FlutterSecureStorage.setMockInitialValues({'ia_chave_anthropic': 'A'});
    await Cfg.setIaModelo('anthropic', 'claude-x');
    var n = 0;
    final cliente = MockClient((req) async {
      n++;
      if (req.body.contains('"document"')) {
        return http.Response(jsonEncode({'error': {'message': 'documentos não suportados'}}), 400);
      }
      return http.Response(jsonEncode({'content': [{'type': 'text', 'text': 'ok sem pdf'}]}), 200);
    });
    final g = await gerarGuia(curso: curso, slot: 'anthropic', chave: 'materia', kind: 'materia', nome: 'Redes', cliente: cliente);
    expect(n, 2);
    expect(g.texto, 'ok sem pdf');
    expect(g.arquivos, 0);
  });

  test('texto de docx e pptx', () async {
    // docx minimo
    final f = File('${tmp.path}/x.docx');
    final enc = ZipBuilder()..add('word/document.xml', '<w:document><w:p><w:t>Olá &amp; mundo</w:t></w:p><w:p><w:t>Linha 2</w:t></w:p></w:document>');
    f.writeAsBytesSync(enc.bytes());
    expect(await textoDeArquivo(f), 'Olá & mundo\nLinha 2');
  });
}


void maisTestes() {
  test('provas presenciais do cronograma', () {
    const html = '<h4>Cronograma</h4><table><tr><th>Instrumento</th><th>Pontuação</th><th>Conteúdo</th><th>Data</th></tr>'
        '<tr><td>N1 - Questionário Individual Online</td><td>6</td><td>Matrizes</td><td>25 a 31 de Agosto</td></tr>'
        '<tr><td>N3 - Prova Individual Presencial</td><td>28</td><td>Matrizes, Determinante</td><td>02 de Outubro</td></tr>'
        '<tr><td>N4 - Questionário Individual Online</td><td>7</td><td>TL</td><td>03 a 09 de Novembro</td></tr>'
        '<tr><td>N5 - Prova Individual Presencial</td><td>28</td><td>TL, Autovalores, Diagonalização</td><td>27 de Novembro</td></tr></table>';
    final p = provasDoCronograma(html, DateTime(2026, 7, 29));
    expect(p.map((e) => e['nome']), ['N3 - Prova Individual Presencial', 'N5 - Prova Individual Presencial']);
    expect(fmtData(p.last['ts'], hora: false), '27/11/2026');
    expect(categoria('evento', p.last), 'prova');
    expect('${p.last['html']}', contains('Diagonalização'));
  });

  test('pedido para app de chat e resposta colada ficam separados', () async {
    final curso = {
      'id': 10, 'nome': 'Álgebra', 'pasta': '${Store.baseTeste!.path}/AL',
      'secoes': [{'nome': 'TL', 'resumo': '<p>Núcleo e imagem</p>', 'modulos': []}],
      'tarefas': [], 'provas': [], 'avisos': [], 'eventos': [],
    };
    await salvarGuia(curso, 'gemini', 'materia', '# do Gemini', modelo: 'g');
    final ped = await montarPedido(curso: curso, origem: 'app_claude', kind: 'materia', nome: 'Álgebra');
    expect(ped.completo, contains('Núcleo e imagem'));
    expect(ped.completo, contains('GUIA DE ESTUDO GERAL'));
    await salvarGuia(curso, 'app_claude', 'materia', '# colado do Claude');
    final todos = await guiasDeTodas(curso, 'materia');
    expect(todos.keys.toSet(), {'gemini', 'app_claude'});
    expect(todos['gemini']!.texto, '# do Gemini');
    expect(nomeSlot('app_claude'), contains('Claude'));
  });
}

/// Monta um zip simples para o teste.
class ZipBuilder {
  final _a = Archive();
  void add(String nome, String conteudo) => _a.addFile(ArchiveFile.string(nome, conteudo));
  List<int> bytes() => ZipEncoder().encode(_a);
}
