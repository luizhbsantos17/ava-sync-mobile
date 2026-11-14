import 'config.dart';
import 'util.dart';

/// Semestre atual x antigo, e atividade x prova.
///
/// O Moodle chama de "em andamento" todo curso sem data de fim, entao materias de
/// semestres passados continuam aparecendo. Aqui o app adivinha o semestre atual e
/// a pessoa pode corrigir na mao (o ajuste manual sempre vence).

/// "2026/2", "2026-2", "2026.2", "2026_02" -> 20262. null se o nome nao tiver.
int? semestreDoNome(String nome) {
  final m = RegExp(r'(20\d\d)\s*[/\-._]\s*0?([12])(?!\d)').firstMatch(nome);
  if (m == null) return null;
  return int.parse(m[1]!) * 10 + int.parse(m[2]!);
}

/// Decide quais cursos sao do semestre atual.
/// [atividade]: ultima data com algo acontecendo no curso (prazo, acesso).
Map<String, bool> cursosAtuais(List<Map<String, dynamic>> cursos, Map<String, int> atividade, int agora,
    {Map<String, dynamic>? manual}) {
  final man = manual ?? Cfg.atualManual;
  const dia = 86400;
  // curso que so comeca daqui a mais de um mes (ex.: proximo semestre ja criado) nao
  // pode definir qual e o semestre "atual"
  bool jaComecou(Map<String, dynamic> c) => ((c['startdate'] as num?)?.toInt() ?? 0) <= agora + 30 * dia;
  final sems = {for (final c in cursos) '${c['id']}': semestreDoNome('${c['fullname'] ?? ''} ${c['shortname'] ?? ''}')};
  final semMax = cursos
      .where(jaComecou)
      .map((c) => sems['${c['id']}'])
      .whereType<int>()
      .fold<int?>(null, (a, b) => a == null || b > a ? b : a);
  final inicios = cursos
      .where(jaComecou)
      .map((c) => (c['startdate'] as num?)?.toInt() ?? 0)
      .where((s) => s > 0)
      .toList();
  final inicioMax = inicios.isEmpty ? 0 : inicios.reduce((a, b) => a > b ? a : b);
  final out = <String, bool>{};
  for (final c in cursos) {
    final id = '${c['id']}';
    if (man[id] is bool) {
      out[id] = man[id] as bool;
      continue;
    }
    final sem = sems[id];
    final inicio = (c['startdate'] as num?)?.toInt() ?? 0;
    final fim = (c['enddate'] as num?)?.toInt() ?? 0;
    if (sem != null && semMax != null) {
      // semestre no nome: atual se for o mais recente (ou um ja criado para o futuro)
      out[id] = sem >= semMax;
    } else if (inicio > 0 && inicioMax > 0) {
      // data de inicio decide antes da data de fim: professor as vezes poe fim errado,
      // e o Moodle tira o curso de "em andamento" mesmo sendo deste semestre
      out[id] = inicio >= inicioMax - 120 * dia;
    } else if (fim > 0 && fim < agora - 7 * dia) {
      out[id] = false;
    } else {
      out[id] = (atividade[id] ?? agora) >= agora - 30 * dia;
    }
  }
  return out;
}

final _reProvaForte = RegExp(
    r'(\bprovas?\b|\bexames?\b|\bsimulado\b|recupera[cç][aã]o|\b[PN][1-6]\b|\bAV[1-4]\b|segunda chamada|2[ªa] chamada)',
    caseSensitive: false);
final _reAvaliacao = RegExp(r'avalia[cç][aã]o', caseSensitive: false);

bool pareceProva(String nome) => _reProvaForte.hasMatch(nome);

/// "prova" ou "atividade".
/// - tarefa (entrega de arquivo): atividade, a nao ser que o nome diga claramente que e prova;
/// - questionario: prova se o nome indicar ou se tiver tempo limite; senao, atividade;
/// - evento do calendario (sem atividade ligada, ex.: prova presencial): prova se o nome indicar.
String categoria(String tipo, Map<String, dynamic> item) {
  final chave = '$tipo:${item['id']}';
  final man = Cfg.categoriaManual[chave];
  if (man == 'prova' || man == 'atividade') return man as String;
  final nome = '${item['nome'] ?? ''}';
  switch (tipo) {
    case 'quiz':
      return pareceProva(nome) || _reAvaliacao.hasMatch(nome) || ((item['limite'] as num?) ?? 0) > 0
          ? 'prova'
          : 'atividade';
    case 'evento':
      return pareceProva(nome) || _reAvaliacao.hasMatch(nome) ? 'prova' : 'atividade';
    default:
      return pareceProva(nome) ? 'prova' : 'atividade';
  }
}

String rotuloTipo(String tipo) => switch (tipo) {
      'tarefa' => 'tarefa',
      'quiz' => 'questionário',
      'evento' => 'evento do calendário',
      _ => tipo,
    };

/// Itens de um curso ja separados.
({List<Map<String, dynamic>> atividades, List<Map<String, dynamic>> provas}) itensDoCurso(Map<String, dynamic> c) {
  final atv = <Map<String, dynamic>>[];
  final prv = <Map<String, dynamic>>[];
  void add(String tipo, Map<String, dynamic> it, int ts) {
    final e = {'tipo': tipo, 'item': it, 'ts': ts, 'cat': categoria(tipo, it), 'curso': c};
    (e['cat'] == 'prova' ? prv : atv).add(e);
  }

  for (final t in lista(c['tarefas']).map(mapa)) {
    add('tarefa', t, (t['entrega'] as num?)?.toInt() ?? 0);
  }
  for (final q in lista(c['provas']).map(mapa)) {
    add('quiz', q, (q['fecha'] as num?)?.toInt() ?? (q['abre'] as num?)?.toInt() ?? 0);
  }
  for (final e in lista(c['eventos']).map(mapa)) {
    add('evento', e, (e['ts'] as num?)?.toInt() ?? 0);
  }
  int ord(Map a, Map b) => (b['ts'] as int).compareTo(a['ts'] as int);
  atv.sort(ord);
  prv.sort(ord);
  return (atividades: atv, provas: prv);
}

const _meses = {
  'janeiro': 1, 'fevereiro': 2, 'março': 3, 'marco': 3, 'abril': 4, 'maio': 5, 'junho': 6,
  'julho': 7, 'agosto': 8, 'setembro': 9, 'outubro': 10, 'novembro': 11, 'dezembro': 12,
};

/// Provas presenciais que so existem no cronograma (tabela num rotulo ou no resumo da
/// secao), sem item no Moodle. Ex.: "N5 - Prova Individual Presencial | ... | 27 de Novembro".
/// [inicio]: data de inicio do curso (para descobrir o ano).
List<Map<String, dynamic>> provasDoCronograma(String html, DateTime inicio) {
  final out = <Map<String, dynamic>>[];
  for (final tr in RegExp(r'<tr\b[^>]*>(.*?)</tr>', caseSensitive: false, dotAll: true).allMatches(html)) {
    final celulas = RegExp(r'<t[dh]\b[^>]*>(.*?)</t[dh]>', caseSensitive: false, dotAll: true)
        .allMatches(tr[1]!)
        .map((m) => semHtml(m[1]).replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (celulas.isEmpty) continue;
    final linha = celulas.join(' | ');
    if (!RegExp(r'\bprovas?\b|\bexames?\b', caseSensitive: false).hasMatch(linha)) continue;
    DateTime? data;
    final porExtenso = RegExp(r'(\d{1,2})\s+de\s+([A-Za-zçÇ]+)', caseSensitive: false).allMatches(linha).toList();
    for (final m in porExtenso.reversed) {
      final mes = _meses[m[2]!.toLowerCase()];
      if (mes != null) {
        data = DateTime(inicio.year, mes, int.parse(m[1]!), 8);
        break;
      }
    }
    if (data == null) {
      final m = RegExp(r'(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?').allMatches(linha).lastOrNull;
      if (m != null) {
        final ano = m[3] == null ? inicio.year : (m[3]!.length == 2 ? 2000 + int.parse(m[3]!) : int.parse(m[3]!));
        data = DateTime(ano, int.parse(m[2]!), int.parse(m[1]!), 8);
      }
    }
    if (data == null) continue;
    // semestre que vira o ano (ex.: comeca em agosto, prova em fevereiro)
    if (data.isBefore(inicio.subtract(const Duration(days: 30)))) data = DateTime(data.year + 1, data.month, data.day, 8);
    final nome = celulas.first;
    out.add({
      'id': 'cr${hashCurto('$nome${data.toIso8601String()}')}',
      'nome': nome,
      'ts': data.millisecondsSinceEpoch ~/ 1000,
      'html': '<p><b>Do cronograma da disciplina:</b></p><p>${celulas.join('<br>')}</p>'
          '<p><i>Horário não informado no cronograma.</i></p>',
      'cronograma': true,
    });
  }
  return out;
}
