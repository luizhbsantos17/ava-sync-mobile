// Notificações do Social: uma por conversa, com quem mandou, acumulando até ler.
import 'package:ava_sync_mobile/social/escuta.dart';
import 'package:ava_sync_mobile/social/notificacoes.dart';
import 'package:flutter_test/flutter_test.dart';

MensagemNova msg(String conv, String canal, String nome, String texto, int quando, {bool dm = false}) =>
    (conversa: conv, canal: canal, titulo: dm ? nome : 'Turma · #geral', direta: dm, linha: LinhaNotif(nome, texto, quando));

void main() {
  test('mensagens seguidas acumulam na mesma notificação, separadas por conversa', () {
    var m = acumular({}, [msg('g1', 'c1', 'Ana', 'oi', 1), msg('g1', 'c1', 'Bia', 'tudo bem?', 2)]);
    m = acumular(m, [msg('g1', 'c1', 'Ana', 'bora estudar', 3), msg('dm1', 'd1', 'Caio', 'e aí', 4, dm: true)]);
    expect(m.length, 2);
    final g = m['g1:c1']!;
    expect(g.total, 3);
    expect(g.linhas.map((l) => '${l.nome}: ${l.texto}'), ['Ana: oi', 'Bia: tudo bem?', 'Ana: bora estudar']);
    expect(corpoSimples(g), 'Ana: oi\nBia: tudo bem?\nAna: bora estudar');
    // mensagem direta: sem repetir o nome em cada linha
    expect(corpoSimples(m['dm1:d1']!), 'e aí');
  });

  test('guarda só as últimas linhas, mas conta todas', () {
    var m = <String, ConversaNotif>{};
    for (var i = 1; i <= 10; i++) {
      m = acumular(m, [msg('g', 'c', 'Ana', 'm$i', i)], maxLinhas: 4);
    }
    final n = m['g:c']!;
    expect(n.total, 10);
    expect(n.linhas.map((l) => l.texto), ['m7', 'm8', 'm9', 'm10']);
    expect(corpoSimples(n).split('\n').first, '+6 mensagens antes');
  });

  test('sobrevive a salvar e ler (JSON)', () {
    final n = acumular({}, [msg('g', 'c', 'Ana', 'oi', 5)])['g:c']!;
    final de = ConversaNotif.fromJson(n.toJson());
    expect(de.titulo, n.titulo);
    expect(de.linhas.single.texto, 'oi');
    expect(de.payload, 'social:g:c');
  });

  test('sem internet, espera cada vez mais (até 60 s)', () {
    expect(EscutaSocial.espera(0), Duration.zero);
    expect(EscutaSocial.espera(1), const Duration(seconds: 2));
    expect(EscutaSocial.espera(3), const Duration(seconds: 8));
    expect(EscutaSocial.espera(20), const Duration(seconds: 60));
  });
}
