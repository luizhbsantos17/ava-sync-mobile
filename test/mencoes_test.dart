// Issue #7: menção mostra o nome (não o @ifes_...) e chama mais atenção.
import 'package:ava_sync_mobile/social/formatacao.dart';
import 'package:ava_sync_mobile/social/notificacoes.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final nomes = {'ifes_3f2a1b_1234': 'Mikame', 'monitor': 'Monitor'};
  String? nome(String u) => nomes[u];

  test('notificação e prévia trocam @usuário pelo nome que aparece no chat', () {
    expect(trocarMencoes('oi @ifes_3f2a1b_1234, vem ver', nome), 'oi @Mikame, vem ver');
    expect(trocarMencoes('@everyone reunião', nome), '@todos reunião');
    expect(trocarMencoes('chama o @monitor', nome), 'chama o @Monitor');
    expect(trocarMencoes('@desconhecido fica igual', nome), '@desconhecido fica igual');
  });

  test('marca você: @você, @todos e @cargo seu', () {
    expect(marcaVoce(['ava:1'], eu: 'ava:1'), isTrue);
    expect(marcaVoce(['everyone'], eu: 'ava:1'), isTrue);
    expect(marcaVoce(['role:r1'], eu: 'ava:1', meusCargos: ['r1']), isTrue);
    expect(marcaVoce(['role:r2', 'ava:2'], eu: 'ava:1', meusCargos: ['r1']), isFalse);
    expect(marcaVoce(['ava:1'], eu: ''), isFalse); // ainda não sabe quem é você
    // "ignorar @todos" e "ignorar @cargos" do grupo: só a menção direta conta
    expect(marcaVoce(['everyone'], eu: 'ava:1', ignorarTodos: true), isFalse);
    expect(marcaVoce(['role:r1'], eu: 'ava:1', meusCargos: ['r1'], ignorarCargos: true), isFalse);
    expect(marcaVoce(['ava:1', 'everyone'], eu: 'ava:1', ignorarTodos: true), isTrue);
  });

  test('notificação com menção fica destacada', () {
    final n = acumular({}, [
      (conversa: 'g', canal: 'c', titulo: 'Turma · #geral', direta: false, linha: const LinhaNotif('Ana', 'oi', 1)),
      (conversa: 'g', canal: 'c', titulo: 'Turma · #geral', direta: false, linha: const LinhaNotif('Bia', '@Mikame olha', 2, mencao: true)),
    ])['g:c']!;
    expect(n.temMencao, isTrue);
    expect(corpoSimples(n), 'Ana: oi\n📣 Bia: @Mikame olha');
    expect(ConversaNotif.fromJson(n.toJson()).temMencao, isTrue);
  });
}
