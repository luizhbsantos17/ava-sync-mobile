import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'atualizacao.dart';
import 'calendario.dart';
import 'compromissos.dart';
import 'config.dart';
import 'sync.dart';
import 'util.dart';

/// Notificacoes e sincronizacao em segundo plano.
/// O segundo plano so LE o Moodle: nunca envia atividade.
const payloadAtualizar = 'atualizar';

class Notif {
  static final p = FlutterLocalNotificationsPlugin();
  static bool _ok = false;

  /// Chamado quando a pessoa toca numa notificacao com o app aberto (ou ao abrir por ela).
  static void Function(String? payload)? aoTocar;

  static Future<void> init() async {
    if (_ok) return;
    await p.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('ic_stat_ava')),
      onDidReceiveNotificationResponse: (r) => aoTocar?.call(r.payload),
    );
    _ok = true;
  }

  /// Payload da notificacao que abriu o app (se foi assim que ele abriu).
  static Future<String?> payloadDeAbertura() async {
    await init();
    final d = await p.getNotificationAppLaunchDetails();
    return d?.didNotificationLaunchApp == true ? d?.notificationResponse?.payload : null;
  }

  static Future<void> pedirPermissao() async {
    await p
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static NotificationDetails _detalhes(String corpo, {String canal = 'ava'}) => NotificationDetails(
        android: canal == 'prazos'
            ? AndroidNotificationDetails('prazos', 'Prazos',
                channelDescription: 'Lembretes antes de entregas, questionários e provas',
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(corpo))
            : AndroidNotificationDetails('ava', 'AVA',
                channelDescription: 'Novidades e prazos do AVA',
                importance: Importance.high,
                priority: Priority.high,
                styleInformation: BigTextStyleInformation(corpo)),
      );

  static Future<void> mostrar(int id, String titulo, String corpo, {String? payload}) async {
    await init();
    await p.show(id: id, title: titulo, body: corpo, notificationDetails: _detalhes(corpo), payload: payload);
  }

  static const _idLembrete = 1000;
  static const _maxLembretes = 400;

  /// Troca todos os lembretes agendados pelos de [lista] (o Android dispara mesmo com o
  /// app fechado, sem precisar de sincronizacao naquele momento).
  static Future<void> agendarLembretes(List<Lembrete> lista) async {
    await init();
    for (final pend in await p.pendingNotificationRequests()) {
      if (pend.id >= _idLembrete && pend.id < _idLembrete + _maxLembretes) await p.cancel(id: pend.id);
    }
    var id = _idLembrete;
    for (final l in lista.take(_maxLembretes)) {
      await p.zonedSchedule(
        id: id++,
        title: l.titulo,
        body: l.corpo,
        scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, l.quando * 1000),
        notificationDetails: _detalhes(l.corpo, canal: 'prazos'),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// Depois de uma sincronizacao: notifica novidades, reagenda lembretes de prazo e
/// atualiza o calendario do celular (se ligado).
Future<void> avisar(ResultadoSync r) async {
  if (Cfg.notificacoes && r.novidades.isNotEmpty) {
    final linhas = r.novidades.take(6).map((n) => '• ${n['texto']}').join('\n');
    final extra = r.novidades.length > 6 ? '\n+${r.novidades.length - 6} outras' : '';
    await Notif.mostrar(1, '${r.novidades.length} novidade(s) no AVA', '$linhas$extra');
  }
  final lista = compromissos(r.snapshot, Cfg.atualManual);
  try {
    await Notif.agendarLembretes(Cfg.lembretePrazo ? lembretes(lista, agoraSeg()) : const []);
  } catch (_) {}
  if (Cfg.calendario) {
    try {
      await Calendario.sincronizar(lista);
    } catch (_) {}
  }
}

/// Avisa (uma vez por versao) que ha atualizacao do app.
Future<void> avisarAtualizacao() async {
  final info = await Atualizacao.verificarAuto();
  if (info == null || Cfg.updNotificado >= info.build) return;
  await Cfg.setUpdNotificado(info.build);
  await Notif.mostrar(2, 'Atualização do AVA Sync disponível',
      'Versão ${info.build} pronta. Toque para atualizar sem desinstalar.', payload: payloadAtualizar);
}

const tarefaSync = 'ava-sync';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await Cfg.init();
      if (!Cfg.autoSync || (await Cfg.token()) == null) {
        await avisarAtualizacao();
        return true;
      }
      final r = await Sync.rodar();
      await avisar(r);
      await avisarAtualizacao();
      return true;
    } catch (_) {
      return false; // o Android tenta de novo mais tarde
    }
  });
}

Future<void> agendar() async {
  final wm = Workmanager();
  // a mesma tarefa periodica sincroniza (se ligado) e procura atualizacao do app
  if (!Cfg.autoSync && !Cfg.verificarAtualizacoes) {
    await wm.cancelByUniqueName(tarefaSync);
    return;
  }
  await wm.registerPeriodicTask(
    tarefaSync,
    tarefaSync,
    frequency: Duration(hours: Cfg.autoSync ? Cfg.intervaloHoras : 12),
    initialDelay: const Duration(minutes: 30),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    constraints: Constraints(networkType: Cfg.soWifi ? NetworkType.unmetered : NetworkType.connected),
  );
}
