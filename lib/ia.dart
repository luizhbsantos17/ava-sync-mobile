import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;

import 'classificar.dart';
import 'config.dart';
import 'util.dart';

/// Guias de estudo por IA.
///
/// Cada provedor ("slot") tem a sua configuracao E a sua pasta:
///   `materia/IA/slot/materia.md`, `tarefa_12.md`, `quiz_3.md`, `evento_9.md`
/// - Trocar de IA so muda qual pasta o app mostra. Nada e apagado.
/// - Uma IA so escreve na propria pasta. Ela pode LER o que as outras geraram, como
///   contexto extra, mas nunca altera o conteudo delas.
const iaSlots = <String, ({String nome, String dica, bool pdf})>{
  'gemini': (nome: 'Gemini (Google)', dica: 'gemini-2.5-flash', pdf: true),
  'openai': (nome: 'ChatGPT (OpenAI)', dica: 'ex.: um modelo GPT da sua conta', pdf: true),
  'anthropic': (nome: 'Claude (Anthropic)', dica: 'ex.: um modelo Claude da sua conta', pdf: true),
  'compat': (nome: 'Outro (OpenRouter, Groq, Ollama...)', dica: 'nome do modelo no provedor', pdf: false),
};

/// Conteudo feito FORA do app, num app de chat (usa a sua assinatura, ex.: Claude Pro).
/// O AVA Sync monta o pedido, voce manda no app de chat e cola a resposta de volta.
const iaApps = <String, String>{
  'app_claude': 'Claude (app/Cowork)',
  'app_chatgpt': 'ChatGPT (app)',
  'app_gemini': 'Gemini (app)',
  'app_outro': 'Outro app de chat',
};

/// Todas as origens possiveis de conteudo, na ordem em que aparecem.
List<String> get todasOrigens => [...iaSlots.keys, ...iaApps.keys];

String nomeSlot(String slot) => iaSlots[slot]?.nome ?? iaApps[slot] ?? slot;

class Anexo {
  final String nome;
  final Uint8List bytes;
  Anexo(this.nome, this.bytes);
}

class Pacote {
  final String texto;
  final List<Anexo> pdfs;
  final List<String> fontes;
  Pacote(this.texto, this.pdfs, this.fontes);
}

class Guia {
  final String slot;
  final String modelo;
  final int em;
  final String texto;
  final int arquivos;
  Guia(this.slot, this.modelo, this.em, this.texto, this.arquivos);
}

// ---------------------------------------------------------------- arquivos dos guias

String chaveItem(String tipo, dynamic id) => '${tipo}_$id';

File arquivoGuia(Map<String, dynamic> curso, String slot, String chave) =>
    File('${curso['pasta']}/IA/$slot/$chave.md');

Future<Guia?> lerGuia(Map<String, dynamic> curso, String slot, String chave) async {
  final f = arquivoGuia(curso, slot, chave);
  if (!await f.exists()) return null;
  final t = await f.readAsString();
  final m = RegExp(r'^<!--avasync-ia (\{.*?\})-->\n').firstMatch(t);
  final meta = m == null ? <String, dynamic>{} : mapa(jsonDecode(m[1]!));
  return Guia(slot, '${meta['modelo'] ?? ''}', (meta['em'] as num?)?.toInt() ?? 0, m == null ? t : t.substring(m.end),
      (meta['arquivos'] as num?)?.toInt() ?? 0);
}

/// Todos os guias deste item, de todas as IAs (para mostrar e para dar contexto).
Future<Map<String, Guia>> guiasDeTodas(Map<String, dynamic> curso, String chave) async {
  final out = <String, Guia>{};
  for (final s in todasOrigens) {
    final g = await lerGuia(curso, s, chave);
    if (g != null) out[s] = g;
  }
  return out;
}

// ---------------------------------------------------------------- leitura dos materiais

/// Texto de DOCX/PPTX/TXT. PDF vai como anexo para as IAs que leem PDF.
Future<String> textoDeArquivo(File f) async {
  final n = f.path.toLowerCase();
  try {
    if (n.endsWith('.txt') || n.endsWith('.md') || n.endsWith('.csv')) return await f.readAsString();
    if (n.endsWith('.html') || n.endsWith('.htm')) return semHtml(await f.readAsString());
    if (n.endsWith('.docx') || n.endsWith('.pptx') || n.endsWith('.odt') || n.endsWith('.odp')) {
      final z = ZipDecoder().decodeBytes(await f.readAsBytes());
      final partes = z.files.where((a) {
        final x = a.name;
        return x == 'word/document.xml' ||
            RegExp(r'^ppt/slides/slide\d+\.xml$').hasMatch(x) ||
            x == 'content.xml';
      }).toList()
        ..sort((a, b) => _num(a.name).compareTo(_num(b.name)));
      final buf = StringBuffer();
      for (final p in partes) {
        if (p.name.startsWith('ppt/')) buf.writeln('\n[Slide ${_num(p.name)}]');
        final xml = utf8.decode(p.content, allowMalformed: true)
            .replaceAll(RegExp(r'</(w:p|a:p|text:p|text:h)>'), '\n')
            .replaceAll(RegExp(r'<[^>]+>'), '');
        buf.write(desescapar(xml));
      }
      return buf.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    }
  } catch (_) {}
  return '';
}

int _num(String s) => int.tryParse(RegExp(r'(\d+)').firstMatch(s.split('/').last)?[1] ?? '') ?? 0;

class _Juntador {
  final int max;
  final buf = StringBuffer();
  final fontes = <String>[];
  _Juntador(this.max);
  bool get cheio => buf.length >= max;
  void add(String titulo, String texto, {int limite = 20000}) {
    texto = texto.trim();
    if (texto.isEmpty || cheio) return;
    if (texto.length > limite) texto = '${texto.substring(0, limite)}\n[...cortado]';
    final resto = max - buf.length;
    if (texto.length > resto) texto = '${texto.substring(0, resto)}\n[...cortado]';
    buf.writeln('\n### $titulo\n$texto');
    fontes.add(titulo);
  }
}

const _maxPdfBytes = 12 * 1024 * 1024;

Future<List<Anexo>> _pdfs(List<Map<String, dynamic>> arquivos, int maxQtd) async {
  final out = <Anexo>[];
  var total = 0;
  for (final a in arquivos) {
    if (out.length >= maxQtd) break;
    final f = File('${a['caminho']}');
    if (!'${a['caminho']}'.toLowerCase().endsWith('.pdf') || !await f.exists()) continue;
    final len = await f.length();
    if (len > 8 * 1024 * 1024 || total + len > _maxPdfBytes) continue;
    out.add(Anexo('${a['nome']}', await f.readAsBytes()));
    total += len;
  }
  return out;
}

List<Map<String, dynamic>> _arquivosDoCurso(Map<String, dynamic> c) => [
      for (final s in lista(c['secoes']).map(mapa))
        for (final mo in lista(s['modulos']).map(mapa)) ...lista(mo['arquivos']).map(mapa),
    ];

/// Tudo o que da para ler da materia, dentro do limite de tamanho.
Future<Pacote> contextoMateria(Map<String, dynamic> c, {int? max, bool pdfs = true}) async {
  final j = _Juntador(max ?? Cfg.iaMaxContexto);
  j.add('Matéria', '${c['nome']}');
  final tarefas = lista(c['tarefas']).map(mapa).toList();
  final itens = itensDoCurso(c);
  j.add(
      'Prazos e avaliações',
      [
        for (final e in [...itens.provas, ...itens.atividades])
          '- [${e['cat'] == 'prova' ? 'PROVA' : 'atividade'}] ${mapa(e['item'])['nome']} (${fmtData(e['ts'])})',
      ].join('\n'));
  for (final s in lista(c['secoes']).map(mapa)) {
    final linhas = <String>[semHtml('${s['resumo']}')];
    for (final mo in lista(s['modulos']).map(mapa)) {
      final d = semHtml('${mo['desc']}');
      linhas.add('- ${mo['nome']} (${mo['tipo']})${d.isEmpty ? '' : ': $d'}');
    }
    j.add('Seção: ${s['nome']}', linhas.join('\n'), limite: 8000);
  }
  for (final s in lista(c['secoes']).map(mapa)) {
    for (final mo in lista(s['modulos']).map(mapa)) {
      if (mo['html'] != null && File('${mo['html']}').existsSync()) {
        j.add('${mo['tipo'] == 'book' ? 'Livro' : 'Página'}: ${mo['nome']}', semHtml(await File('${mo['html']}').readAsString()));
      }
      for (final a in lista(mo['arquivos']).map(mapa)) {
        final t = await textoDeArquivo(File('${a['caminho']}'));
        if (t.isNotEmpty) j.add('Arquivo: ${a['nome']}', t, limite: 15000);
      }
    }
  }
  for (final t in tarefas) {
    j.add('Atividade: ${t['nome']} (entrega ${fmtData(t['entrega'])})', semHtml('${t['html']}'), limite: 4000);
  }
  for (final a in lista(c['avisos']).map(mapa).take(15)) {
    j.add('Aviso: ${a['titulo']} (${fmtData(a['data'])})', semHtml('${a['html']}'), limite: 3000);
  }
  final anexos = pdfs ? await _pdfs(_arquivosDoCurso(c), 8) : <Anexo>[];
  return Pacote(j.buf.toString(), anexos, [...j.fontes, ...anexos.map((a) => 'PDF: ${a.nome}')]);
}

/// Contexto de uma atividade ou prova: o item, os anexos, avisos e o guia da materia.
Future<Pacote> contextoItem(Map<String, dynamic> c, String tipo, Map<String, dynamic> item, String cat, String slot,
    {bool pdfs = true}) async {
  final j = _Juntador(Cfg.iaMaxContexto);
  final ts = tipo == 'tarefa' ? item['entrega'] : (tipo == 'quiz' ? item['fecha'] : item['ts']);
  j.add('Matéria', '${c['nome']}');
  j.add('${cat == 'prova' ? 'Prova/avaliação' : 'Atividade'}: ${item['nome']}',
      'Tipo no Moodle: ${rotuloTipo(tipo)}\nData: ${fmtData(ts)}\n\n${semHtml('${item['html']}')}');
  final anexos = lista(item['anexos']).map(mapa).toList();
  for (final a in anexos) {
    final t = await textoDeArquivo(File('${a['caminho']}'));
    if (t.isNotEmpty) j.add('Anexo do professor: ${a['nome']}', t);
  }
  // guia geral da materia: o desta IA, ou de outra se esta ainda nao fez
  final geral = await guiasDeTodas(c, 'materia');
  final g = geral[slot] ?? geral.values.firstOrNull;
  if (g != null) {
    j.add('Guia geral da matéria (gerado por ${nomeSlot(g.slot)}${g.slot == slot ? '' : ', outra IA'})', g.texto, limite: 30000);
  }
  // avisos (podem dizer o que cai na prova) e cronograma/conteudo
  for (final a in lista(c['avisos']).map(mapa).take(cat == 'prova' ? 20 : 8)) {
    j.add('Aviso: ${a['titulo']} (${fmtData(a['data'])})', semHtml('${a['html']}'), limite: 3000);
  }
  if (cat == 'prova') {
    for (final e in lista(c['eventos']).map(mapa)) {
      j.add('Evento do calendário: ${e['nome']} (${fmtData(e['ts'])})', semHtml('${e['html']}'), limite: 2000);
    }
  }
  final ctxMat = await contextoMateria(c, max: (Cfg.iaMaxContexto ~/ 2), pdfs: false);
  j.add('Conteúdo da matéria', ctxMat.texto, limite: Cfg.iaMaxContexto ~/ 2);
  // o que outras IAs ja escreveram sobre este mesmo item (so leitura)
  final outras = await guiasDeTodas(c, chaveItem(tipo, item['id']));
  for (final o in outras.values.where((o) => o.slot != slot)) {
    j.add('Material sobre este item feito por OUTRA IA (${nomeSlot(o.slot)}), use só como referência e confira',
        o.texto, limite: 15000);
  }
  var lista_ = <Anexo>[];
  if (pdfs) {
    lista_ = await _pdfs([...anexos, if (cat == 'prova') ..._arquivosDoCurso(c).reversed], cat == 'prova' ? 5 : 3);
  }
  return Pacote(j.buf.toString(), lista_, [...j.fontes, ...lista_.map((a) => 'PDF: ${a.nome}')]);
}

// ---------------------------------------------------------------- prompts

const _sistema = '''Você é um monitor de estudos de um estudante universitário brasileiro.
Escreva em português do Brasil, em Markdown bem organizado (títulos, listas, tabelas quando ajudar, fórmulas em texto simples).
Baseie-se no material fornecido (textos e PDFs da matéria). Quando usar algo de um material, cite entre colchetes, ex.: [Slides aula 3].
Se faltar informação, diga o que falta em vez de inventar. Datas e prazos: use as datas fornecidas.''';

String _pedido(String kind, String nome) => switch (kind) {
      'materia' => '''Monte o GUIA DE ESTUDO GERAL da matéria "$nome".
1. Visão geral: do que a matéria trata e como os assuntos se conectam.
2. Tópicos na ordem do curso: para cada um, explique de forma didática (o que é, por que importa, exemplo resolvido, fórmulas/definições principais, armadilhas comuns).
3. Glossário dos termos importantes.
4. Calendário: provas e entregas com datas.
5. Como estudar esta matéria (estratégia, o que priorizar).
6. 10 perguntas de revisão com respostas curtas.''',
      'prova' => '''Prepare o estudante para a PROVA/AVALIAÇÃO "$nome".
1. O que provavelmente vai cair: liste os tópicos e JUSTIFIQUE cada um com base no material (avisos, cronograma, conteúdo dado até a data, descrição da prova). Diga o grau de confiança.
2. Revisão didática de cada tópico (explicação, exemplos resolvidos, fórmulas, pegadinhas).
3. Lista de exercícios de treino no estilo provável da prova, com resolução comentada no final.
4. Plano de estudo até a data da prova (dia a dia, se houver tempo).
5. Checklist do que levar/saber no dia.''',
      _ => '''Ajude o estudante a fazer a ATIVIDADE "$nome" e a APRENDER a matéria por trás dela.
1. O que a atividade pede, em palavras simples (e o formato de entrega, prazo, critérios).
2. A matéria necessária, ensinada de forma didática, com exemplos.
3. Passo a passo de como fazer.
4. Erros comuns e como evitar.
5. Checklist de entrega.
IMPORTANTE: não entregue a resposta final pronta (código final, texto final, resultados finais); ensine o caminho.''',
    };

// ---------------------------------------------------------------- chamada aos provedores

class IaErro implements Exception {
  final String msg;
  final int? status;
  IaErro(this.msg, [this.status]);
  @override
  String toString() => msg;
}

Map<String, dynamic> _json(http.Response r) {
  dynamic d;
  try {
    d = jsonDecode(utf8.decode(r.bodyBytes));
  } catch (_) {
    throw IaErro('Resposta inválida do provedor (HTTP ${r.statusCode}).', r.statusCode);
  }
  if (r.statusCode >= 400) {
    final e = d is Map ? d['error'] : null;
    throw IaErro('HTTP ${r.statusCode}: ${e is Map ? e['message'] : e ?? r.body}', r.statusCode);
  }
  return mapa(d);
}

/// Envia o pedido ao provedor. Devolve o texto.
Future<String> perguntar(String slot, String sistema, String usuario,
    {List<Anexo> pdfs = const [], int maxTokens = 8000, http.Client? cliente}) async {
  final c = cliente ?? http.Client();
  final chave = await Cfg.iaChave(slot) ?? '';
  final modelo = Cfg.iaModelo(slot);
  if (modelo.isEmpty) throw IaErro('Escolha o modelo da IA em Ajustes.');
  if (chave.isEmpty && slot != 'compat') throw IaErro('Coloque a chave da API em Ajustes.');
  const t = Duration(minutes: 4);
  switch (slot) {
    case 'gemini':
      final r = await c
          .post(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/$modelo:generateContent'),
              headers: {'x-goog-api-key': chave, 'content-type': 'application/json'},
              body: jsonEncode({
                'systemInstruction': {
                  'parts': [
                    {'text': sistema}
                  ]
                },
                'contents': [
                  {
                    'role': 'user',
                    'parts': [
                      for (final p in pdfs) {'inline_data': {'mime_type': 'application/pdf', 'data': base64Encode(p.bytes)}},
                      {'text': usuario},
                    ]
                  }
                ],
                'generationConfig': {'maxOutputTokens': maxTokens, 'temperature': 0.4},
              }))
          .timeout(t);
      final d = _json(r);
      final cand = mapa(lista(d['candidates']).firstOrNull);
      final txt = lista(mapa(cand['content'])['parts']).map(mapa).map((x) => x['text'] ?? '').join();
      if (txt.isEmpty) throw IaErro('O Gemini não devolveu texto (${cand['finishReason'] ?? 'sem motivo'}).');
      return txt;
    case 'anthropic':
      final r = await c
          .post(Uri.parse('https://api.anthropic.com/v1/messages'),
              headers: {'x-api-key': chave, 'anthropic-version': '2023-06-01', 'content-type': 'application/json'},
              body: jsonEncode({
                'model': modelo,
                'max_tokens': maxTokens,
                'system': sistema,
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      for (final p in pdfs)
                        {
                          'type': 'document',
                          'title': p.nome,
                          'source': {'type': 'base64', 'media_type': 'application/pdf', 'data': base64Encode(p.bytes)}
                        },
                      {'type': 'text', 'text': usuario},
                    ]
                  }
                ]
              }))
          .timeout(t);
      final d = _json(r);
      return lista(d['content']).map(mapa).map((x) => x['text'] ?? '').join();
    default:
      final base = slot == 'openai'
          ? 'https://api.openai.com/v1'
          : (Cfg.iaBaseUrl(slot).isEmpty ? 'https://openrouter.ai/api/v1' : Cfg.iaBaseUrl(slot)).replaceAll(RegExp(r'/+$'), '');
      final usaPdf = slot == 'openai' && pdfs.isNotEmpty;
      final r = await c
          .post(Uri.parse('$base/chat/completions'),
              headers: {if (chave.isNotEmpty) 'Authorization': 'Bearer $chave', 'content-type': 'application/json'},
              body: jsonEncode({
                'model': modelo,
                if (slot == 'openai') 'max_completion_tokens': maxTokens else 'max_tokens': maxTokens,
                'messages': [
                  {'role': 'system', 'content': sistema},
                  {
                    'role': 'user',
                    'content': usaPdf
                        ? [
                            for (final p in pdfs)
                              {
                                'type': 'file',
                                'file': {'filename': p.nome, 'file_data': 'data:application/pdf;base64,${base64Encode(p.bytes)}'}
                              },
                            {'type': 'text', 'text': usuario},
                          ]
                        : usuario,
                  }
                ]
              }))
          .timeout(t);
      final d = _json(r);
      return '${mapa(mapa(lista(d['choices']).firstOrNull)['message'])['content'] ?? ''}';
  }
}

/// Lista os modelos disponiveis na conta (para escolher sem decorar nomes).
Future<List<String>> listarModelos(String slot, {http.Client? cliente}) async {
  final c = cliente ?? http.Client();
  final chave = await Cfg.iaChave(slot) ?? '';
  http.Response r;
  if (slot == 'gemini') {
    r = await c.get(Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?pageSize=200'),
        headers: {'x-goog-api-key': chave});
    return lista(_json(r)['models'])
        .map(mapa)
        .where((m) => lista(m['supportedGenerationMethods']).contains('generateContent'))
        .map((m) => '${m['name']}'.replaceFirst('models/', ''))
        .toList();
  }
  if (slot == 'anthropic') {
    r = await c.get(Uri.parse('https://api.anthropic.com/v1/models?limit=100'),
        headers: {'x-api-key': chave, 'anthropic-version': '2023-06-01'});
    return lista(_json(r)['data']).map(mapa).map((m) => '${m['id']}').toList();
  }
  final base = slot == 'openai'
      ? 'https://api.openai.com/v1'
      : (Cfg.iaBaseUrl(slot).isEmpty ? 'https://openrouter.ai/api/v1' : Cfg.iaBaseUrl(slot)).replaceAll(RegExp(r'/+$'), '');
  r = await c.get(Uri.parse('$base/models'), headers: {if (chave.isNotEmpty) 'Authorization': 'Bearer $chave'});
  return lista(_json(r)['data']).map(mapa).map((m) => '${m['id']}').toList()..sort();
}

Future<String> testar(String slot) =>
    perguntar(slot, 'Responda em uma frase curta, em português.', 'Diga "funcionando" e qual modelo você é.', maxTokens: 200);

class Pedido {
  final String sistema;
  final String usuario;
  final List<Anexo> pdfs;
  final int fontes;
  Pedido(this.sistema, this.usuario, this.pdfs, this.fontes);

  /// Texto unico para colar/compartilhar num app de chat.
  String get completo => '$sistema\n\n$usuario';
}

/// Monta o pedido (instrucoes + material) sem enviar a ninguem.
/// [origem]: quem vai gerar (para usar o conteudo das OUTRAS como referencia).
Future<Pedido> montarPedido({
  required Map<String, dynamic> curso,
  required String origem,
  required String kind,
  required String nome,
  Map<String, dynamic>? item,
  String? tipo,
  bool pdfs = true,
}) async {
  final pac = kind == 'materia'
      ? await contextoMateria(curso, pdfs: pdfs)
      : await contextoItem(curso, tipo!, item!, kind, origem, pdfs: pdfs);
  final usuario = '${_pedido(kind, nome)}\n\n'
      '${pac.pdfs.isEmpty ? '' : 'Os PDFs anexados são materiais da matéria: ${pac.pdfs.map((p) => p.nome).join(', ')}.\n'}'
      '=== MATERIAL DA MATÉRIA ===\n${pac.texto}';
  return Pedido(_sistema, usuario, pac.pdfs, pac.fontes.length);
}

/// Grava o conteudo na pasta da origem (e SO nela).
Future<Guia> salvarGuia(Map<String, dynamic> curso, String origem, String chave, String texto,
    {String modelo = '', int arquivos = 0, int fontes = 0}) async {
  final g = Guia(origem, modelo, agoraSeg(), texto.trim(), arquivos);
  final f = arquivoGuia(curso, origem, chave);
  await f.parent.create(recursive: true);
  final meta = jsonEncode({'slot': origem, 'modelo': modelo, 'em': g.em, 'arquivos': arquivos, 'fontes': fontes});
  await f.writeAsString('<!--avasync-ia $meta-->\n${g.texto}');
  return g;
}

/// Gera pela API e salva. Grava SO na pasta do slot ativo.
Future<Guia> gerarGuia({
  required Map<String, dynamic> curso,
  required String slot,
  required String chave,
  required String kind, // materia | atividade | prova
  required String nome,
  Map<String, dynamic>? item,
  String? tipo,
  void Function(String)? progresso,
  http.Client? cliente,
}) async {
  progresso?.call('Lendo o material da matéria...');
  final ped = await montarPedido(
      curso: curso,
      origem: slot,
      kind: kind,
      nome: nome,
      item: item,
      tipo: tipo,
      pdfs: Cfg.iaEnviarPdfs && (iaSlots[slot]?.pdf ?? false));
  progresso?.call('Pedindo para ${nomeSlot(slot)} (pode levar 1 a 2 minutos)...');
  String texto;
  var pdfs = ped.pdfs;
  final max = kind == 'materia' ? 12000 : 8000;
  try {
    texto = await perguntar(slot, ped.sistema, ped.usuario, pdfs: pdfs, maxTokens: max, cliente: cliente);
  } on IaErro catch (e) {
    // alguns modelos nao aceitam PDF ou o pedido ficou grande demais: tenta so com texto
    if (pdfs.isEmpty || !(e.status == 400 || e.status == 413)) rethrow;
    progresso?.call('O modelo recusou os PDFs; tentando só com o texto...');
    pdfs = [];
    texto = await perguntar(slot, ped.sistema, ped.usuario, maxTokens: max, cliente: cliente);
  }
  return salvarGuia(curso, slot, chave, texto, modelo: Cfg.iaModelo(slot), arquivos: pdfs.length, fontes: ped.fontes);
}
