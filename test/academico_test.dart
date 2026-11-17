// Leitor do Q-Academico (boletim/diarios), frequencia, notas do AVA e tema em JSON.
import 'package:ava_sync_mobile/qacademico.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:ava_sync_mobile/tema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

// Boletim no formato do Q-Academico: cabecalho em 2 linhas, etapas com colspan.
const boletim = '''
<html><body><table><tr><td>menu</td></tr></table>
<table class="conteudoTexto">
  <tr class="rotulo">
    <td rowspan="2">Cód. Disc.</td><td rowspan="2">Disciplina</td><td rowspan="2">Carga Horária</td>
    <td rowspan="2">Total de Faltas</td><td rowspan="2">% Freq.</td>
    <td colspan="2">1ª Etapa</td><td colspan="2">2ª Etapa</td>
    <td rowspan="2">Média Final</td><td rowspan="2">Situação</td>
  </tr>
  <tr class="rotulo"><td>Nota</td><td>Faltas</td><td>Nota</td><td>Faltas</td></tr>
  <tr><td>SI.101</td><td>101 - Redes de Computadores</td><td>60</td><td>8</td><td>86,7</td>
      <td>7,5</td><td>4</td><td>8,0</td><td>4</td><td>7,8</td><td>Cursando</td></tr>
  <tr><td>SI.102</td><td>Banco de Dados</td><td>40</td><td>9</td><td>&nbsp;</td>
      <td>6,0</td><td>9</td><td>-</td><td>&nbsp;</td><td>&nbsp;</td><td>Cursando</td></tr>
</table></body></html>
''';

const diarios = '''
<html><body>
<div>Diário de Redes de Computadores - Turma A</div>
<table><tr><td>Avaliação</td><td>Data</td><td>Peso</td><td>Nota Máx.</td><td>Nota</td></tr>
  <tr><td>Prova 1</td><td>10/09/2026</td><td>1</td><td>10</td><td>7,5</td></tr>
  <tr><td>Trabalho</td><td>01/10/2026</td><td>1</td><td>10</td><td>9,0</td></tr>
</table>
<div>Diário de Banco de Dados - Turma B</div>
<table><tr><td>Descrição</td><td>Nota</td></tr><tr><td>Lista SQL</td><td>6,0</td></tr></table>
</body></html>
''';

void main() {
  group('boletim', () {
    test('le disciplinas, carga, faltas, frequencia, etapas e media', () {
      final ds = lerBoletim(boletim);
      expect(ds, hasLength(2));
      final r = ds.first;
      expect(r.nome, 'Redes de Computadores');
      expect(r.codigo, 'SI.101');
      expect(r.carga, 60);
      expect(r.faltas, 8);
      expect(r.frequencia, closeTo(86.7, 0.01));
      expect(r.media, '7,8');
      expect(r.situacao, 'Cursando');
      expect(r.etapas.map((e) => e['rotulo']), ['1ª etapa', '2ª etapa']);
      expect(r.etapas.first['nota'], '7,5');
      expect(r.etapas.first['faltas'], 4);
    });

    test('pagina sem boletim nao inventa nada', () {
      expect(lerBoletim('<html><body><form name="frmLogin"></form></body></html>'), isEmpty);
    });
  });

  test('diarios: avaliacoes vao para a disciplina certa', () {
    final ds = lerBoletim(boletim);
    lerDiarios(diarios, ds);
    expect(ds[0].avaliacoes.map((a) => a['descricao']), ['Prova 1', 'Trabalho']);
    expect(ds[0].avaliacoes.last['nota'], '9,0');
    expect(ds[0].avaliacoes.first['max'], '10');
    expect(ds[1].avaliacoes.single['descricao'], 'Lista SQL');
  });

  group('frequencia', () {
    for (final (carga, limite) in [(30.0, 9), (60.0, 18), (90.0, 27)]) {
      test('carga de ${carga}h permite $limite faltas', () {
        for (final aulas in [null, carga, carga * 60 / 50]) {
          final d = Disciplina(nome: 'Disciplina exemplo', carga: carga, aulas: aulas, faltas: limite.toDouble());
          expect(frequencia(d).limite, limite);
          expect(frequencia(d).restantes, 0);
          expect(frequencia(d).reprovadoPorFalta, isFalse);
          d.faltas = limite + 1.0;
          expect(frequencia(d).reprovadoPorFalta, isTrue);
        }
      });
    }

    test('limite de 25% da carga, faltas restantes e dias que ainda pode faltar', () {
      final d = Disciplina(nome: 'BD', carga: 40, faltas: 4);
      final f = frequencia(d, aulasPorDia: 2);
      expect(f.limite, 12); // 40 horas = 48 aulas de 50 minutos
      expect(f.restantes, 8);
      expect(f.diasRestantes, 4); // cada dia de falta = 2 faltas
      expect(f.percentual, closeTo(100 * (1 - 4 / 48), 0.01));
      expect(f.emRisco, isFalse);
      expect(frequencia(Disciplina(nome: 'x', carga: 40, faltas: 9), aulasPorDia: 2).emRisco, isTrue);
      expect(frequencia(Disciplina(nome: 'x', carga: 40, faltas: 13)).reprovadoPorFalta, isTrue);
    });

    test('usa total de aulas quando existe, o % do Q-Academico e a frequencia minima escolhida', () {
      expect(frequencia(Disciplina(nome: 'R', carga: 60, aulas: 72, faltas: 0)).limite, 18);
      // presenca principal: sobre o total do semestre (72 aulas), nao sobre as aulas dadas
      final d = Disciplina(nome: 'R', carga: 60, faltas: 8, frequencia: 86.7);
      expect(frequencia(d).percentual, closeTo(100 * (1 - 8 / 72), 0.01));
      expect(frequencia(d).percentualDadas, 86.7);
      // sem carga horaria, so resta o % do Q-Academico
      expect(frequencia(Disciplina(nome: 'R', faltas: 8, frequencia: 86.7)).percentual, 86.7);
      expect(frequencia(d, minima: 80).limite, 14);
    });
  });

  test('boletim no formato N1/F1 e codigo junto do nome', () {
    final ds = lerBoletim('''
<table><tr><td>Disciplina</td><td>C.H.</td><td>N1</td><td>F1</td><td>N2</td><td>F2</td><td>Faltas</td><td>Freq. (%)</td><td>MF</td><td>Sit.</td></tr>
<tr><td>SIN.0123 - Cálculo I</td><td>80</td><td>5,5</td><td>2</td><td>--</td><td>0</td><td>2</td><td>97,5</td><td>-</td><td>Cursando</td></tr></table>''');
    final d = ds.single;
    expect(d.nome, 'Cálculo I');
    expect(d.codigo, 'SIN.0123');
    expect(d.carga, 80);
    expect(d.faltas, 2);
    expect(d.media, '');
    expect(d.etapas.map((e) => e['rotulo']), ['1ª etapa', '2ª etapa']);
    expect(d.etapas.first, {'rotulo': '1ª etapa', 'nota': '5,5', 'faltas': 2.0});
    expect(d.etapas.last['nota'], '');
  });

  group('horario', () {
    const pagina = '''
<table><tr><td>Horário</td><td>Segunda</td><td>Terça</td><td>Quarta</td><td>Quinta</td><td>Sexta</td></tr>
<tr><td>07:00 - 07:50</td><td>Português - Sala 5</td><td></td><td>Redes de Computadores</td><td></td><td></td></tr>
<tr><td>07:50 - 08:40</td><td>Português - Sala 5</td><td></td><td>Redes de Computadores</td><td></td><td></td></tr>
<tr><td>09:00 - 09:50</td><td>SI.102</td><td></td><td></td><td></td><td></td></tr>
<tr><td>09:50 - 10:40</td><td>SI.102</td><td></td><td></td><td></td><td></td></tr>
<tr><td>10:40 - 11:30</td><td>SI.102</td><td></td><td></td><td></td><td></td></tr>
</table>''';
    final ds = [
      Disciplina(nome: 'Português', carga: 40),
      Disciplina(nome: 'Banco de Dados', codigo: 'SI.102', carga: 60),
      Disciplina(nome: 'Redes de Computadores', carga: 60),
    ];

    test('junta horarios seguidos e acha a disciplina pelo nome ou codigo', () {
      final h = lerHorario(pagina, ds);
      final seg = aulasDoDia(h, 1);
      expect(seg.map((a) => a.disciplina), ['Português', 'Banco de Dados']);
      expect(seg.first.inicio, '07:00');
      expect(seg.first.fim, '08:40');
      expect(seg.first.aulas, 2);
      expect(seg.first.detalhe, 'Sala 5');
      expect(seg.last.aulas, 3);
      expect(aulasDoDia(h, 3).single.disciplina, 'Redes de Computadores');
    });

    test('faltar um dia custa o bloco de aulas do dia', () {
      final h = lerHorario(pagina, ds);
      expect(aulasPorDia('Português', h), 2);
      expect(aulasPorDia('Banco de Dados', h), 3);
      expect(aulasPorDia('Sem horário', h, padrao: 2), 2);
    });

    test('aula vai e volta pelo JSON', () {
      final a = lerHorario(pagina, ds).first;
      final b = Aula.fromJson(a.toJson());
      expect([b.dia, b.inicio, b.fim, b.disciplina, b.aulas], [a.dia, a.inicio, a.fim, a.disciplina, a.aulas]);
    });
  });

  test('mudancas: nota nova, media e falta', () {
    final antes = lerBoletim(boletim);
    final depois = lerBoletim(boletim
        .replaceFirst('<td>8,0</td><td>4</td><td>7,8</td>', '<td>9,0</td><td>4</td><td>8,3</td>')
        .replaceFirst('<td>40</td><td>9</td>', '<td>40</td><td>10</td>'));
    final m = mudancasAcademico(antes, depois);
    expect(m, contains('Nota no boletim: Redes de Computadores · 2ª etapa: 9,0'));
    expect(m, contains('Média atualizada: Redes de Computadores: 8,3'));
    expect(m.any((t) => t.startsWith('Falta registrada: Banco de Dados (10 no total, ainda pode ter 2)')), isTrue);
    expect(mudancasAcademico([], depois), isEmpty); // primeira importacao nao avisa
  });

  test('disciplina vai e volta pelo JSON', () {
    final d = lerBoletim(boletim).first;
    final j = Disciplina.fromJson(d.toJson());
    expect(j.nome, d.nome);
    expect(j.etapas, d.etapas);
    expect(j.frequencia, d.frequencia);
  });

  test('notas do AVA: ignora categorias, total por ultimo', () {
    final n = notasDoLivro({
      'usergrades': [
        {
          'gradeitems': [
            {'itemtype': 'course', 'gradeformatted': '78,00', 'percentageformatted': '78,00 %'},
            {'itemtype': 'category', 'itemname': 'Etapa 1'},
            {'itemtype': 'mod', 'itemmodule': 'quiz', 'itemname': 'Quiz 1', 'gradeformatted': '8,00', 'grademax': 10},
            {'itemtype': 'mod', 'itemmodule': 'assign', 'itemname': 'Tarefa', 'gradeformatted': '-'},
          ]
        }
      ]
    });
    expect(n.map((e) => e['nome']), ['Quiz 1', 'Tarefa', 'Total da matéria']);
    expect(n[1]['nota'], ''); // "-" = sem nota
    expect(n.last['pct'], '78,00 %');
  });

  group('tema', () {
    test('JSON completo vai e volta', () {
      const t = Tema(cor: Color(0xFF6EC6FF), modo: 'claro', fundo: Color(0xFF0B1320), raio: 10, fonte: 1.2, compacto: true);
      final j = Tema.fromJson(t.toJson());
      expect(hex(j.cor), '#6EC6FF');
      expect(j.modo, 'claro');
      expect(hex(j.fundo!), '#0B1320');
      expect(j.raio, 10);
      expect(j.fonte, 1.2);
      expect(j.compacto, isTrue);
    });

    test('erros claros e limites', () {
      expect(() => Tema.fromJson({'cor': 'roxo'}), throwsA(isA<FormatException>()));
      expect(() => Tema.fromJson({'modo': 'neon'}), throwsA(isA<FormatException>()));
      expect(Tema.fromJson({'raio': 999, 'fonte': 5}).raio, 40);
      expect(Tema.deTexto('{quebrado').cor, Tema.padrao.cor);
    });

    test('todos os temas prontos constroem', () {
      for (final t in Tema.presets.values) {
        expect(t.construir(Brightness.dark).colorScheme.primary, isNotNull);
        expect(t.construir(Brightness.light).colorScheme.primary, isNotNull);
      }
    });
  });
}
