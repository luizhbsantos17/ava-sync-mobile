import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'armazenamento.dart';
import 'util.dart';

/// Dados do Q-Academico (boletim e diarios), lidos das paginas que a propria pessoa
/// abre logada no navegador interno do app. O Q-Academico nao tem API e bloqueia
/// robos, por isso o app nunca acessa o site sozinho por HTTP.
class QAcademico {
  static const urlPadrao = 'https://academico.ifes.edu.br/qacademico/index.asp?t=1001';

  /// Paginas lidas apos o login (relativas a /qacademico/).
  static const paginaBoletim = 'index.asp?t=2032';
  static const paginaDiarios = 'index.asp?t=2071';

  static Future<Map<String, dynamic>> carregar() => Store.lerJson('academico.json');
  static Future<void> salvar(Map<String, dynamic> d) => Store.gravarJson('academico.json', d);
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
      final texto = limpar(td.text);
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

String _norm(String s) => limpar(s)
    .toLowerCase()
    .replaceAll(RegExp('[áàâã]'), 'a')
    .replaceAll(RegExp('[éê]'), 'e')
    .replaceAll('í', 'i')
    .replaceAll(RegExp('[óôõ]'), 'o')
    .replaceAll('ú', 'u')
    .replaceAll('ç', 'c');

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
  double? carga; // carga horaria (h ou aulas, como o Q-Academico mostra)
  double? faltas;
  double? frequencia; // % informado pelo Q-Academico
  String media;
  String situacao;
  List<Map<String, dynamic>> etapas; // {rotulo, nota, faltas}
  List<Map<String, dynamic>> avaliacoes; // {etapa, descricao, nota, max, peso, data}

  Disciplina({
    required this.nome,
    this.codigo = '',
    this.carga,
    this.faltas,
    this.frequencia,
    this.media = '',
    this.situacao = '',
    List<Map<String, dynamic>>? etapas,
    List<Map<String, dynamic>>? avaliacoes,
  })  : etapas = etapas ?? [],
        avaliacoes = avaliacoes ?? [];

  Map<String, dynamic> toJson() => {
        'nome': nome,
        'codigo': codigo,
        'carga': carga,
        'faltas': faltas,
        'frequencia': frequencia,
        'media': media,
        'situacao': situacao,
        'etapas': etapas,
        'avaliacoes': avaliacoes,
      };

  factory Disciplina.fromJson(Map<String, dynamic> j) => Disciplina(
        nome: '${j['nome'] ?? ''}',
        codigo: '${j['codigo'] ?? ''}',
        carga: (j['carga'] as num?)?.toDouble(),
        faltas: (j['faltas'] as num?)?.toDouble(),
        frequencia: (j['frequencia'] as num?)?.toDouble(),
        media: '${j['media'] ?? ''}',
        situacao: '${j['situacao'] ?? ''}',
        etapas: lista(j['etapas']).map(mapa).toList(),
        avaliacoes: lista(j['avaliacoes']).map(mapa).toList(),
      );
}

/// Frequencia e faltas: o que da para calcular com carga horaria e faltas.
class Frequencia {
  final double? percentual; // presenca, 0-100
  final double? faltasPercentual;
  final int? limite; // faltas permitidas no total
  final int? restantes; // quantas ainda pode ter (negativo = passou)
  const Frequencia(this.percentual, this.faltasPercentual, this.limite, this.restantes);

  bool get emRisco => restantes != null && restantes! <= 2;
}

Frequencia frequencia(Disciplina d, {double minima = 75}) {
  final carga = d.carga;
  final faltas = d.faltas ?? 0;
  double? pres = d.frequencia;
  if (pres == null && carga != null && carga > 0) pres = (100 * (1 - faltas / carga)).clamp(0, 100).toDouble();
  final limite = carga == null || carga <= 0 ? null : (carga * (100 - minima) / 100).floor();
  return Frequencia(pres, pres == null ? null : 100 - pres, limite, limite == null ? null : limite - faltas.ceil());
}

final _reEtapa = RegExp(r'etapa|bimestre|trimestre|semestre|\bn\d\b|\be\d\b|\d\s*[ao]\b|\d[ªº]');

/// Le o boletim (qualquer tabela com cabecalho "Disciplina" + faltas/frequencia/carga).
List<Disciplina> lerBoletim(String pagina) {
  final doc = html.parse(pagina);
  final out = <Disciplina>[];
  for (final t in doc.querySelectorAll('table')) {
    final g = grade(t);
    final h = g.indexWhere((l) {
      final n = l.map(_norm).toList();
      return n.any((c) => c.contains('disciplina')) &&
          n.any((c) => c.contains('falta') || c.contains('freq') || c.contains('carga'));
    });
    if (h < 0) continue;
    // cabecalho em duas linhas (ex.: "1ª Etapa" sobre "Nota | Faltas")
    var rotulos = g[h].map(_norm).toList();
    var inicio = h + 1;
    if (inicio < g.length && _ehSubcabecalho(g[h], g[inicio])) {
      final sub = g[inicio].map(_norm).toList();
      rotulos = [
        for (var i = 0; i < rotulos.length; i++)
          i < sub.length && sub[i] != rotulos[i] ? '${rotulos[i]} ${sub[i]}' : rotulos[i]
      ];
      inicio++;
    }
    int col(bool Function(String) f) => rotulos.indexWhere(f);
    final cNome = col((r) => r.contains('disciplina') && !r.contains('cod'));
    if (cNome < 0) continue;
    final cCod = col((r) => r.contains('cod'));
    final cCarga = col((r) => r.contains('carga') || RegExp(r'\bc\.?\s?h\b').hasMatch(r) || r.contains('aulas previstas'));
    final cFreq = col((r) => r.contains('freq') || r == '%');
    final cFaltas = col((r) =>
        r.contains('falta') && (r.contains('total') || !_reEtapa.hasMatch(r.replaceAll('total', ''))) && !r.contains('freq'));
    final cMedia = col((r) => r.contains('media') || r.contains('nota final') || r == 'mf' || r.contains('resultado'));
    final cSit = col((r) => r.contains('situa'));
    final usadas = {cNome, cCod, cCarga, cFreq, cFaltas, cMedia, cSit};

    // colunas de etapa: "1ª etapa nota", "n1", "e1 faltas"...
    final etapas = <String, Map<String, int>>{};
    for (var i = 0; i < rotulos.length; i++) {
      if (usadas.contains(i)) continue;
      final r = rotulos[i];
      if (!_reEtapa.hasMatch(r)) continue;
      final ehFalta = r.contains('falta') || RegExp(r'\bf\b').hasMatch(r);
      final base = limpar(r.replaceAll(RegExp(r'\b(nota|notas|faltas?|f|n)\b$'), ''));
      final rotulo = base.isEmpty ? r : base;
      etapas.putIfAbsent(rotulo, () => {})[ehFalta ? 'faltas' : 'nota'] = i;
    }

    String cel(List<String> l, int i) => i >= 0 && i < l.length ? l[i] : '';
    for (final l in g.skip(inicio)) {
      final nome = cel(l, cNome);
      final n = _norm(nome);
      if (nome.isEmpty || n.contains('disciplina') || n.startsWith('total') || numero(nome) != null && nome.length < 4) {
        continue;
      }
      out.add(Disciplina(
        nome: nome.replaceFirst(RegExp(r'^\d+\s*-\s*'), ''),
        codigo: cel(l, cCod),
        carga: numero(cel(l, cCarga)),
        faltas: numero(cel(l, cFaltas)),
        frequencia: numero(cel(l, cFreq)),
        media: cel(l, cMedia),
        situacao: cel(l, cSit),
        etapas: [
          for (final e in etapas.entries)
            if (cel(l, e.value['nota'] ?? -1).isNotEmpty || cel(l, e.value['faltas'] ?? -1).isNotEmpty)
              {
                'rotulo': _titulo(e.key),
                'nota': cel(l, e.value['nota'] ?? -1),
                'faltas': numero(cel(l, e.value['faltas'] ?? -1)),
              }
        ],
      ));
    }
  }
  return out;
}

bool _ehSubcabecalho(List<String> cab, List<String> l) {
  // celulas com rowspan se repetem na 2a linha: so contam as que mudaram
  final n = [
    for (var i = 0; i < l.length; i++)
      if (_norm(l[i]).isNotEmpty && (i >= cab.length || _norm(cab[i]) != _norm(l[i]))) _norm(l[i])
  ];
  if (n.isEmpty) return false;
  final curtos = n.where((c) => RegExp(r'^(nota|notas|n|f|faltas?|falta|media|freq.*|%|mf|rec.*)$').hasMatch(c));
  return curtos.length >= n.length / 2;
}

String _titulo(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ---------------------------------------------------------------- diarios

/// Le as avaliacoes dos diarios: tabelas com "avaliacao/descricao" + "nota". A disciplina
/// de cada tabela e o ultimo nome de disciplina (do boletim) que aparece antes dela.
void lerDiarios(String pagina, List<Disciplina> disciplinas) {
  if (disciplinas.isEmpty) return;
  final doc = html.parse(pagina);
  final textoTodo = _norm(doc.body?.text ?? '');
  final nomes = {for (final d in disciplinas) _norm(d.nome): d};
  var cursor = 0;
  for (final t in doc.querySelectorAll('table')) {
    final g = grade(t);
    final h = g.indexWhere((l) {
      final n = l.map(_norm).toList();
      return n.any((c) => c.contains('avalia') || c.contains('descri')) && n.any((c) => c.contains('nota'));
    });
    if (h < 0) continue;
    // so tabelas "folha" (a de fora tambem casa, mas contem as outras)
    if (t.querySelector('table') != null) continue;
    final inicioTabela = _posicao(textoTodo, _norm(t.text), cursor);
    if (inicioTabela < 0) continue;
    cursor = inicioTabela;
    final antes = textoTodo.substring(0, inicioTabela);
    Disciplina? dono;
    var melhor = -1;
    for (final e in nomes.entries) {
      final p = antes.lastIndexOf(e.key);
      if (p > melhor) {
        melhor = p;
        dono = e.value;
      }
    }
    if (dono == null) continue;
    final r = g[h].map(_norm).toList();
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
      if (desc.isEmpty || _norm(desc).contains('avalia') && cel(l, cNota).isEmpty) continue;
      dono.avaliacoes.add({
        'descricao': desc,
        'nota': cel(l, cNota),
        'max': cel(l, cMax),
        'peso': cel(l, cPeso),
        'data': cel(l, cData),
        'etapa': cel(l, cEtapa),
      });
    }
  }
}

int _posicao(String todo, String trecho, int desde) {
  if (trecho.isEmpty) return -1;
  final amostra = trecho.length > 60 ? trecho.substring(0, 60) : trecho;
  return todo.indexOf(amostra, desde);
}

// ---------------------------------------------------------------- novidades

/// O que mudou entre duas importacoes (nota nova, media, faltas).
List<String> mudancasAcademico(List<Disciplina> antes, List<Disciplina> agora) {
  if (antes.isEmpty) return const [];
  final ant = {for (final d in antes) _norm(d.nome): d};
  final out = <String>[];
  for (final d in agora) {
    final a = ant[_norm(d.nome)];
    if (a == null) continue;
    final notasAntes = {for (final e in a.etapas) '${e['rotulo']}': '${e['nota']}'};
    for (final e in d.etapas) {
      final nota = '${e['nota']}';
      if (numero(nota) != null && notasAntes['${e['rotulo']}'] != nota) {
        out.add('Nota no Q-Acadêmico: ${d.nome} · ${e['rotulo']}: $nota');
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
