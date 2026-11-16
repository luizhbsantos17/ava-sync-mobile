// App de computador: layout largo, segundo plano, atualização e "abrir com o sistema".
import 'dart:io';

import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:ava_sync_mobile/atualizacao.dart';
import 'package:ava_sync_mobile/compromissos.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/desktop/iniciar_com_sistema.dart';
import 'package:ava_sync_mobile/desktop/segundo_plano.dart';
import 'package:ava_sync_mobile/estado_app.dart';
import 'package:ava_sync_mobile/telas/inicio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('arquivo da atualização por plataforma', () {
    test('oficial', () {
      expect(Atualizacao.nomeDoArquivo(beta: false, plataforma: 'Android'), 'AVA-Sync.apk');
      expect(Atualizacao.nomeDoArquivo(beta: false, plataforma: 'Windows'), 'AVA-Sync-Windows.exe');
      expect(Atualizacao.nomeDoArquivo(beta: false, plataforma: 'Linux'), 'AVA-Sync-Linux.tar.gz');
      expect(Atualizacao.nomeDoArquivo(beta: false, plataforma: 'macOS'), 'AVA-Sync-macOS.zip');
    });
    test('beta', () {
      expect(Atualizacao.nomeDoArquivo(beta: true, plataforma: 'Android'), 'AVA-Sync-Beta.apk');
      expect(Atualizacao.nomeDoArquivo(beta: true, plataforma: 'Windows'), 'AVA-Sync-Beta-Windows.exe');
    });
  });

  group('segundo plano no computador', () {
    test('lembrete dispara uma vez, na janela certa', () {
      const l = [Lembrete(100, 'a', ''), Lembrete(200, 'b', ''), Lembrete(300, 'c', '')];
      expect(SegundoPlanoDesktop.vencidos(l, 100, 250).map((e) => e.titulo), ['b']);
      expect(SegundoPlanoDesktop.vencidos(l, 250, 300).map((e) => e.titulo), ['c']);
      expect(SegundoPlanoDesktop.vencidos(l, 300, 900), isEmpty);
    });
    test('sincroniza só quando passou o intervalo', () {
      expect(SegundoPlanoDesktop.deveSincronizar(agora: 10000, ultima: 9000, intervaloHoras: 1), isFalse);
      expect(SegundoPlanoDesktop.deveSincronizar(agora: 12600, ultima: 9000, intervaloHoras: 1), isTrue);
      expect(SegundoPlanoDesktop.deveSincronizar(agora: 10000, ultima: 0, intervaloHoras: 12), isFalse);
      expect(SegundoPlanoDesktop.deveSincronizar(agora: 50000, ultima: 0, intervaloHoras: 12), isTrue);
    });
  });

  group('abrir com o sistema', () {
    test('Linux: .desktop com o argumento de começar escondido', () {
      final t = IniciarComSistema.conteudoDesktop('AVA Sync', '/opt/ava/ava_sync_mobile', ['--oculto']);
      expect(t, contains('Exec="/opt/ava/ava_sync_mobile" --oculto'));
      expect(t, contains('Name=AVA Sync'));
    });
    test('macOS: plist com RunAtLoad e caminho escapado', () {
      final t = IniciarComSistema.conteudoPlist('io.github.avasync.avasync', '/Apps/A & B.app/x', ['--oculto']);
      expect(t, contains('<string>/Apps/A &amp; B.app/x</string>'));
      expect(t, contains('<string>--oculto</string>'));
      expect(t, contains('<key>RunAtLoad</key>'));
    });
  });

  group('tela larga', () {
    late Directory tmp;
    setUp(() async {
      SharedPreferences.setMockInitialValues({'site': 'https://m.ex'});
      await Cfg.init();
      tmp = Directory.systemTemp.createTempSync('avasync_desk_');
      Store.baseTeste = tmp;
      app.snap = {'gerado_em': 1, 'cursos': []};
      app.estado = {};
      app.logado = true;
      app.carregando = false;
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    testWidgets('menu lateral no lugar das abas de baixo', (t) async {
      t.view.physicalSize = const Size(1400, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: InicioTela()));
      await t.pump();
      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.text('Social'), findsOneWidget); // o Social vira uma seção da janela
      await t.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text('Matérias')));
      await t.pumpAndSettle();
      expect(find.text('Semestre atual'), findsOneWidget);
    });

    testWidgets('janela estreita continua igual ao celular', (t) async {
      t.view.physicalSize = const Size(420, 860);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(const MaterialApp(home: InicioTela()));
      await t.pump();
      expect(find.byType(NavigationBar), findsOneWidget);
      expect(find.byType(NavigationRail), findsNothing);
    });
  });
}
