import 'dart:io';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'armazenamento.dart';
import 'util.dart';

/// Dados do Q-Academico (boletim, diarios e horario), lidos das paginas que a propria
/// pessoa abre logada no navegador interno do app. O Q-Academico nao tem API e bloqueia
/// robos, por isso o app nunca acessa o site sozinho por HTTP.
class QAcademico {
  static const urlPadrao = 'https://academico.ifes.edu.br/qacademico/index.asp?t=1001';

  /// Paginas padrao (relativas a /qacademico/), usadas se o menu nao tiver os links.
  static const paginaBoletim = 'index.asp?t=2032';
  static const paginaDiarios = 'index.asp?t=2071';
  static const paginaHorario = 'index.asp?t=2010';
  /// Seleção de questionários (avaliação docente).
  static const paginaQuestionarios = 'index.asp?t=1020';

  static Future<Map<String, dynamic>> carregar() => Store.lerJson('academico.json');
  static Future<void> salvar(Map<String, dynamic> d) => Store.gravarJson('academico.json', d);

  /// Guarda a pagina lida (para diagnostico: "Exportar paginas do Q-Academico").
  static Future<void> guardarPagina(String nome, String conteudo) async {
    final f = File('${(await Store.dados()).path}/qa_$nome.html');
    await f.writeAsString(conteudo);
  }

  static Future<List<File>> paginasGuardadas() async {
    final d = await Store.dados();
    final out = <File>[];
    for (final n in ['menu', 'boletim', 'diarios', 'horario']) {
      final f = File('${d.path}/qa_$n.html');
      if (await f.exists()) out.add(f);
    }
    return out;
  }
}

// ---------------------------------------------------------------- tabelas

/// Tabela HTML -> grade de textos, expandindo colspan/rowspan (cada celula ocupa
/// todas as posicoes que cobre, assim cabecalhos agrupados viram rotulos por coluna).
List<List<String>> grade(dom.Element tabela) {
  final linhas = tabela.querySelectorAll('tr').where((tr) => _tabelaDe(tr) == tabela).toList();
  final out = <List<String>>[];
  final pendentes = <int, (String, int)>{}; // coluna -> (texto, linhas restantes)
  for (final tr in linhas) {
    final linha = <String>[];
    var col = 0;
    void consumirPendentes() {
      while (pendentes.containsKey(col)) {
        final (t, n) = pendentes[col]!;
        linha.add(t);
        if (n <= 1) {
          pendentes.remove(col);
        } else {
          pendentes[col] = (t, n - 1);
        }
        col++;
      }
    }

    for (final td in tr.children.where((e) => e.localName == 'td' || e.localName == 'th')) {
      consumirPendentes();
      final titulo = limpar(td.querySelector('[title]')?.attributes['title'] ?? '');
      final textoBase = limpar(td.text);
      final texto = titulo.isEmpty || norm(textoBase).contains(norm(titulo)) ? textoBase : '$textoBase $titulo';
      final cs = int.tryParse(td.attributes['colspan'] ?? '') ?? 1;
      final rs = int.tryParse(td.attributes['rowspan'] ?? '') ?? 1;
      for (var i = 0; i < cs.clamp(1, 50); i++) {
        linha.add(texto);
        if (rs > 1) pendentes[col] = (texto, rs - 1);
        col++;
      }
    }
    consumirPendentes();
    if (linha.any((c) => c.isNotEmpty)) out.add(linha);
  }
  return out;
}

dom.Element? _tabelaDe(dom.Element e) {
  dom.Element? p = e.parent;
  while (p != null && p.localName != 'table') {
    p = p.parent;
  }
  return p;
}

String limpar(String s) => s.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

/// minusculo, sem acento e sem pontuacao ("Cód. Disc." -> "cod disc", "N1" -> "n1")
String norm(String s) => limpar(limpar(s)
        .toLowerCase()
        .replaceAll(RegExp('[áàâã]'), 'a')
        .replaceAll(RegExp('[éê]'), 'e')
        .replaceAll('í', 'i')
        .replaceAll(RegExp('[óôõ]'), 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c')
        .replaceAll('ª', 'a')
        .replaceAll('º', 'o')
        .replaceAll(RegExp(r'[.:;()\[\]]'), ' '));

/// "8,5" -> 8.5; "-", "" -> null
double? numero(String? s) {
  if (s == null) return null;
  final m = RegExp(r'-?\d+(?:[.,]\d+)?').firstMatch(s.replaceAll(' ', ''));
  if (m == null) return null;
  return double.tryParse(m[0]!.replaceAll(',', '.'));
}

// ---------------------------------------------------------------- boletim

/// Uma disciplina do boletim.
class Disciplina {
  String nome;
  String codigo;
  String pauta; // COD_PAUTA do Q-Academico: liga boletim e diario sem depender do nome
  String professor;
  double? carga; // carga horaria como o Q-Academico mostra
  double? aulas; // total de aulas previstas (quando a pagina mostra)
  double? faltas;
  double? frequencia; // % de presenca informado pelo Q-Academico
  double? minima; // % de presenca obrigatorio informado pelo Q-Academico
  String media;
  String situacao;
  List<Map<String, dynamic>> etapas; // {rotulo, nota, faltas}
  List<Map<String, dynamic>> avaliacoes; // {etapa, descricao, nota, max, peso, data}

  Disciplina({
    required this.nome,
    this.codigo = '',
    this.pauta = '',
    this.professor = '',
    this.carga,
    this.aulas,
    this.faltas,
    this.frequencia,
    this.minima,
    this.media = '',
    this.situacao = '',
    List<Map<String, dynamic>>? etapas,
    List<Map<String, dynamic>>? avaliacoes,
  })  : etapas = etapas ?? [],
        avaliacoes = avaliacoes ?? [];

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'codigo': codigo,
        'pauta': pauta,
        'professor': professor,
        'carga': carga,
        'aulas': aulas,
        'faltas': faltas,
        'frequencia': frequencia,
        'minima': minima,
        'media': media,
        'situacao': situacao,
        'etapas': etapas,
        'avaliacoes': avaliacoes,
      };

  factory Disciplina.fromJson(Map<String, dynamic> j) => Disciplina(
        nome: '${j['nome'] ?? ''}',
        codigo: '${j['codigo'] ?? ''}',
        pauta: '${j['pauta'] ?? ''}',
        professor: '${j['professor'] ?? ''}',
        carga: (j['carga'] as num?)?.toDouble(),
        aulas: (j['aulas'] as num?)?.toDouble(),
        faltas: (j['faltas'] as num?)?.toDouble(),
        frequencia: (j['frequencia'] as num?)?.toDouble(),
        minima: (j['minima'] as num?)?.toDouble(),
        media: '${j['media'] ?? ''}',
        situacao: '${j['situacao'] ?? ''}',
        etapas: lista(j['etapas']).map(mapa).toList(),
        avaliacoes: lista(j['avaliacoes']).map(mapa).toList(),
      );
}

/// Frequencia e faltas de uma disciplina.
class Frequencia {
  final double? percentual; // presenca sobre o total do semestre (carga), 0-100
  final double? percentualDadas; // presenca sobre as aulas ja dadas (o % do Q-Academico)
  final double? faltasPercentual;
  final int? limite; // faltas permitidas no total
  final int? restantes; // quantas faltas ainda pode ter (negativo = passou)
  final int aulasPorDia; // faltar um dia de aula desta disciplina custa isto
  const Frequencia(this.percentual, this.faltasPercentual, this.limite, this.restantes, this.aulasPorDia,
      {this.percentualDadas});

  /// Quantos dias inteiros de aula ainda pode faltar.
  int? get diasRestantes => restantes == null ? null : (restantes! < 0 ? -1 : restantes! ~/ aulasPorDia);

  bool get emRisco => diasRestantes != null && diasRestantes! <= 1;
  bool get reprovadoPorFalta => restantes != null && restantes! < 0;
}

/// [aulasPorDia]: quantas aulas seguidas a disciplina tem num dia (do horario, ou o
/// padrao dos ajustes). Uma falta no dia conta todas elas. O % obrigatorio do proprio
/// Q-Academico (quando lido do diario) vale mais que [minima].
Frequencia frequencia(Disciplina d, {double minima = 75, int aulasPorDia = 2}) {
  final min = d.minima ?? minima;
  // O Q-Academico pode repetir a carga em horas no campo de aulas previstas.
  // Cada hora equivale a 60/50 aulas; nao reconverter totais ja distintos da carga.
  final aulas = (d.aulas ?? 0) > 0 ? d.aulas : null;
  final total = aulas != null && aulas != d.carga ? aulas : d.carga == null ? null : d.carga! * 60 / 50;
  final faltas = d.faltas ?? 0;
  // O que decide reprovar por falta e o total do semestre, nao as aulas dadas ate agora:
  // por isso o % principal e sobre o total. O % do Q-Academico so vale sem carga horaria.
  final pres = total != null && total > 0 ? (100 * (1 - faltas / total)).clamp(0, 100).toDouble() : d.frequencia;
  final limite = total == null || total <= 0 ? null : (total * (100 - min) / 100).floor();
  return Frequencia(pres, pres == null ? null : 100 - pres, limite, limite == null ? null : limite - faltas.ceil(),
      aulasPorDia < 1 ? 1 : aulasPorDia,
      percentualDadas: d.frequencia);
}

// rotulo de etapa: "1a etapa", "2o bimestre", "n1", "f1", "etapa 3"...
final _reEtapa = RegExp(r'etapa|bimestre|trimestre|\b[nef]\s?\d\b|\b\d\s?[ao]\b|\bav\s?\d\b|\bp\s?\d\b');
final _reRec = RegExp(r'\brec|exame|\bef\b|\bpf\b');

/// Celulas "folha" de uma linha (sem tabela dentro): as tabelas de layout do Q-Academico
/// embrulham a pagina inteira e nao podem ser confundidas com o boletim.
bool _folha(dom.Element t) => t.querySelector('table') == null;

/// Le o boletim do Q-Academico (cabecalho "Disciplina" ou, no IFES, "Componente Curricular").
List<Disciplina> lerBoletim(String pagina) {
  final doc = html.parse(pagina);
  final out = <Disciplina>[];
  for (final t in doc.querySelectorAll('table').where(_folha)) {
    final g = grade(t);
    final h = g.indexWhere((l) {
      final n = l.map(norm).toList();
      return n.any((c) => c.contains('disciplina') || c.contains('componente curricular')) &&
          n.any((c) => c.contains('falta') || c.contains('freq') || c.contains('carga') || c == 'ch');
    });
    if (h < 0) continue;
    // cabecalho em duas linhas (ex.: "1a Etapa" sobre "Nota | Faltas" ou "N | F")
    var rotulos = g[h].map(norm).toList();
    var inicio = h + 1;
    if (inicio < g.length && _ehSubcabecalho(g[h], g[inicio])) {
      final sub = g[inicio].map(norm).toList();
      rotulos = [
        for (var i = 0; i < rotulos.length; i++)
          i < sub.length && sub[i] != rotulos[i] ? '${rotulos[i]} ${sub[i]}' : rotulos[i]
      ];
      inicio++;
    }
    int col(bool Function(String) f) => rotulos.indexWhere(f);
    final cNome = col((r) => (r.contains('disciplina') || r.contains('componente curricular')) && !r.contains('cod'));
    if (cNome < 0) continue;
    final cCod = col((r) => r.contains('cod'));
    final cProf = col((r) => r.contains('professor') || r.contains('docente'));
    final cCarga = col((r) => r.contains('carga') || r == 'ch' || RegExp(r'\bc\s?h\b').hasMatch(r));
    final cAulas = col((r) => r.contains('aula') && !r.contains('falta'));
    final cFreq = col((r) => r.contains('freq') || r == '%');
    final cFaltas = col((r) =>
        r.contains('falta') &&
        !r.contains('freq') &&
        (r.contains('total') || r.startsWith('t faltas') || !_reEtapa.hasMatch(r.replaceAll('total', ''))) &&
        r != 'f');
    // MF (media final oficial) primeiro; "M Final" so se MF estiver vazio
    final cMedia = col((r) => r == 'mf' || r.startsWith('mf ') || r.contains('media final') || r.contains('nota final'));
    var cMediaAlt = col((r) => r == 'm final' || r == 'media' || r.contains('resultado'));
    if (cMediaAlt == cMedia) cMediaAlt = -1;
    final cSit = col((r) => r.contains('situa') || r == 'sit');
    final cTurma = col((r) => r == 'turma');
    final usadas = {cNome, cCod, cProf, cCarga, cAulas, cFreq, cFaltas, cMedia, cMediaAlt, cSit, cTurma};

    // colunas de etapa: agrupa nota e faltas da mesma etapa; um "F" solto e a falta da
    // etapa logo a esquerda (IFES: "NS | F | EF | F")
    final etapas = <String, Map<String, int>>{};
    String? ultima;
    for (var i = 0; i < rotulos.length; i++) {
      if (usadas.contains(i)) {
        ultima = null;
        continue;
      }
      final r = rotulos[i];
      if ((r == 'f' || r == 'faltas' || r == 'falta') && ultima != null) {
        etapas[ultima]!['faltas'] = i;
        continue;
      }
      final ehRec = _reRec.hasMatch(r);
      final ehNs = r == 'ns' || r.startsWith('ns ') || r.contains('nota do semestre');
      final ehEf = r == 'ef' || r.startsWith('ef ') || r.contains('exame final');
      if (!_reEtapa.hasMatch(r) && !ehRec && !ehNs && !ehEf) {
        ultima = null;
        continue;
      }
      var tipo = 'nota';
      String chave;
      if (ehNs) {
        chave = 'Nota do semestre';
      } else if (ehEf) {
        chave = 'Exame final';
      } else {
        final compacto = RegExp(r'^([nf])\s?(\d)$').firstMatch(r); // N1 / F1
        if (compacto != null) {
          tipo = compacto[1] == 'f' ? 'faltas' : 'nota';
          chave = '${compacto[2]}a etapa';
        } else {
          if (RegExp(r'\b(faltas?|f)$').hasMatch(r)) tipo = 'faltas';
          chave = limpar(r.replaceAll(RegExp(r'\b(nota|notas|n|faltas?|f)$'), ''));
          if (chave.isEmpty) chave = r;
        }
        // "1a etapa" e "etapa 1" viram a mesma coisa
        final num = RegExp(r'(\d)').firstMatch(chave)?[1];
        if (!ehRec && num != null && chave.contains(RegExp(r'etapa|\b[nef]\s?\d\b'))) chave = '${num}a etapa';
      }
      etapas.putIfAbsent(chave, () => {})[tipo] = i;
      ultima = chave;
    }

    final linhas = t.querySelectorAll('tr').where((tr) => _tabelaDe(tr) == t).toList();
    String cel(List<String> l, int i) => i >= 0 && i < l.length ? l[i] : '';
    for (var li = inicio; li < g.length; li++) {
      final l = g[li];
      final nome = cel(l, cNome);
      final n = norm(nome);
      if (nome.isEmpty ||
          n.contains('disciplina') ||
          n.contains('componente curricular') ||
          n.startsWith('total') ||
          (numero(nome) != null && nome.length < 4)) {
        continue;
      }
      var codigo = cel(l, cCod);
      var nomeLimpo = nome;
      // "SI.101 - Redes" ou "101 - Redes": separa o codigo do nome
      final m = RegExp(r'^([A-Za-z0-9.\-_/]{2,15})\s+-\s+(.+)$').firstMatch(nome);
      if (m != null && RegExp(r'\d').hasMatch(m[1]!)) {
        if (codigo.isEmpty) codigo = m[1]!;
        nomeLimpo = m[2]!;
      }
      // "Redes de Computadores - G 1": o grupo da turma nao faz parte do nome
      nomeLimpo = limpar(nomeLimpo.replaceFirst(RegExp(r'\s+-\s+G\s*\d+\s*$', caseSensitive: false), ''));
      // COD_PAUTA escondido na linha (<q_latente value="COD_PAUTA=900103">)
      final tr = _linhaComTexto(linhas, nome);
      final pauta = RegExp(r'COD_PAUTA=(\d+)').firstMatch(tr?.outerHtml ?? '')?[1] ?? '';
      final mf = _valor(cel(l, cMedia));
      out.add(Disciplina(
        nome: nomeLimpo,
        codigo: codigo,
        pauta: pauta,
        professor: cel(l, cProf),
        carga: numero(cel(l, cCarga)),
        aulas: cAulas == cCarga ? null : numero(cel(l, cAulas)),
        faltas: numero(cel(l, cFaltas)),
        frequencia: numero(cel(l, cFreq)),
        media: mf.isNotEmpty ? mf : _valor(cel(l, cMediaAlt)),
        situacao: cel(l, cSit),
        etapas: [
          for (final e in etapas.entries)
            if (_valor(cel(l, e.value['nota'] ?? -1)).isNotEmpty || numero(cel(l, e.value['faltas'] ?? -1)) != null)
              {
                'rotulo': _rotulo(e.key),
                'nota': _valor(cel(l, e.value['nota'] ?? -1)),
                'faltas': numero(cel(l, e.value['faltas'] ?? -1)),
              }
        ],
      ));
    }
    if (out.isNotEmpty) break; // a primeira tabela que deu certo e o boletim
  }
  return out;
}

dom.Element? _linhaComTexto(List<dom.Element> linhas, String texto) {
  for (final tr in linhas) {
    final primeira = tr.children.where((e) => e.localName == 'td' || e.localName == 'th').firstOrNull;
    if (primeira != null && limpar(primeira.text) == texto) return tr;
  }
  return null;
}

String _valor(String s) => s == '-' || s == '--' ? '' : s;

bool _ehSubcabecalho(List<String> cab, List<String> l) {
  // celulas com rowspan se repetem na 2a linha: so contam as que mudaram
  final n = [
    for (var i = 0; i < l.length; i++)
      if (norm(l[i]).isNotEmpty && (i >= cab.length || norm(cab[i]) != norm(l[i]))) norm(l[i])
  ];
  if (n.isEmpty) return false;
  final curtos = n.where((c) => RegExp(r'^(nota|notas|n|f|faltas?|media|freq.*|%|mf|rec.*|n\s?\d|f\s?\d)$').hasMatch(c));
  return curtos.length >= n.length / 2;
}

String _rotulo(String s) {
  final m = RegExp(r'^(\d)a etapa$').firstMatch(s);
  if (m != null) return '${m[1]}ª etapa';
  return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

// ---------------------------------------------------------------- diarios

/// Quanto foi lido dos diarios.
class LeituraDiarios {
  final int disciplinas; // disciplinas com frequencia/faltas lidas
  final int avaliacoes; // avaliacoes (com ou sem nota) lidas
  const LeituraDiarios(this.disciplinas, this.avaliacoes);
  bool get vazia => disciplinas == 0 && avaliacoes == 0;
}

/// Le frequencia, faltas, aulas previstas, professor e avaliacoes dos diarios.
///
/// IFES: cada diario e uma linha "900102 - 20262.BSI.5 - Nome (30H) - PROFESSOR" com uma
/// tabela de frequencia ao lado, seguida (as vezes) de "Nota do Semestre" com linhas
/// "data, Prova: descricao | Peso: x | Nota Maxima: y | Nota: z".
LeituraDiarios lerDiarios(String pagina, List<Disciplina> disciplinas) {
  if (disciplinas.isEmpty) return const LeituraDiarios(0, 0);
  final doc = html.parse(pagina);
  Disciplina? atual;
  var lendoNotas = false;
  final comFrequencia = <Disciplina>{};
  var avaliacoes = 0;
  final reCab = RegExp(r'^(\d+)\s*-\s*\S+\s*-\s*(.+?)\s*\(\s*(\d+)\s*h\s*\)\s*(?:-\s*(.+))?$', caseSensitive: false);

  Disciplina? achar(String pauta, String nome) {
    for (final d in disciplinas) {
      if (d.pauta.isNotEmpty && d.pauta == pauta) return d;
    }
    final n = norm(nome);
    for (final d in disciplinas) {
      if (norm(d.nome) == n) return d;
    }
    for (final d in disciplinas) {
      final dn = norm(d.nome);
      if (dn.isNotEmpty && (dn.startsWith(n) || n.startsWith(dn))) return d;
    }
    return null;
  }

  // so linhas de tabelas "folha" e as linhas de cabecalho de diario: as tabelas de
  // layout repetem o texto da pagina inteira e confundiriam a leitura
  for (final tr in doc.querySelectorAll('tr')) {
    final celulas = tr.children.where((e) => e.localName == 'td' || e.localName == 'th').toList();
    if (celulas.isEmpty) continue;
    final primeira = celulas.first;

    final cab = primeira.querySelector('strong');
    if (cab != null && primeira.querySelector('table') == null) {
      final m = reCab.firstMatch(limpar(cab.text));
      if (m != null) {
        atual = achar(m[1]!, m[2]!);
        lendoNotas = false;
        final d = atual;
        if (d != null) {
          if (d.pauta.isEmpty) d.pauta = m[1]!;
          d.carga ??= numero(m[3]);
          if (d.professor.isEmpty && m[4] != null) d.professor = _nomeProprio(m[4]!);
        }
        continue;
      }
    }
    final d = atual;
    if (d == null) continue;

    // "Nota do Semestre" (titulo do bloco de avaliacoes)
    final titulo = primeira.children.where((e) => e.localName == 'div').firstOrNull;
    if (celulas.length == 1 && titulo != null && norm(titulo.text).contains('nota do semestre')) {
      lendoNotas = true;
      continue;
    }
    if (celulas.any((c) => c.querySelector('table') != null)) continue;

    final textos = celulas.map((e) => limpar(e.text)).toList();
    if (celulas.length == 2) {
      final rotulo = norm(textos[0]);
      final valor = textos[1];
      if (rotulo.contains('numero de aulas previsto') || rotulo.contains('total de aulas previsto')) {
        d.aulas = numero(valor) ?? d.aulas;
        comFrequencia.add(d);
      } else if (rotulo == 'faltas') {
        d.faltas = numero(valor) ?? d.faltas;
        comFrequencia.add(d);
      } else if (rotulo.contains('presenca obrigatorio')) {
        d.minima = numero(valor) ?? d.minima;
      } else if (rotulo.contains('presenca') && rotulo.contains('ministradas')) {
        d.frequencia = numero(valor) ?? d.frequencia; // referencia do historico escolar
      } else if (rotulo.contains('carga horaria prevista')) {
        d.carga ??= numero(valor);
      }
      continue;
    }

    if (!lendoNotas) continue;
    final iNota = textos.indexWhere((s) => RegExp(r'^nota\s*:').hasMatch(s.toLowerCase()));
    if (iNota < 0) continue;
    String depois(String s) => limpar(s.replaceFirst(RegExp(r'^[^:]*:\s*'), ''));
    final nota = depois(textos[iNota]);
    final max = depois(textos.firstWhere((s) => norm(s).startsWith('nota maxima'), orElse: () => ''));
    final peso = depois(textos.firstWhere((s) => norm(s).startsWith('peso'), orElse: () => ''));
    final desc = textos.firstWhere(
        (s) => s.isNotEmpty && !RegExp(r'^(peso|nota)', caseSensitive: false).hasMatch(s.trim()),
        orElse: () => '');
    final data = RegExp(r'\d{2}/\d{2}/\d{4}').firstMatch(desc)?[0] ?? '';
    final descricao = limpar(desc
        .replaceFirst(RegExp(r'^\s*\d{2}/\d{2}/\d{4}(\s+\d{1,2}:\d{2}(:\d{2})?)?\s*,?\s*'), '')
        .replaceFirst(RegExp(r'^(prova|avaliacao|avaliação)\s*:\s*', caseSensitive: false), ''));
    if (descricao.isEmpty) continue;
    d.avaliacoes.add({
      'descricao': descricao,
      'nota': nota,
      'max': max,
      'peso': peso,
      'data': data,
      'etapa': 'Nota do semestre',
    });
    avaliacoes++;
  }

  // Formato antigo: tabelas com cabecalho "Avaliacao/Descricao" + "Nota".
  if (avaliacoes == 0) avaliacoes = _diariosEmTabela(doc, disciplinas);
  return LeituraDiarios(comFrequencia.length, avaliacoes);
}

/// "PROFESSOR EXEMPLO UM" -> "Professor Exemplo Um"
String _nomeProprio(String s) => limpar(s)
    .split(' ')
    .map((p) => p.isEmpty ? p : (p.length <= 2 && p == p.toLowerCase() ? p : p[0].toUpperCase() + p.substring(1).toLowerCase()))
    .join(' ')
    .replaceAllMapped(RegExp(r'\b(Da|De|Do|Das|Dos|E)\b'), (m) => m[0]!.toLowerCase());

int _diariosEmTabela(dom.Document doc, List<Disciplina> disciplinas) {
  var lidas = 0;
  final textoTodo = norm(doc.body?.text ?? '');
  var cursor = 0;
  for (final t in doc.querySelectorAll('table').where(_folha)) {
    final g = grade(t);
    final h = g.indexWhere((l) {
      final n = l.map(norm).toList();
      return n.any((c) => c.contains('avalia') || c.contains('descri')) && n.any((c) => c.contains('nota'));
    });
    if (h < 0) continue;
    final inicio = _posicao(textoTodo, norm(t.text), cursor);
    if (inicio < 0) continue;
    cursor = inicio;
    final antes = textoTodo.substring(0, inicio);
    Disciplina? dono;
    var melhor = -1;
    for (final d in disciplinas) {
      for (final chave in [norm(d.nome), if (d.codigo.isNotEmpty) norm(d.codigo)]) {
        final p = antes.lastIndexOf(chave);
        if (p > melhor) {
          melhor = p;
          dono = d;
        }
      }
    }
    final d = dono;
    if (d == null) continue;
    final r = g[h].map(norm).toList();
    int col(bool Function(String) f) => r.indexWhere(f);
    final cDesc = col((c) => c.contains('avalia') || c.contains('descri'));
    final cNota = col((c) => c.contains('nota') && !c.contains('max'));
    final cMax = col((c) => c.contains('max') || c.contains('valor'));
    final cPeso = col((c) => c.contains('peso'));
    final cData = col((c) => c.contains('data'));
    final cEtapa = col((c) => c.contains('etapa'));
    String cel(List<String> l, int i) => i >= 0 && i < l.length ? l[i] : '';
    for (final l in g.skip(h + 1)) {
      final desc = cel(l, cDesc);
      if (desc.isEmpty || (norm(desc).contains('avalia') && cel(l, cNota).isEmpty) || norm(desc).startsWith('total')) {
        continue;
      }
      d.avaliacoes.add({
        'descricao': desc,
        'nota': _valor(cel(l, cNota)),
        'max': cel(l, cMax),
        'peso': cel(l, cPeso),
        'data': cel(l, cData),
        'etapa': cel(l, cEtapa),
      });
      lidas++;
    }
  }
  return lidas;
}

int _posicao(String todo, String trecho, int desde) {
  if (trecho.isEmpty) return -1;
  final amostra = trecho.length > 60 ? trecho.substring(0, 60) : trecho;
  return todo.indexOf(amostra, desde);
}

// ---------------------------------------------------------------- horario

const diasSemana = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];
const _diasNorm = ['segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado', 'domingo'];

/// Uma aula no horario (blocos seguidos da mesma disciplina viram uma aula so).
class Aula {
  final int dia; // 1 = segunda ... 7 = domingo (DateTime.weekday)
  final String inicio; // "07:00"
  final String fim; // "08:40"
  final String disciplina; // nome da disciplina do boletim (ou o texto da celula)
  final String detalhe; // sala, turma...
  final int aulas; // quantos horarios seguidos (= faltas se faltar)
  const Aula(this.dia, this.inicio, this.fim, this.disciplina, this.detalhe, this.aulas);

  Map<String, dynamic> toJson() =>
      {'dia': dia, 'inicio': inicio, 'fim': fim, 'disciplina': disciplina, 'detalhe': detalhe, 'aulas': aulas};
  factory Aula.fromJson(Map<String, dynamic> j) => Aula((j['dia'] as num?)?.toInt() ?? 1, '${j['inicio'] ?? ''}',
      '${j['fim'] ?? ''}', '${j['disciplina'] ?? ''}', '${j['detalhe'] ?? ''}', (j['aulas'] as num?)?.toInt() ?? 1);

  int get minutosInicio => _min(inicio);
  int get minutosFim => _min(fim);
  static int _min(String h) {
    final m = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(h);
    return m == null ? 0 : int.parse(m[1]!) * 60 + int.parse(m[2]!);
  }
}

int? _diaHorario(String texto) {
  final n = norm(texto);
  final nome = _diasNorm.indexWhere((d) => n.startsWith(d));
  if (nome >= 0) return nome + 1;
  // IFES: "2a-feira" e segunda ... "7a-feira"/sabado; "1a-feira" seria domingo.
  final ordinal = RegExp(r'^([1-7])\s?a?\s?[- ]?\s?feira').firstMatch(n);
  if (ordinal == null) return null;
  return (int.parse(ordinal[1]!) + 5) % 7 + 1;
}

/// Siglas da legenda do horario: "RC - BSI.26 - Redes de Computadores - Professor".
Map<String, String> _legendaHorario(dom.Document doc) {
  final out = <String, String>{};
  for (final td in doc.querySelectorAll('td')) {
    if (td.querySelector('table') != null) continue;
    final m = RegExp(r'^([A-Z0-9]{1,8})\s+-\s+[A-Z0-9.]+\s+-\s+(.+?)(?:\s+-\s+[^-]+)?$').firstMatch(limpar(td.text));
    if (m != null) out[m[1]!] = m[2]!;
  }
  return out;
}

/// Le a grade de horario (dias por nome ou "2a-FEIRA", horarios com "-" ou "~").
List<Aula> lerHorario(String pagina, List<Disciplina> disciplinas) {
  final doc = html.parse(pagina);
  final legenda = _legendaHorario(doc);
  for (final t in doc.querySelectorAll('table').where(_folha)) {
    final linhas = t.querySelectorAll('tr').where((tr) => _tabelaDe(tr) == t).toList();
    List<dom.Element> celulasDe(dom.Element tr) =>
        tr.children.where((e) => e.localName == 'td' || e.localName == 'th').toList();
    final h = linhas.indexWhere((tr) => celulasDe(tr).where((e) => _diaHorario(e.text) != null).length >= 3);
    if (h < 0) continue;
    final cab = celulasDe(linhas[h]);
    final colDia = <int, int>{};
    for (var i = 0; i < cab.length; i++) {
      final d = _diaHorario(cab[i].text);
      if (d != null) colDia[i] = d;
    }
    final slots = <(int, String, String, String, String)>[]; // dia, inicio, fim, disciplina, detalhe
    for (final tr in linhas.skip(h + 1)) {
      final celulas = celulasDe(tr);
      if (celulas.isEmpty) continue;
      final hora = RegExp(r'(\d{1,2}[:h]\d{2})\s*(?:~|–|—|-|a|as|às|ate|até)?\s*(\d{1,2}[:h]\d{2})?')
          .firstMatch(celulas.first.text);
      if (hora == null) continue;
      final ini = hora[1]!.replaceAll('h', ':');
      final fim = (hora[2] ?? hora[1]!).replaceAll('h', ':');
      for (final e in colDia.entries) {
        if (e.key >= celulas.length) continue;
        final cel = celulas[e.key];
        final texto = limpar(cel.text);
        if (texto.isEmpty || texto == '-') continue;
        // IFES: <div title="Nome">SIGLA</div><div title="sala">BL09 903T</div><div>turma</div>
        final partes = cel.querySelectorAll('div').where((d) => d.querySelector('div') == null).toList();
        final sigla = partes.isEmpty ? texto : limpar(partes.first.text);
        final titulo = partes.isEmpty ? '' : limpar(partes.first.attributes['title'] ?? '');
        final nomeBase = titulo.isNotEmpty ? titulo : (legenda[sigla] ?? (partes.isEmpty ? texto : sigla));
        final detalhe = partes.length > 1
            ? partes.skip(1).map((d) => limpar(d.text)).where((s) => s.isNotEmpty).join(' · ')
            : '';
        final (nome, resto) = _disciplinaDaCelula(nomeBase, disciplinas);
        slots.add((e.value, _hh(ini), _hh(fim), nome, detalhe.isNotEmpty ? detalhe : resto));
      }
    }
    if (slots.isEmpty) continue;
    slots.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : Aula._min(a.$2).compareTo(Aula._min(b.$2)));
    final out = <Aula>[];
    for (final s in slots) {
      final ult = out.isEmpty ? null : out.last;
      if (ult != null && ult.dia == s.$1 && norm(ult.disciplina) == norm(s.$4) && Aula._min(s.$2) - ult.minutosFim <= 20) {
        out[out.length - 1] = Aula(ult.dia, ult.inicio, s.$3, ult.disciplina, ult.detalhe.isEmpty ? s.$5 : ult.detalhe, ult.aulas + 1);
      } else {
        out.add(Aula(s.$1, s.$2, s.$3, s.$4, s.$5, 1));
      }
    }
    return out;
  }
  return const [];
}

String _hh(String h) {
  final p = h.split(':');
  return '${p[0].padLeft(2, '0')}:${p.length > 1 ? p[1] : '00'}';
}

/// Acha a disciplina do boletim citada na celula (pelo nome ou codigo).
(String, String) _disciplinaDaCelula(String texto, List<Disciplina> ds) {
  final n = norm(texto);
  for (final d in ds) {
    final nn = norm(d.nome);
    if (nn.isNotEmpty && (n == nn || n.contains(nn) || nn.contains(n))) {
      final resto = limpar(texto
          .replaceAll(RegExp(RegExp.escape(d.nome), caseSensitive: false), '')
          .replaceAll(RegExp(r'^[\s\-–/|]+|[\s\-–/|]+$'), ''));
      return (d.nome, resto);
    }
  }
  for (final d in ds) {
    if (d.codigo.isNotEmpty && n.contains(norm(d.codigo))) return (d.nome, texto);
  }
  return (texto, '');
}

/// Maior bloco de aulas seguidas da disciplina num dia (faltar esse dia custa isto).
int aulasPorDia(String disciplina, List<Aula> horario, {int padrao = 2}) {
  final n = norm(disciplina);
  final porDia = <int, int>{};
  for (final a in horario.where((a) => norm(a.disciplina) == n)) {
    porDia[a.dia] = (porDia[a.dia] ?? 0) + a.aulas;
  }
  if (porDia.isEmpty) return padrao;
  return porDia.values.reduce((a, b) => a > b ? a : b);
}

/// Aulas de um dia (1-7), em ordem.
List<Aula> aulasDoDia(List<Aula> horario, int dia) =>
    horario.where((a) => a.dia == dia).toList()..sort((a, b) => a.minutosInicio.compareTo(b.minutosInicio));

// ---------------------------------------------------------------- novidades

/// O que mudou entre duas importacoes (nota nova, media, faltas).
List<String> mudancasAcademico(List<Disciplina> antes, List<Disciplina> agora) {
  if (antes.isEmpty) return const [];
  final ant = {for (final d in antes) norm(d.nome): d};
  final out = <String>[];
  for (final d in agora) {
    final a = ant[norm(d.nome)];
    if (a == null) continue;
    final notasAntes = {for (final e in a.etapas) '${e['rotulo']}': '${e['nota']}'};
    for (final e in d.etapas) {
      final nota = '${e['nota']}';
      if (numero(nota) != null && notasAntes['${e['rotulo']}'] != nota) {
        out.add('Nota no boletim: ${d.nome} · ${e['rotulo']}: $nota');
      }
    }
    final avAntes = {for (final v in a.avaliacoes) '${v['descricao']}': '${v['nota']}'};
    for (final v in d.avaliacoes) {
      final nota = '${v['nota']}';
      if (numero(nota) != null && avAntes['${v['descricao']}'] != nota) {
        out.add('Nota lançada: ${d.nome} · ${v['descricao']}: $nota');
      }
    }
    if (d.media.isNotEmpty && numero(d.media) != null && d.media != a.media) {
      out.add('Média atualizada: ${d.nome}: ${d.media}');
    }
    final fa = a.faltas ?? 0, fd = d.faltas ?? 0;
    if (fd > fa) {
      final r = frequencia(d).restantes;
      out.add('Falta registrada: ${d.nome} (${fd.toStringAsFixed(0)} no total'
          '${r == null ? '' : r >= 0 ? ', ainda pode ter $r' : ', passou do limite'})');
    }
  }
  return out;
}

// ---------------------------------------------------------------- questionários obrigatórios

/// Um questionário pendente (avaliação docente). No fim do semestre o Q-Acadêmico
/// bloqueia o resto do sistema até a pessoa responder os obrigatórios.
class QuestionarioQA {
  final String titulo;
  final String url;
  final String disciplina;
  final String professor;
  final bool obrigatorio;
  const QuestionarioQA({required this.titulo, required this.url, this.disciplina = '', this.professor = '', this.obrigatorio = true});
}

/// A página é a de "responda os questionários antes de continuar"?
bool ehBloqueioQuestionarios(String pagina) {
  final t = norm(pagina);
  return t.contains('questionario obrigatorio') ||
      (pagina.contains('t=1022') && pagina.contains('codAplicacaoQuestionario') && t.contains('selecione o questionario'));
}

/// Lista de questionários (página "Seleção de questionário"). [base] resolve links relativos.
List<QuestionarioQA> lerQuestionariosPendentes(String pagina, {String base = 'https://academico.ifes.edu.br/qacademico/'}) {
  final doc = html.parse(pagina);
  final out = <QuestionarioQA>[];
  var obrigatorio = true;
  // percorre as linhas na ordem: os rótulos "Obrigatórios:" / "Não Obrigatórios:" dividem a lista
  for (final tr in doc.querySelectorAll('tr')) {
    if (tr.querySelector('tr') != null) continue; // linha de layout
    final texto = norm(tr.text);
    if (texto.startsWith('nao obrigatorio')) {
      obrigatorio = false;
      continue;
    }
    if (texto.startsWith('obrigatorio')) {
      obrigatorio = true;
      continue;
    }
    for (final a in tr.querySelectorAll('a[href]')) {
      final href = a.attributes['href'] ?? '';
      if (!href.contains('t=1022') || !href.toLowerCase().contains('codaplicacaoquestionario')) continue;
      final titulo = limpar(a.text);
      final url = href.startsWith('http') ? href : Uri.parse(base).resolve(href.replaceFirst(RegExp(r'^/qacademico/'), '')).toString();
      // "Avaliação Docente - 2026/2 - campus X - Disciplina - Professor - 123"
      final partes = titulo.split(' - ').map((s) => s.trim()).toList();
      var disciplina = '', professor = '';
      if (partes.length >= 6) {
        disciplina = partes[partes.length - 3];
        professor = partes[partes.length - 2];
      } else if (partes.length >= 2) {
        disciplina = partes.last;
      }
      out.add(QuestionarioQA(titulo: titulo, url: url, disciplina: disciplina, professor: professor, obrigatorio: obrigatorio));
    }
  }
  return out;
}

/// Uma pergunta do formulário: de múltipla escolha (opções com valor e pontos) ou de texto.
class PerguntaQA {
  final String campo; // name do input (P_1234)
  final String texto;
  final List<(String valor, int? pontos)> opcoes;
  bool get deTexto => opcoes.isEmpty;
  const PerguntaQA(this.campo, this.texto, this.opcoes);
}

const _pontosPorExtenso = {
  'zero': 0, 'um': 1, 'uma': 1, 'dois': 2, 'duas': 2, 'tres': 3, 'quatro': 4, 'cinco': 5,
  'seis': 6, 'sete': 7, 'oito': 8, 'nove': 9, 'dez': 10,
};

/// "dez pontos" -> 10, "zero ponto" -> 0, "7" -> 7. Outro texto: null.
int? pontosDoRotulo(String rotulo) {
  final t = norm(rotulo);
  final n = RegExp(r'^(\d{1,2})\b').firstMatch(t);
  if (n != null) return int.parse(n.group(1)!);
  final p = RegExp(r'^([a-z]+)').firstMatch(t);
  if (p == null) return null;
  final w = p.group(1)!;
  // página salva com acento estragado ("tr?s"): o começo da palavra basta
  return _pontosPorExtenso[w] ?? (w == 'tr' ? 3 : null);
}

/// O que enviar num questionário: nota de 0 a 10 para as perguntas de escolha e um
/// comentário opcional para a pergunta de texto.
class RespostaQuestionario {
  final QuestionarioQA questionario;
  final int pontos;
  final String comentario;
  const RespostaQuestionario(this.questionario, this.pontos, {this.comentario = ''});
}

/// Perguntas do formulário de um questionário (form "frmquestionario").
List<PerguntaQA> lerFormularioQuestionario(String pagina) {
  final doc = html.parse(pagina);
  final form = doc.querySelector('form#frmquestionario') ?? doc.querySelector('form[name=frmquestionario]');
  if (form == null) return const [];
  final out = <PerguntaQA>[];
  final vistos = <String>{};
  final textos = form.querySelectorAll('.textoPergunta').map((e) => limpar(e.text)).toList();
  var i = 0;
  for (final input in form.querySelectorAll('input')) {
    final nome = input.attributes['name'] ?? '';
    final tipo = (input.attributes['type'] ?? 'text').toLowerCase();
    if (!RegExp(r'^P_\d+$').hasMatch(nome) || vistos.contains(nome)) continue;
    if (tipo != 'radio' && tipo != 'text' && tipo != 'textarea') continue;
    vistos.add(nome);
    final texto = i < textos.length ? textos[i] : nome;
    i++;
    if (tipo == 'radio') {
      final opcoes = <(String, int?)>[];
      for (final r in form.querySelectorAll('input[name="$nome"]')) {
        // o rótulo é o texto logo depois do botão ("dez pontos")
        opcoes.add((r.attributes['value'] ?? '', pontosDoRotulo(_textoDepois(r))));
      }
      out.add(PerguntaQA(nome, texto, opcoes));
    } else {
      out.add(PerguntaQA(nome, texto, const []));
    }
  }
  for (final t in form.querySelectorAll('textarea')) {
    final nome = t.attributes['name'] ?? '';
    if (RegExp(r'^P_\d+$').hasMatch(nome) && vistos.add(nome)) out.add(PerguntaQA(nome, i < textos.length ? textos[i++] : nome, const []));
  }
  return out;
}

/// Texto logo depois de um elemento, até o próximo input ou quebra de linha.
String _textoDepois(dom.Element e) {
  final irmaos = e.parentNode?.nodes ?? <dom.Node>[];
  final buf = StringBuffer();
  for (var i = irmaos.indexOf(e) + 1; i < irmaos.length; i++) {
    final n = irmaos[i];
    if (n is dom.Element && (n.localName == 'input' || n.localName == 'br')) break;
    buf.write(n.text ?? '');
  }
  return limpar(buf.toString());
}

/// Para cada pergunta de múltipla escolha, o valor da opção com [pontos] (ou a mais perto).
/// Perguntas sem pontos reconhecíveis ficam de fora (o envio confere e avisa).
Map<String, String> escolherRespostas(List<PerguntaQA> perguntas, int pontos) {
  final out = <String, String>{};
  for (final p in perguntas.where((p) => !p.deTexto)) {
    final comPontos = p.opcoes.where((o) => o.$2 != null).toList();
    if (comPontos.isEmpty) continue;
    comPontos.sort((a, b) => (a.$2! - pontos).abs().compareTo((b.$2! - pontos).abs()));
    out[p.campo] = comPontos.first.$1;
  }
  return out;
}
