// Social v4: notificações por grupo, @all, turma de ingresso, ordem e arquivos.
import 'package:ava_sync_mobile/salvar.dart';
import 'package:ava_sync_mobile/social/formatacao.dart';
import 'package:ava_sync_mobile/social/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('@todos, @all e @everyone marcam todo mundo', () {
    expect(ehTodos('todos'), isTrue);
    expect(ehTodos('ALL'), isTrue);
    expect(ehTodos('everyone'), isTrue);
    expect(ehTodos('allan'), isFalse);
    expect(trocarMencoes('oi @all', (_) => null), 'oi @todos');
  });

  test('notificação do grupo: vem do servidor ou do "silenciado" antigo', () {
    expect(NotificarGrupo.de('mentions'), NotificarGrupo.mencoes);
    expect(NotificarGrupo.de('none'), NotificarGrupo.nada);
    expect(NotificarGrupo.de(null), NotificarGrupo.tudo);
    expect(NotificarGrupo.de(null, muted: true), NotificarGrupo.mencoes);
    final c = SocialConversation.fromJson({
      'id': 'g',
      'title': 'G',
      'created_at': '2026-11-16T10:00:00Z',
      'notify': 'mentions',
      'muted': true,
      'suppress_everyone': true,
      'channels': [
        {'id': 'c1', 'name': 'geral', 'last_read_at': '2026-11-16T09:00:00Z', 'category_id': 'k1'},
      ],
    });
    expect(c.notify, NotificarGrupo.mencoes);
    expect(c.suppressEveryone, isTrue);
    expect(c.suppressRoles, isFalse);
    expect(c.channels.single.lastReadAt, DateTime.parse('2026-11-16T09:00:00Z').toLocal());
    final tudo = c.copyWith(notify: NotificarGrupo.tudo);
    expect(tudo.muted, isFalse);
    // abrir o canal zera o contador sem tirar o canal da categoria
    final ch = c.channels.single.copyWith(unread: 0, mentions: 0);
    expect(ch.categoryId, 'k1');
  });

  test('turma de ingresso no perfil', () {
    final p = SocialProfile.fromJson({'user_key': 'h:1', 'username': 'x', 'display_name': 'Aluno Exemplo', 'cohort': '2024/2'});
    expect(p.cohort, '2024/2');
    expect(SocialProfile.fromJson({'user_key': 'h:2'}).cohort, isNull);
  });

  test('nome livre ao salvar arquivo repetido', () {
    final existentes = {'/d/foto.png', '/d/foto (2).png'};
    String sep(String s) => s.replaceAll('/', RegExp(r'\\').hasMatch(r'\') ? '/' : '/');
    final r = nomeLivre('/d', 'foto.png', (c) => existentes.contains(c.replaceAll('\\', '/')));
    expect(sep(r).replaceAll('\\', '/'), '/d/foto (3).png');
    expect(nomeLivre('/d', 'novo.pdf', (c) => false).replaceAll('\\', '/'), '/d/novo.pdf');
    expect(nomeLivre('/d', 'semext', (c) => c.replaceAll('\\', '/') == '/d/semext').replaceAll('\\', '/'), '/d/semext (2)');
  });
}
