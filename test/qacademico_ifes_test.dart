// Regressao do leitor do Q-Academico do IFES com fixtures sanitizadas que reproduzem o
// HTML real (tabelas de layout por fora, COD_PAUTA escondido, divs com title...).
import 'dart:io';

import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/estado_app.dart';
import 'package:ava_sync_mobile/qacademico.dart';
import 'package:ava_sync_mobile/telas/desempenho.dart';
import 'package:ava_sync_mobile/telas/qacademico_tela.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

String fixture(String nome) => File('test/fixtures/$nome').readAsStringSync();

void main() {
  final boletim = fixture('ifes_boletim.html');
  final diarios = fixture('ifes_diarios.html');
  final horario = fixture('ifes_horario.html');

  Disciplina por(List<Disciplina> ds, String nome) => ds.firstWhere((d) => d.nome == nome);

  group('boletim do IFES', () {
    test('le so a tabela do boletim, nunca o texto do aluno/rodape das tabelas de layout', () {
      final ds = lerBoletim(boletim);
      expect(ds.map((d) => d.nome), [
        'Álgebra Linear',
        'Administração da Produção e Logística',
        'Redes de Computadores',
        'Marketing',
      ]);
      for (final d in ds) {
        expect(d.nome, isNot(contains('Aluno Exemplo')));
        expect(d.nome, isNot(contains('Qualidata')));
        expect(d.nome, isNot(contains('20990XXX0001')));
      }
    });

    test('Componente Curricular, CH, T. Faltas, NS + F, EF, MF/M Final e situacao', () {
      final ds = lerBoletim(boletim);
      final apl = por(ds, 'Administração da Produção e Logística');
      expect(apl.pauta, '900102');
      expect(apl.carga, 30);
      expect(apl.faltas, 6); // T. Faltas
      expect(apl.media, '72,00'); // MF
      expect(apl.situacao, 'Cursando');
      expect(apl.etapas, [
        {'rotulo': 'Nota do semestre', 'nota': '72,00', 'faltas': 4.0}
      ]);
      // MF vazio: usa "M Final"
      expect(por(ds, 'Redes de Computadores').media, '55');
      // sem nota nenhuma: media vazia, mas a falta do NS aparece
      final ali = por(ds, 'Álgebra Linear');
      expect(ali.media, '');
      expect(ali.pauta, '900101');
      expect(ali.etapas.single['faltas'], 4.0);
      expect(ali.etapas.single['nota'], '');
      // "Exame Final" sem nota e sem falta nao vira etapa vazia
      expect(ds.expand((d) => d.etapas).where((e) => e['rotulo'] == 'Exame final'), isEmpty);
    });
  });

  group('diarios do IFES', () {
    test('frequencia, faltas, aulas previstas, minimo e professor na disciplina certa', () {
      final ds = lerBoletim(boletim);
      final r = lerDiarios(diarios, ds);
      expect(r.disciplinas, 4);
      final redes = por(ds, 'Redes de Computadores');
      expect(redes.aulas, 60);
      expect(redes.faltas, 14);
      expect(redes.minima, 75);
      expect(redes.frequencia, 72); // presenca com base nas aulas ministradas (referencia do historico)
      expect(redes.professor, 'Professor Exemplo Tres');
      // diario com turma diferente do boletim ("BSI.5A"): casa pelo COD_PAUTA
      final ali = por(ds, 'Álgebra Linear');
      expect(ali.faltas, 4);
      expect(ali.aulas, 60);
      expect(ali.professor, 'Professora Exemplo Dois');
    });

    test('avaliacoes: Nota Maxima nao vira nota, data com hora, nota vazia mantida', () {
      final ds = lerBoletim(boletim);
      final r = lerDiarios(diarios, ds);
      expect(r.avaliacoes, 5);
      final apl = por(ds, 'Administração da Produção e Logística');
      expect(apl.avaliacoes.first,
          {'descricao': 'Atividades Semanais', 'nota': '60', 'max': '100', 'peso': '30', 'data': '16/09/2026', 'etapa': 'Nota do semestre'});
      final mkt = por(ds, 'Marketing').avaliacoes;
      expect(mkt.map((a) => a['descricao']),
          ['Lista de exercícios PARTE 1 ATÉ 07/10/26', 'AV1', 'TRABALHO FINAL – FERRAMENTAS DIGITAIS']);
      expect(mkt[0]['data'], '30/09/2026');
      expect(mkt[1]['nota'], '0');
      expect(mkt[2]['nota'], ''); // ainda sem nota, mas aparece
      expect(mkt[2]['max'], '35');
      // nenhuma avaliacao vai para disciplina errada
      expect(por(ds, 'Redes de Computadores').avaliacoes, isEmpty);
      expect(por(ds, 'Álgebra Linear').avaliacoes, isEmpty);
    });

    test('limite de faltas e dias que ainda pode faltar com os dados do diario', () {
      final ds = lerBoletim(boletim);
      lerDiarios(diarios, ds);
      final h = lerHorario(horario, ds);
      final redes = por(ds, 'Redes de Computadores');
      final f = frequencia(redes, aulasPorDia: aulasPorDia(redes.nome, h));
      expect(f.limite, 18); // 60 horas = 72 aulas de 50 minutos
      expect(f.restantes, 4);
      expect(f.aulasPorDia, 2);
      expect(f.diasRestantes, 2);
      expect(f.emRisco, isFalse);
    });

    test('pagina sem diarios conta como nao lida', () {
      final ds = lerBoletim(boletim);
      expect(lerDiarios('<html><body><table><tr><td>nada</td></tr></table></body></html>', ds).vazia, isTrue);
    });
  });

  group('horario do IFES', () {
    test('2a-FEIRA, intervalos com ~, nome pelo title e blocos seguidos juntos', () {
      final ds = lerBoletim(boletim);
      final h = lerHorario(horario, ds);
      final seg = aulasDoDia(h, 1);
      expect(seg, hasLength(1));
      expect(seg.single.disciplina, 'Redes de Computadores');
      expect(seg.single.inicio, '07:30');
      expect(seg.single.fim, '09:09');
      expect(seg.single.aulas, 2);
      expect(seg.single.detalhe, 'BL09 903T · BSI.5 - G 1');
      expect(aulasDoDia(h, 2).single.disciplina, 'Álgebra Linear');
      final qua = aulasDoDia(h, 3);
      expect(qua.map((a) => a.disciplina), ['Redes de Computadores', 'Administração da Produção e Logística']);
      expect(qua.last.aulas, 1);
      expect(aulasDoDia(h, 4), isEmpty);
    });

    test('sigla sem title usa a legenda', () {
      final h = lerHorario(horario, lerBoletim(boletim));
      final sex = aulasDoDia(h, 5).single;
      expect(sex.disciplina, 'Marketing');
      expect(sex.aulas, 2);
    });
  });

  group('importacao', () {
    test('avisa quando diario ou horario nao foram lidos', () {
      final ok = resultadoImportacao(4, const LeituraDiarios(4, 5), 6);
      expect(ok.parcial, isFalse);
      expect(ok.mensagem, startsWith('Q-Acadêmico atualizado: 4 disciplina(s)'));

      final semHorario = resultadoImportacao(4, const LeituraDiarios(4, 0), 0);
      expect(semHorario.parcial, isTrue);
      expect(semHorario.mensagem, contains('Importação parcial'));
      expect(semHorario.mensagem, contains('o horário'));
      expect(semHorario.mensagem, isNot(contains('diários')));

      final semNada = resultadoImportacao(4, null, 0);
      expect(semNada.parcial, isTrue);
      expect(semNada.mensagem, contains('os diários (frequência e avaliações) nem o horário'));

      // diario lido sem nenhuma avaliacao lancada ainda nao e falha
      expect(resultadoImportacao(4, const LeituraDiarios(4, 0), 6).parcial, isFalse);
    });

    group('senha', () {
      setUp(() async {
        SharedPreferences.setMockInitialValues({});
        FlutterSecureStorage.setMockInitialValues({});
        await Cfg.init();
      });
      const ok = ResultadoQA(SituacaoQA.ok, 'ok');
      const falhou = ResultadoQA(SituacaoQA.falhou, 'erro');

      test('so salva depois de importar com sucesso', () async {
        await guardarCredenciaisQA(falhou, login: 'mat', senha: 's3nha', lembrar: true);
        expect(Cfg.qaLogin, '');
        expect(await Cfg.qaSenha(), isNull);
        await guardarCredenciaisQA(ok, login: 'mat', senha: 's3nha', lembrar: true);
        expect(Cfg.qaLogin, 'mat');
        expect(await Cfg.qaSenha(), 's3nha');
      });

      test('sem marcar "lembrar" a senha nao fica (e a antiga e apagada)', () async {
        await guardarCredenciaisQA(ok, login: 'mat', senha: 's3nha', lembrar: true);
        await guardarCredenciaisQA(ok, login: 'mat', senha: 's3nha', lembrar: false);
        expect(await Cfg.qaSenha(), isNull);
        expect(Cfg.qaLogin, 'mat');
      });
    });
  });

  group('tela', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Cfg.init();
    });

    testWidgets('nome longo e media estranha nao viram uma letra por linha', (t) async {
      const nome = 'Administração da Produção e Logística Aplicada a Sistemas de Informação';
      app.academico = [
        Disciplina(
            nome: nome,
            carga: 60,
            aulas: 60,
            faltas: 14,
            media: '14/11/2026 20990XXX0001 - Aluno Exemplo da Silva © 2004 Qualidata',
            situacao: 'Cursando'),
      ];
      app.horario = [];
      app.academicoEm = 1;
      await t.binding.setSurfaceSize(const Size(360, 800));
      await t.pumpWidget(const MaterialApp(home: Scaffold(body: DesempenhoAba())));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      final titulo = t.getSize(find.text(nome));
      expect(titulo.width, greaterThan(150)); // espaco de verdade para o nome
      expect(titulo.height, lessThan(60)); // no maximo 2 linhas
      await t.binding.setSurfaceSize(null);
    });
  });
}
