// Social v3: cargos (hierarquia, permissões, @menção) e notificações de eventos.
import 'package:ava_sync_mobile/social/models.dart';
import 'package:ava_sync_mobile/social/notificacoes.dart';
import 'package:ava_sync_mobile/telas/social/chat.dart';
import 'package:flutter_test/flutter_test.dart';

SocialGroupInfo grupo({String myRole = 'member', List<String> myPerms = const []}) => SocialGroupInfo.fromJson({
      'conversation': {'id': 'g1', 'title': 'Turma', 'group_kind': 'friends', 'created_at': '2026-11-16T00:00:00Z'},
      'myRole': myRole,
      'muted': false,
      'channels': [],
      'myRank': 5,
      'myPerms': myPerms,
      'roles': [
        {'id': 'r1', 'name': 'Monitor', 'color': 0xFF2ECC71, 'position': 5, 'permissions': ['fixar'], 'mentionable': true},
        {'id': 'r2', 'name': 'Calouro', 'color': null, 'position': 2, 'permissions': [], 'mentionable': false},
      ],
      'members': [
        {'user_key': 'a', 'role': 'owner', 'roles': []},
        {'user_key': 'b', 'role': 'member', 'roles': ['r2', 'r1']},
        {'user_key': 'c', 'role': 'member', 'roles': ['r2']},
      ],
    });

void main() {
  test('hierarquia: dono > admin > cargo mais alto', () {
    final g = grupo();
    expect(g.roles.map((r) => r.name), ['Monitor', 'Calouro']); // do mais alto para o mais baixo
    expect(g.rankDe(g.member('a')!), greaterThan(g.rankDe(g.member('b')!)));
    expect(g.rankDe(g.member('b')!), 5);
    expect(g.rankDe(g.member('c')!), 2);
  });

  test('cor do nome vem do cargo mais alto que tem cor', () {
    final g = grupo();
    expect(g.corDe(g.member('b')!), 0xFF2ECC71);
    expect(g.corDe(g.member('c')!), isNull);
  });

  test('permissões: dono pode tudo; membro só o que os cargos dão', () {
    expect(grupo(myRole: 'owner').pode(Permissao.gerenciarCargos), isTrue);
    final m = grupo(myPerms: ['fixar']);
    expect(m.pode(Permissao.fixar), isTrue);
    expect(m.pode(Permissao.banir), isFalse);
  });

  test('@ do cargo: minúsculas, sem acento, _ no lugar de espaço', () {
    expect(apelidoCargo('Monitor de Cálculo'), 'monitor_de_calculo');
    expect(apelidoCargo('  Representante!! '), 'representante');
    expect(apelidoCargo('🎉'), 'cargo');
  });

  test('textos das notificações de eventos (#1)', () {
    expect(textoDoEvento('amizade_pedido', {'nome': 'Ana'})!.corpo, 'Ana quer ser seu amigo no Social.');
    expect(textoDoEvento('removido', {'titulo': 'Turma', 'por': 'Bia'})!.titulo, 'Você saiu de Turma');
    expect(textoDoEvento('cargo', {'titulo': 'Turma', 'cargo': 'Monitor', 'ganhou': true})!.corpo, 'Você agora é Monitor.');
    expect(textoDoEvento('desconhecido', {}), isNull);
  });
}
