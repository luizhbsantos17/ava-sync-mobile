// Leitor do Q-Academico (boletim/diarios), frequencia, notas do AVA e tema em JSON.
import 'package:ava_sync_mobile/qacademico.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:ava_sync_mobile/tema.dart';
import 'package:ava_sync_mobile/telas/desempenho.dart';
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
    test('limite de 25% da carga e quantas ainda pode ter', () {
      final d = Disciplina(nome: 'BD', carga: 40, faltas: 9);
      final f = frequencia(d);
      expect(f.limite, 10);
      expect(f.restantes, 1);
      expect(f.percentual, closeTo(77.5, 0.01));
      expect(f.emRisco, isTrue);
    });

    test('usa o % do Q-Academico quando existe e respeita a frequencia minima escolhida', () {
      final d = Disciplina(nome: 'R', carga: 60, faltas: 8, frequencia: 86.7);
      expect(frequencia(d).percentual, 86.7);
      expect(frequencia(d, minima: 80).limite, 12);
    });

    test('resumo pondera pela carga', () {
      final r = resumoAcademico([
        Disciplina(nome: 'a', carga: 60, faltas: 0, media: '8,0'),
        Disciplina(nome: 'b', carga: 20, faltas: 10, media: '6,0'),
      ]);
      expect(r.frequencia, closeTo((100 * 60 + 50 * 20) / 80, 0.01));
      expect(r.media, closeTo(7, 0.01));
      expect(r.emRisco, 1);
    });
  });

  test('mudancas: nota nova, media e falta', () {
    final antes = lerBoletim(boletim);
    final depois = lerBoletim(boletim
        .replaceFirst('<td>8,0</td><td>4</td><td>7,8</td>', '<td>9,0</td><td>4</td><td>8,3</td>')
        .replaceFirst('<td>40</td><td>9</td>', '<td>40</td><td>10</td>'));
    final m = mudancasAcademico(antes, depois);
    expect(m, contains('Nota no Q-Acadêmico: Redes de Computadores · 2ª etapa: 9,0'));
    expect(m, contains('Média atualizada: Redes de Computadores: 8,3'));
    expect(m.any((t) => t.startsWith('Falta registrada: Banco de Dados (10 no total, ainda pode ter 0)')), isTrue);
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
