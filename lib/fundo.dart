import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'armazenamento.dart';
import 'config.dart';
import 'sync.dart';
import 'util.dart';

/// Notificacoes e sincronizacao em segundo plano.
/// O segundo plano so LE o Moodle: nunca envia atividade.
class Notif {
  static final p = FlutterLocalNotificationsPlugin();
  static bool _ok = false;

  static Future<void> init() async {
    if (_ok) return;
    await p.initialize(
        settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_ava')));
    _ok = true;
  }

  static Future<void> pedirPermissao() async {
    await p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> mostrar(int id, String titulo, String corpo) async {
    await init();
    await p.show(
      id: id,
      title: titulo,
      body: corpo,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('ava', 'AVA',
            channelDescription: 'Novidades e prazos do AVA',
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(corpo)),
      ),
    );
  }
}

/// Depois de uma sincronizacao: notifica novidades e prazos proximos.
Future<void> avisar(ResultadoSync r) async {
  if (Cfg.notificacoes && r.novidades.isNotEmpty) {
    final linhas = r.novidades.take(6).map((n) => '• ${n['texto']}').join('\n');
    final extra = r.novidades.length > 6 ? '\n+${r.novidades.length - 6} outras' : '';
    await Notif.mostrar(1, '${r.novidades.length} novidade(s) no AVA', '$linhas$extra');
  }
  if (Cfg.lembretePrazo) {
    final estado = await Store.estado();
    final lembrados = mapa(estado['lembrados']);
    final agora = agoraSeg();
    final hoje = fmtData(agora, hora: false);
    var id = 100;
    for (final c in lista(r.snapshot['cursos']).map(mapa)) {
      final man = Cfg.atualManual['${c['id']}'];
      if (!(man is bool ? man : c['atual'] != false)) continue; // semestre anterior: sem lembrete
      for (final t in lista(c['tarefas']).map(mapa)) {
        final e = (t['entrega'] as num?)?.toInt() ?? 0;
        if (e <= agora || e - agora > 24 * 3600) continue;
        if (t['situacao'] == 'submitted') continue;
        final chave = 't${t['id']}';
        if (lembrados[chave] == hoje) continue;
        lembrados[chave] = hoje;
        await Notif.mostrar(id++, 'Prazo ${fmtRelativo(e)}: ${t['nome']}',
            '${c['nome']}\nSituação: ${situacoes[t['situacao']] ?? t['situacao']}');
      }
    }
    estado['lembrados'] = lembrados;
    await Store.salvarEstado(estado);
  }
}

const tarefaSync = 'ava-sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await Cfg.init();
      if (!Cfg.autoSync || (await Cfg.token()) == null) return true;
      final r = await Sync.rodar();
      await avisar(r);
      return true;
    } catch (_) {
      return false; // o Android tenta de novo mais tarde
    }
  });
}

Future<void> agendar() async {
  final wm = Workmanager();
  if (!Cfg.autoSync) {
    await wm.cancelByUniqueName(tarefaSync);
    return;
  }
  await wm.registerPeriodicTask(
    tarefaSync,
    tarefaSync,
    frequency: Duration(hours: Cfg.intervaloHoras),
    initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: Cfg.soWifi ? NetworkType.unmetered : NetworkType.connected),
  );
}
