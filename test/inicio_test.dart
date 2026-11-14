// Tela inicial: troca "Semestre atual/Todas" na hora e paineis clicaveis.
import 'dart:io';

import 'package:ava_sync_mobile/armazenamento.dart';
import 'package:ava_sync_mobile/config.dart';
import 'package:ava_sync_mobile/estado_app.dart';
import 'package:ava_sync_mobile/telas/inicio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({'site': 'https://m.ex'});
    await Cfg.init();
    tmp = Directory.systemTemp.createTempSync('avasync_ini_');
    Store.baseTeste = tmp;
    final daqui3dias = DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3 * 86400;
    app.snap = {
      'gerado_em': 1,
      'cursos': [
        {
          'id': 1, 'nome': 'Desenvolvimento Web I', 'atual': true, 'secoes': [], 'provas': [], 'avisos': [], 'eventos': [],
          'tarefas': [
            {'id': 7, 'nome': 'Sprint 2 do SIGMA', 'entrega': daqui3dias, 'situacao': 'new', 'html': '', 'anexos': []}
          ],
        },
        {'id': 2, 'nome': 'Sociologia (2026/1)', 'atual': false, 'secoes': [], 'tarefas': [], 'provas': [], 'avisos': [], 'eventos': []},
      ],
    };
    app.estado = {};
    app.logado = true;
    app.carregando = false;
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  testWidgets('Semestre atual / Todas troca na hora', (t) async {
    await t.pumpWidget(const MaterialApp(home: InicioTela()));
    await t.tap(find.text('Matérias').last);
    await t.pumpAndSettle();
    expect(find.text('Desenvolvimento Web I'), findsOneWidget);
    expect(find.text('Sociologia (2026/1)'), findsNothing);
    await t.tap(find.text('Todas'));
    await t.pumpAndSettle();
    expect(find.text('Sociologia (2026/1)'), findsOneWidget); // sem precisar trocar de aba
    await t.tap(find.text('Semestre atual'));
    await t.pumpAndSettle();
    expect(find.text('Sociologia (2026/1)'), findsNothing);
  });

  testWidgets('paineis da tela inicial navegam', (t) async {
    await t.pumpWidget(const MaterialApp(home: InicioTela()));
    await t.pump();
    await t.tap(find.text('Nesta semana'));
    await t.pumpAndSettle();
    expect(find.text('Sprint 2 do SIGMA'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Tarefas abertas'));
    await t.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Tarefas abertas'), findsOneWidget);
    await t.pageBack();
    await t.pumpAndSettle();
    await t.tap(find.text('Matérias').first); // o painel, nao a barra de baixo
    await t.pumpAndSettle();
    expect(find.text('Semestre atual'), findsOneWidget); // abriu a aba Matérias
  });
}
