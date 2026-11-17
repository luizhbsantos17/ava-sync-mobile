// Canais de voz (issue #3): modelos e chave de mídia.
import 'package:ava_sync_mobile/social/models.dart';
import 'package:ava_sync_mobile/social/voz.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('canal de voz com quem está na chamada', () {
    final c = SocialConversation.fromJson({
      'id': 'g',
      'title': 'G',
      'created_at': '2026-11-16T10:00:00Z',
      'channels': [
        {'id': 'v', 'name': 'Sala', 'position': 0, 'kind': 'voice', 'user_limit': 5, 'voice': [
          {'user_key': 'h:1', 'muted': true, 'screen': true},
          {'user_key': 'h:2'},
        ]},
        {'id': 't', 'name': 'geral', 'position': 1, 'kind': 'text'},
      ],
    });
    final voz = c.channels.first;
    expect(voz.voz, isTrue);
    expect(voz.userLimit, 5);
    expect(voz.naVoz.map((p) => p.userKey), ['h:1', 'h:2']);
    expect(voz.naVoz.first.muted, isTrue);
    expect(voz.naVoz.first.screen, isTrue);
    // a conversa de texto padrão nunca é o canal de voz
    expect(c.primeiroCanal!.id, 't');
    // copiar o canal mantém o tipo
    expect(voz.copyWith(unread: 0).voz, isTrue);
  });

  test('chave de mídia: igual para quem tem a chave do grupo, diferente por canal', () async {
    final k = List<int>.generate(32, (i) => i);
    final a = await VozController.chaveMidia('canal-1', k);
    expect(await VozController.chaveMidia('canal-1', k), a);
    expect(await VozController.chaveMidia('canal-2', k), isNot(a));
    expect(await VozController.chaveMidia('canal-1', List<int>.filled(32, 9)), isNot(a));
  });
}
