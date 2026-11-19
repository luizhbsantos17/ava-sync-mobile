// Questionários obrigatórios do Q-Acadêmico (avaliação docente no fim do semestre).
import 'dart:io';

import 'package:ava_sync_mobile/qacademico.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final lista = File('test/fixtures/ifes_questionarios_lista.html').readAsStringSync();
  final form = File('test/fixtures/ifes_questionario_form.html').readAsStringSync();

  test('reconhece a página que bloqueia o sistema', () {
    expect(ehBloqueioQuestionarios(lista), isTrue);
    expect(ehBloqueioQuestionarios(File('test/fixtures/ifes_boletim.html').readAsStringSync()), isFalse);
  });

  test('lista os questionários, separando obrigatórios e resolvendo links relativos', () {
    final qs = lerQuestionariosPendentes(lista);
    expect(qs.length, 3);
    expect(qs[0].disciplina, 'Cálculo Exemplo');
    expect(qs[0].professor, 'Professor Exemplo Um');
    expect(qs[0].obrigatorio, isTrue);
    expect(qs[1].url, startsWith('https://academico.ifes.edu.br/qacademico/index.asp?t=1022'));
    expect(qs[1].url, contains('codAvaliado=900102'));
    expect(qs[2].obrigatorio, isFalse);
  });

  test('pontos pelo rótulo da opção', () {
    expect(pontosDoRotulo('dez pontos'), 10);
    expect(pontosDoRotulo('três pontos'), 3);
    expect(pontosDoRotulo('um ponto'), 1);
    expect(pontosDoRotulo('zero ponto'), 0);
    expect(pontosDoRotulo('7'), 7);
    expect(pontosDoRotulo('Concordo'), isNull);
  });

  test('lê o formulário e escolhe a opção da nota', () {
    final ps = lerFormularioQuestionario(form);
    expect(ps.map((p) => p.campo), ['P_101', 'P_102', 'P_103']);
    expect(ps[0].opcoes.length, 11);
    expect(ps[0].texto, contains('Plano de Ensino'));
    expect(ps[2].deTexto, isTrue);
    expect(escolherRespostas(ps, 8), {'P_101': '1008', 'P_102': '2008'});
    expect(escolherRespostas(ps, 0), {'P_101': '1000', 'P_102': '2000'});
  });

  test('página sem formulário: nenhuma pergunta', () {
    expect(lerFormularioQuestionario(lista), isEmpty);
  });
}
