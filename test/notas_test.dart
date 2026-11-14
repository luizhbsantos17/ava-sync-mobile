// Notas de versao: do CHANGELOG para a release e da release para a janela de atualizacao.
import 'dart:io';

import 'package:ava_sync_mobile/atualizacao.dart';
import 'package:ava_sync_mobile/telas/atualizar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = 'Build: 11\nVersão: 0.7.0\nCommit: abc1234\n\n### Adicionado\n- **Grupos** novos\n  com convite\n### Corrigido\n- Sync';

  test('separa o cabecalho das notas', () {
    expect(notasDaRelease(body), startsWith('### Adicionado'));
    expect(notasDaRelease('Build: 3\nCommit: x'), '');
    expect(notasDaRelease(body.replaceAll('\n', '\r\n')), startsWith('### Adicionado'));
  });

  test('markdown simples vira linhas legiveis', () {
    final l = linhasDasNotas(notasDaRelease(body));
    expect(l.map((e) => e.texto), ['Adicionado', '• Grupos novos com convite', 'Corrigido', '• Sync']);
    expect(l.first.titulo, isTrue);
    expect(l[1].item, isTrue);
  });

  test('a versao do pubspec tem notas no CHANGELOG', () {
    final versao = RegExp(r'^version:\s*([^+\s]+)', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync())!
        .group(1)!;
    final linhas = File('CHANGELOG.md').readAsLinesSync();
    final ini = linhas.indexWhere((l) => l.startsWith('## [$versao]'));
    expect(ini, greaterThanOrEqualTo(0), reason: 'Adicione "## [$versao]" ao CHANGELOG.md');
    final resto = linhas.skip(ini + 1).takeWhile((l) => !l.startsWith('## ['));
    expect(resto.where((l) => l.trim().isNotEmpty), isNotEmpty);
  });
}
