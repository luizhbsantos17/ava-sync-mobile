// Social v2: formatação, modelos e criptografia (mensagens, arquivos, envelopes).
import 'package:ava_sync_mobile/social/formatacao.dart';
import 'package:ava_sync_mobile/social/models.dart';
import 'package:ava_sync_mobile/social/supabase_crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  group('formatação', () {
    String marcas(String t) => formatar(t).map((x) => x.toString()).join(' / ');

    test('negrito, itálico, riscado e código', () {
      expect(marcas('oi **forte** e *leve*'), 'oi  / forte|b /  e  / leve|i');
      expect(marcas('~~não~~ `x = 1`'), 'não|s /   / x = 1|code');
    });

    test('sublinhado dentro de palavra não vira itálico', () {
      expect(formatar('arquivo_final_v2.pdf').single.italico, isFalse);
      expect(formatar('_sim_').single.italico, isTrue);
    });

    test('bloco de código não é formatado por dentro', () {
      final t = formatar('antes\n```dart\nvar **a** = 1;\n```\ndepois');
      final bloco = t.firstWhere((x) => x.bloco);
      expect(bloco.texto, 'var **a** = 1;');
    });

    test('links e menções', () {
      final t = formatar('veja https://ava.ifes.edu.br/x, @ana_b e email@x.com');
      expect(t.where((x) => x.link != null).single.link, 'https://ava.ifes.edu.br/x');
      expect(t.where((x) => x.mencao != null).map((x) => x.mencao), ['ana_b']);
    });

    test('spoiler e citação', () {
      expect(formatar('||segredo||').single.spoiler, isTrue);
      expect(formatar('> citado').single.citacao, isTrue);
    });

    test('mensagem só de emoji', () {
      expect(soEmojis('😂'), isTrue);
      expect(soEmojis('👍🏽 ❤️'), isTrue);
      expect(soEmojis('oi 😂'), isFalse);
      expect(soEmojis('123'), isFalse);
      expect(soEmojis('😂😂😂😂'), isFalse);
    });
  });

  group('modelos', () {
    test('conversa com canais, não lidas e menções', () {
      final c = SocialConversation.fromJson({
        'id': 'c1',
        'title': 'Turma',
        'group_kind': 'friends',
        'role': 'admin',
        'member_count': 4,
        'created_at': '2026-11-14T10:00:00Z',
        'channels': [
          {'id': 'b', 'name': 'dúvidas', 'position': 1, 'unread': 2, 'mentions': 1},
          {'id': 'a', 'name': 'geral', 'position': 0, 'unread': 3, 'mentions': 0},
        ],
      });
      expect(c.channels.map((x) => x.name), ['geral', 'dúvidas']);
      expect(c.unread, 5);
      expect(c.mentions, 1);
      expect(c.role.gerencia, isTrue);
      expect(c.direta, isFalse);
    });

    test('mensagem direta usa o nome da outra pessoa', () {
      final c = SocialConversation.fromJson({
        'id': 'd1',
        'title': 'Mensagem direta',
        'group_kind': 'dm',
        'created_at': '2026-11-14T10:00:00Z',
        'peer': {'user_key': 'h:2', 'username': 'aluno.exemplo', 'display_name': 'Aluno Exemplo', 'presence': 'busy'},
      });
      expect(c.nome, 'Aluno Exemplo');
      expect(c.peer!.presence, Presenca.busy);
    });

    test('reações agrupadas por emoji', () {
      final r = SocialMessage.reactionsFrom([
        {'emoji': '👍', 'user_key': 'a'},
        {'emoji': '👍', 'user_key': 'b'},
        {'emoji': '😂', 'user_key': 'a'},
      ]);
      expect(r.map((x) => '${x.emoji}${x.users.length}'), ['👍2', '😂1']);
    });
  });

  group('criptografia', () {
    final chave = List<int>.generate(32, (i) => i);

    test('mensagem v2 com anexo volta igual e amarra o canal', () async {
      SupabaseSocialCrypto.setKeyForTest('conv', chave);
      const anexo = SocialAttachment(path: 'att/conv/u/1.bin', name: 'foto.png', mime: 'image/png', size: 10, width: 4, height: 3);
      final box = await SupabaseSocialCrypto.encryptMessage(conversationId: 'conv', channelId: 'ch1', senderId: 'eu', text: 'olá **mundo**', attachments: [anexo]);
      final row = {...box, 'conversation_id': 'conv', 'channel_id': 'ch1', 'sender_id': 'eu'};
      final c = await SupabaseSocialCrypto.decryptRow(row);
      expect(c.texto, 'olá **mundo**');
      expect(c.anexos.single.path, anexo.path);
      expect(c.anexos.single.width, 4);
      // mover a mensagem para outro canal ou trocar o autor invalida
      await expectLater(SupabaseSocialCrypto.decryptRow({...row, 'channel_id': 'ch2'}), throwsA(anything));
      await expectLater(SupabaseSocialCrypto.decryptRow({...row, 'sender_id': 'outro'}), throwsA(anything));
    });

    test('mensagens antigas (formato 1) continuam abrindo', () async {
      SupabaseSocialCrypto.setKeyForTest('conv', chave);
      final box = await SupabaseSocialCrypto.encrypt('conv', 'eu', 'mensagem antiga');
      final c = await SupabaseSocialCrypto.decryptRow({...box, 'conversation_id': 'conv', 'channel_id': 'x', 'sender_id': 'eu', 'format': 1});
      expect(c.texto, 'mensagem antiga');
    });

    test('arquivo cifrado ida e volta', () async {
      SupabaseSocialCrypto.setKeyForTest('conv', chave);
      final dados = List<int>.generate(1000, (i) => i % 251);
      final sealed = await SupabaseSocialCrypto.encryptFile('conv', 'att/conv/a', dados);
      expect(sealed.length, dados.length + 28);
      expect(await SupabaseSocialCrypto.decryptFile('conv', 'att/conv/a', sealed), dados);
      await expectLater(SupabaseSocialCrypto.decryptFile('conv', 'att/conv/b', sealed), throwsA(anything));
    });

    test('envelope entrega a chave para outro aparelho', () async {
      // aparelho A tem a chave e embrulha para a chave pública de B
      final pubB = await _publicaDe(List.filled(32, 5));
      final pubA = await _publicaDe(List.filled(32, 9));
      expect(pubA, isNot(pubB));
      SupabaseSocialCrypto.setKeyForTest('g', chave);
      final e = (await SupabaseSocialCrypto.sealFor(conversationId: 'g', userKey: 'b', recipientPublic: pubB))!;
      expect(e['senderPublic'], pubA);

      // aparelho B abre
      FlutterSecureStorage.setMockInitialValues({'social_device_seed': SupabaseSocialCrypto.b64(List.filled(32, 5))});
      SupabaseSocialCrypto.resetDeviceForTest();
      SupabaseSocialCrypto.setKeyForTest('g', null);
      final ok = await SupabaseSocialCrypto.openEnvelope({
        'conversation_id': 'g',
        'sender_public': e['senderPublic'],
        'sealed': e['sealed'],
        'nonce': e['nonce'],
        'mac': e['mac'],
      });
      expect(ok, isTrue);
      expect(await SupabaseSocialCrypto.groupKey('g'), chave);
    });

    test('chave nova não apaga a antiga: mensagens das duas continuam abrindo', () async {
      final k1 = List<int>.filled(32, 1), k2 = List<int>.filled(32, 2);
      await SupabaseSocialCrypto.removeGroupKey('m');
      await SupabaseSocialCrypto.saveGroupKey('m', k1);
      final antiga = await SupabaseSocialCrypto.encrypt('m', 'eu', 'com a chave 1');
      await SupabaseSocialCrypto.saveGroupKey('m', k2); // entrou de novo por outro convite
      final nova = await SupabaseSocialCrypto.encrypt('m', 'eu', 'com a chave 2');
      expect(await SupabaseSocialCrypto.groupKey('m'), k2);
      for (final (box, texto) in [(antiga, 'com a chave 1'), (nova, 'com a chave 2')]) {
        final c = await SupabaseSocialCrypto.decryptRow({...box, 'conversation_id': 'm', 'channel_id': 'x', 'sender_id': 'eu'});
        expect(c.texto, texto);
      }
      // envelope com outra chave só acrescenta, não troca a atual
      await SupabaseSocialCrypto.saveGroupKey('m', List<int>.filled(32, 3), atual: false);
      expect(await SupabaseSocialCrypto.groupKey('m'), k2);
      expect((await SupabaseSocialCrypto.groupKeys('m')).length, 3);
    });

    test('convite colado com texto em volta', () {
      final k = SupabaseSocialCrypto.b64(chave);
      final code = SupabaseSocialCrypto.makeInvite(conversationId: 'g1', token: 's', conversationKey: k);
      final c = SupabaseSocialCrypto.parseInvite('Entre no grupo:\n\n$code\n');
      expect(c.conversationId, 'g1');
    });
  });
}

Future<String> _publicaDe(List<int> seed) async {
  FlutterSecureStorage.setMockInitialValues({'social_device_seed': SupabaseSocialCrypto.b64(seed)});
  SupabaseSocialCrypto.resetDeviceForTest();
  final pub = await SupabaseSocialCrypto.devicePublicKey();
  return pub;
}
