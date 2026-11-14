// Novidades de tarefa, lembretes agendados, eventos da agenda e download da atualizacao.
import 'dart:async';
import 'dart:io';

import 'package:ava_sync_mobile/atualizacao.dart';
import 'package:ava_sync_mobile/calendario.dart';
import 'package:ava_sync_mobile/compromissos.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

const agora = 1800000000;

Map<String, dynamic> tarefa({String situacao = 'new', int? entrega, int corte = 0, String? nota}) => {
      'id': 7,
      'nome': 'Relatório',
      'entrega': entrega ?? agora + 5 * 86400,
      'corte': corte,
      'situacao': situacao,
      'nota': nota,
    };

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    await Cfg.init();
  });

  group('mudancasTarefa', () {
    test('entrega registrada e nota publicada avisam uma vez', () {
      final vistos = <String, dynamic>{};
      mudancasTarefa(tarefa(), vistos, agora);
      final r = mudancasTarefa(tarefa(situacao: 'submitted', nota: '9,0'), vistos, agora);
      expect(r.map((e) => e['tipo']), containsAll(['entrega', 'nota']));
      expect(mudancasTarefa(tarefa(situacao: 'submitted', nota: '9,0'), vistos, agora), isEmpty);
    });

    test('prazo alterado', () {
      final vistos = <String, dynamic>{};
      mudancasTarefa(tarefa(), vistos, agora);
      final r = mudancasTarefa(tarefa(entrega: agora + 9 * 86400), vistos, agora);
      expect(r.single['texto'], startsWith('Prazo alterado: Relatório'));
    });

    test('venceu sem entrega, com e sem prazo de corte', () {
      final v1 = <String, dynamic>{};
      final r1 = mudancasTarefa(tarefa(entrega: agora - 3600), v1, agora);
      expect(r1.single['texto'], 'Prazo encerrado sem entrega: Relatório');
      final r2 = mudancasTarefa(tarefa(entrega: agora - 3600, corte: agora + 86400), <String, dynamic>{}, agora);
      expect(r2.single['texto'], contains('ainda aceita até'));
    });

    test('silencioso so registra (sem encher de aviso depois de atualizar o app)', () {
      final vistos = <String, dynamic>{};
      expect(mudancasTarefa(tarefa(situacao: 'submitted', nota: '8'), vistos, agora, silencioso: true), isEmpty);
      expect(mudancasTarefa(tarefa(situacao: 'submitted', nota: '8'), vistos, agora), isEmpty);
    });
  });

  group('lembretes', () {
    Map<String, dynamic> snap() => {
          'cursos': [
            {
              'id': 1,
              'nome': 'Redes',
              'atual': true,
              'tarefas': [
                {'id': 1, 'nome': 'Lista 1', 'entrega': agora + 4 * 86400, 'situacao': 'new'},
                {'id': 2, 'nome': 'Lista 2', 'entrega': agora + 4 * 86400, 'situacao': 'submitted'},
              ],
              'provas': [
                {'id': 3, 'nome': 'Questionário 1', 'fecha': agora + 2 * 3600},
              ],
              'eventos': [],
            },
            {
              'id': 2,
              'nome': 'Antiga',
              'atual': false,
              'tarefas': [
                {'id': 9, 'nome': 'Velha', 'entrega': agora + 86400 * 2, 'situacao': 'new'}
              ],
            },
          ],
        };

    test('3 dias, 1 dia e 3 h antes; ignora entregue, passado e semestre antigo', () {
      final l = lembretes(compromissos(snap(), const {}), agora);
      // Lista 1: 3 lembretes; Questionario 1 fecha em 2 h: todos ja passaram
      expect(l, hasLength(3));
      expect(l.first.titulo, startsWith('Entrega em 3 dias: Lista 1'));
      expect(l.map((e) => e.quando), [agora + 86400, agora + 3 * 86400, agora + 4 * 86400 - 3 * 3600]);
      expect(l.last.corpo, contains('ainda não entregue'));
    });

    test('materia marcada manualmente como atual entra', () {
      final l = lembretes(compromissos(snap(), const {'2': true}), agora);
      expect(l.any((e) => e.titulo.contains('Velha')), isTrue);
    });
  });

  group('agenda', () {
    test('prazo vira bloco de 30 min terminando na entrega', () {
      const c = Compromisso(chave: 'tarefa:1', tipo: 'tarefa', cat: 'atividade', nome: 'Lista', curso: 'Redes', ts: agora);
      final e = eventoDe(c);
      expect(e.titulo, 'Entrega: Lista');
      expect(e.fim, agora);
      expect(e.inicio, agora - 1800);
      expect(e.descricao, contains('não entregue'));
    });

    test('entregue muda o titulo (e a assinatura)', () {
      const a = Compromisso(chave: 'tarefa:1', tipo: 'tarefa', cat: 'atividade', nome: 'Lista', curso: 'Redes', ts: agora);
      const b = Compromisso(
          chave: 'tarefa:1', tipo: 'tarefa', cat: 'atividade', nome: 'Lista', curso: 'Redes', ts: agora, entregue: true);
      expect(eventoDe(b).titulo, startsWith('✓ '));
      expect(eventoDe(a).assinatura, isNot(eventoDe(b).assinatura));
    });

    test('prova do cronograma (so data) vira dia inteiro', () {
      final meiaNoite = DateTime(2027, 3, 10).millisecondsSinceEpoch ~/ 1000;
      final c = Compromisso(chave: 'evento:p1', tipo: 'evento', cat: 'prova', nome: 'N1', curso: 'Redes', ts: meiaNoite);
      expect(eventoDe(c).diaTodo, isTrue);
      expect(eventoDe(c).titulo, 'Prova: N1');
    });

    test('filtro: so provas e nada muito antigo', () {
      final l = [
        const Compromisso(chave: 'a', tipo: 'tarefa', cat: 'atividade', nome: 'x', curso: '', ts: agora + 10),
        const Compromisso(chave: 'b', tipo: 'quiz', cat: 'prova', nome: 'y', curso: '', ts: agora + 10),
        const Compromisso(chave: 'c', tipo: 'quiz', cat: 'prova', nome: 'z', curso: '', ts: agora - 3 * 86400),
      ];
      expect(paraAgenda(l, agora).map((c) => c.chave), ['a', 'b']);
      expect(paraAgenda(l, agora, soProvas: true).map((c) => c.chave), ['b']);
    });
  });

  group('download da atualizacao', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('avasync_apk_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    final apk = List<int>.filled(2 * 1024 * 1024, 7);

    test('baixa inteiro, informa progresso e termina sem esperar o servidor fechar', () async {
      final fim = Completer<void>();
      final cliente = MockClient.streaming((req, _) async {
        final ctrl = StreamController<List<int>>();
        ctrl.add(apk.sublist(0, 1024 * 1024));
        ctrl.add(apk.sublist(1024 * 1024));
        fim.future.then((_) => ctrl.close()); // servidor nunca fecha durante o teste
        return http.StreamedResponse(ctrl.stream, 200, contentLength: apk.length);
      });
      final progresso = <int>[];
      final f = await DownloadApk.baixar('https://x/AVA-Sync.apk', tmp,
          cliente: cliente, progresso: (r, _) => progresso.add(r));
      fim.complete();
      expect(await f.length(), apk.length);
      expect(f.path, endsWith('AVA-Sync.apk'));
      expect(progresso.last, apk.length);
    });

    test('para de receber dados: da erro em vez de ficar travado', () async {
      final cliente = MockClient.streaming((req, _) async {
        final ctrl = StreamController<List<int>>();
        ctrl.add(apk.sublist(0, 1024));
        return http.StreamedResponse(ctrl.stream, 200, contentLength: apk.length);
      });
      await expectLater(
          DownloadApk.baixar('https://x/a.apk', tmp, cliente: cliente, ocioso: const Duration(milliseconds: 200)),
          throwsA(isA<Exception>()));
      expect(tmp.listSync(), isEmpty); // nao deixa .part para tras
    });

    test('incompleto e recusado', () async {
      final cliente = MockClient.streaming((req, _) async =>
          http.StreamedResponse(Stream.value(apk.sublist(0, 1024 * 1024 + 5)), 200, contentLength: apk.length));
      await expectLater(DownloadApk.baixar('https://x/a.apk', tmp, cliente: cliente), throwsA(isA<Exception>()));
      expect(File('${tmp.path}/AVA-Sync.apk').existsSync(), isFalse);
    });
  });

  test('"Depois" silencia so aquele build ate o prazo', () async {
    const info = AtualizacaoInfo(build: 9, buildInstalado: 5, apkUrl: 'u', releaseUrl: 'r');
    expect(Atualizacao.devePerguntar(info, agora), isTrue);
    await Cfg.adiarAtualizacao(9, agora + 100);
    expect(Atualizacao.devePerguntar(info, agora), isFalse);
    expect(Atualizacao.devePerguntar(info, agora + 101), isTrue);
    const nova = AtualizacaoInfo(build: 10, buildInstalado: 5, apkUrl: 'u', releaseUrl: 'r');
    expect(Atualizacao.devePerguntar(nova, agora), isTrue);
  });
}
