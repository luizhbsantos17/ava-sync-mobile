import 'classificar.dart';
import 'util.dart';

/// Um prazo/prova com data, usado pelos lembretes e pelo calendario.
class Compromisso {
  /// Chave estavel: "tarefa:12", "quiz:3", "evento:9".
  final String chave;
  final String tipo; // tarefa | quiz | evento
  final String cat; // prova | atividade
  final String nome;
  final String curso;
  final int ts; // segundos
  final int duracao; // segundos (0 = pontual)
  final bool entregue;
  final String link;

  const Compromisso({
    required this.chave,
    required this.tipo,
    required this.cat,
    required this.nome,
    required this.curso,
    required this.ts,
    this.duracao = 0,
    this.entregue = false,
    this.link = '',
  });

  String get rotulo => switch (tipo) {
        'tarefa' => 'Entrega',
        'quiz' => cat == 'prova' ? 'Prova' : 'Questionário',
        _ => cat == 'prova' ? 'Prova' : 'Evento',
      };
}

/// Compromissos das materias do semestre atual (respeita o ajuste manual).
List<Compromisso> compromissos(Map<String, dynamic> snap, Map<String, dynamic> atualManual) {
  final out = <Compromisso>[];
  for (final c in lista(snap['cursos']).map(mapa)) {
    final man = atualManual['${c['id']}'];
    if (!(man is bool ? man : c['atual'] != false)) continue;
    final it = itensDoCurso(c);
    for (final e in [...it.atividades, ...it.provas]) {
      final item = mapa(e['item']);
      final ts = e['ts'] as int;
      if (ts <= 0) continue;
      final tipo = '${e['tipo']}';
      out.add(Compromisso(
        chave: '$tipo:${item['id']}',
        tipo: tipo,
        cat: '${e['cat']}',
        nome: '${item['nome'] ?? ''}',
        curso: '${c['nome'] ?? ''}',
        ts: ts,
        duracao: (item['duracao'] as num?)?.toInt() ?? 0,
        entregue: tipo == 'tarefa' && item['situacao'] == 'submitted',
        link: '${item['link'] ?? ''}',
      ));
    }
  }
  out.sort((a, b) => a.ts.compareTo(b.ts));
  return out;
}

/// Um lembrete a agendar.
class Lembrete {
  final int quando; // segundos
  final String titulo;
  final String corpo;
  const Lembrete(this.quando, this.titulo, this.corpo);
}

const antecedencias = [3 * 86400, 86400, 3 * 3600];

String _falta(int seg) => switch (seg) {
      >= 2 * 86400 => 'em ${seg ~/ 86400} dias',
      >= 86400 => 'amanhã',
      _ => 'em ${seg ~/ 3600} horas',
    };

/// Lembretes futuros para os compromissos pendentes (no maximo [limite], os mais proximos).
List<Lembrete> lembretes(List<Compromisso> lista, int agora, {int limite = 60}) {
  final out = <Lembrete>[];
  for (final c in lista) {
    if (c.entregue || c.ts <= agora) continue;
    for (final a in antecedencias) {
      final quando = c.ts - a;
      if (quando <= agora) continue;
      final verbo = c.tipo == 'tarefa' ? 'vence' : (c.tipo == 'quiz' ? 'fecha' : 'é');
      out.add(Lembrete(
        quando,
        '${c.rotulo} ${_falta(a)}: ${c.nome}',
        '${c.curso}\n${c.rotulo} $verbo ${fmtData(c.ts)}${c.tipo == 'tarefa' ? ' · ainda não entregue' : ''}',
      ));
    }
  }
  out.sort((a, b) => a.quando.compareTo(b.quando));
  return out.take(limite).toList();
}
