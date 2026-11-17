// Gravação dos JSON do app (snapshot, estado): várias ao mesmo tempo não se atropelam.
import 'dart:io';

import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('ava_store_');
    Store.baseTeste = dir;
  });
  tearDown(() async {
    Store.baseTeste = null;
    await dir.delete(recursive: true);
  });

  test('gravações simultâneas do mesmo arquivo: a última vence, sem erro', () async {
    await Future.wait([
      for (var i = 0; i < 20; i++) Store.gravarJson('estado.json', {'n': i, 'lista': List.generate(100, (k) => k)}),
    ]);
    final lido = await Store.lerJson('estado.json');
    expect(lido['n'], 19);
    expect(File('${dir.path}/estado.json.tmp').existsSync(), isFalse);
  });

  test('JSON grande é lido e gravado igual (passa por outro isolate)', () async {
    final grande = {for (var i = 0; i < 3000; i++) 'chave$i': {'texto': 'valor $i' * 5, 'n': i}};
    await Store.gravarJson('snapshot.json', grande);
    final lido = await Store.lerJson('snapshot.json');
    expect(lido.length, 3000);
    expect((lido['chave2999'] as Map)['n'], 2999);
  });
}
