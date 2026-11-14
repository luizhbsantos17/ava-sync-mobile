// Social (grupos) e filtro de materias por ID: partes que nao dependem do servidor.
import 'dart:convert';

import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/social/supabase_crypto.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('convite do grupo', () {
    final chave = base64Url.encode(List<int>.filled(32, 7)).replaceAll('=', '');

    test('ida e volta preserva grupo, segredo e chave', () {
      final codigo = SupabaseSocialCrypto.makeInvite(conversationId: 'g1', token: 'segredo', conversationKey: chave);
      expect(codigo, startsWith('AVASYNC1.'));
      final c = SupabaseSocialCrypto.parseInvite('  $codigo\n');
      expect(c.conversationId, 'g1');
      expect(c.token, 'segredo');
      expect(c.conversationKey, chave);
    });

    test('recusa codigo estranho ou chave de tamanho errado', () {
      expect(() => SupabaseSocialCrypto.parseInvite('oi'), throwsFormatException);
      final curta = base64Url.encode(List<int>.filled(16, 1)).replaceAll('=', '');
      final codigo = SupabaseSocialCrypto.makeInvite(conversationId: 'g1', token: 's', conversationKey: curta);
      expect(() => SupabaseSocialCrypto.parseInvite(codigo), throwsFormatException);
    });
  });

  group('filtro de materias por ID', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await Cfg.init();
    });
    final c = [
      {'id': 1, 'fullname': 'Redes', 'enddate': 0},
      {'id': 2, 'fullname': 'Marketing', 'enddate': 0},
      {'id': 3, 'fullname': 'Biblioteca', 'enddate': 0},
    ];
    List<dynamic> nomes(List<Map<String, dynamic>> r) => r.map((x) => x['fullname']).toList();

    test('ignorar por ID', () {
      expect(nomes(Sync.filtrarCursos(c, 100, ignorar: [], somente: [], ignorarIds: {'3'}, somenteIds: {})),
          ['Redes', 'Marketing']);
    });

    test('somente as escolhidas, inclusive com o modo ligado e nenhuma escolhida', () async {
      expect(nomes(Sync.filtrarCursos(c, 100, ignorar: [], somente: [], ignorarIds: {}, somenteIds: {'2'})), ['Marketing']);
      await Cfg.setSomenteCursosIdsAtivo(true);
      expect(Sync.filtrarCursos(c, 100, ignorar: [], somente: [], ignorarIds: {}, somenteIds: {}), isEmpty);
    });
  });

  test('notas do release beta seguem o formato que o app le', () {
    final notas = 'Build: 12\nCommit: abc1234\n\nVersão de testes.';
    expect(RegExp(r'Build:\s*(\d+)', caseSensitive: false).firstMatch(notas)?.group(1), '12');
  });
}
