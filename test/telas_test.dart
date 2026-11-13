// Abre as telas com dados simulados para pegar erros de layout e de execucao.
import 'dart:io';

import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/estado_app.dart';
import 'package:ava_sync_mobile/moodle.dart';
import 'package:ava_sync_mobile/sync.dart';
import 'package:ava_sync_mobile/telas/inicio.dart';
import 'package:ava_sync_mobile/telas/login.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_test.dart' as dados;

void main() {
  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'site': dados.site});
    await Cfg.init();
    tmp = Directory.systemTemp.createTempSync('avasync_ui_');
    Store.baseTeste = tmp;
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Widget envolver(Widget w) => MaterialApp(home: w);

  testWidgets('login abre', (t) async {
    await t.pumpWidget(envolver(const LoginTela()));
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.textContaining('não é salva'), findsOneWidget);
  });

  testWidgets('navega por todas as telas', (t) async {
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.75;
    addTearDown(t.view.reset);

    await t.runAsync(() async {
      final m = Moodle(dados.site, 'TOK', cliente: dados.clienteMoodle());
      final r = await Sync.rodar(moodle: m, externo: dados.clienteExterno(), baixarArquivos: true);
      app.snap = r.snapshot;
      app.estado = await Store.estado();
    });
    app.logado = true;
    app.carregando = false;

    await t.pumpWidget(envolver(const InicioTela()));
    await t.pump();
    expect(find.text('Relatório Lab'), findsOneWidget); // prazos
    expect(find.text('Prova 1'), findsOneWidget);

    await t.tap(find.text('Matérias').last);
    await t.pumpAndSettle();
    await t.tap(find.text('Redes de Computadores'));
    await t.pumpAndSettle();
    expect(find.text('Atividades'), findsOneWidget);

    for (final aba in ['Provas', 'Avisos', 'Conteúdo', 'Arquivos', 'Estudar']) {
      await t.ensureVisible(find.text(aba));
      await t.pumpAndSettle();
      await t.tap(find.text(aba));
      await t.pumpAndSettle();
    }
    expect(find.text('Guia da matéria (IA)'), findsOneWidget);

    await t.ensureVisible(find.text('Atividades'));
    await t.pumpAndSettle();
    await t.tap(find.text('Atividades'));
    await t.pumpAndSettle();
    await t.tap(find.text('Relatório Lab'));
    await t.pumpAndSettle();
    expect(find.text('Enunciado'), findsOneWidget);
    expect(find.text('Enviar atividade'), findsOneWidget);

    await t.tap(find.text('Enviar atividade'));
    await t.pumpAndSettle();
    expect(find.text('Digite ENVIAR para confirmar'), findsOneWidget);
    // sem arquivo e sem ENVIAR o botao fica desligado
    final botao = t.widget<FilledButton>(find.byWidgetPredicate((w) => w is FilledButton));
    expect(botao.onPressed, isNull);

    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();
    await t.pageBack();
    await t.pumpAndSettle();

    await t.tap(find.text('Novidades').last);
    await t.pumpAndSettle();
    expect(find.textContaining('Primeira sincronização'), findsOneWidget);

    await t.tap(find.text('Ajustes').last);
    await t.pumpAndSettle();
    expect(find.text('Sincronizar automaticamente'), findsOneWidget);
    await t.drag(find.byType(ListView).first, const Offset(0, -3000));
    await t.pumpAndSettle();

    // busca
    await t.tap(find.text('Prazos').last);
    await t.pumpAndSettle();
    await t.tap(find.byIcon(Icons.search));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'livro');
    await t.pumpAndSettle();
    expect(find.text('Livro de Redes'), findsOneWidget);
  });
}
