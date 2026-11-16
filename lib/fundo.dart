import 'dart:ui';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'atualizacao.dart';
import 'calendario.dart';
import 'compromissos.dart';
import 'config.dart';
import 'desktop/segundo_plano.dart';
import 'plataforma.dart';
import 'social/notificacoes.dart';
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
      settings: InitializationSettings(
        android: const AndroidInitializationSettings('ic_stat_ava'),
        macOS: const DarwinInitializationSettings(
            requestAlertPermission: false, requestBadgePermission: false, requestSoundPermission: false),
        linux: const LinuxInitializationSettings(defaultActionName: 'Abrir'),
        windows: WindowsInitializationSettings(
            appName: Atualizacao.canal == 'beta' ? 'AVA Sync Teste' : 'AVA Sync',
            appUserModelId: Atualizacao.canal == 'beta' ? 'AvaSync.Desktop.Beta' : 'AvaSync.Desktop',
            guid: Atualizacao.canal == 'beta' ? '6f1d3b52-8c0e-4a8b-9d55-1b7e4f2c9a31' : '3c8e2a17-5d4b-4f0a-8e61-9a2b7c4d1e58'),
      ),
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
    await p
        .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
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

  /// Notificação de uma conversa do Social: cada mensagem com quem mandou, acumulando
  /// (no Android, no estilo de conversa do sistema, igual WhatsApp).
  static Future<void> mostrarConversa(ConversaNotif n) async {
    await init();
    final eu = const Person(name: 'Você');
    await p.show(
      id: 5000 + (n.id.abs() % 4000),
      title: n.titulo,
      body: corpoSimples(n),
      payload: n.payload,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails('social', 'Social',
            channelDescription: 'Mensagens dos grupos e conversas',
            importance: Importance.high,
            priority: Priority.high,
            groupKey: 'social',
            category: AndroidNotificationCategory.message,
            number: n.total,
            styleInformation: MessagingStyleInformation(
              eu,
              conversationTitle: n.direta ? null : n.titulo,
              groupConversation: !n.direta,
              messages: [
                for (final l in n.linhas)
                  Message(l.texto, DateTime.fromMillisecondsSinceEpoch(l.quando), Person(name: l.nome, key: l.nome)),
              ],
            )),
      ),
    );
  }

  static Future<void> cancelar(int idConversa) async {
    await init();
    await p.cancel(id: 5000 + (idConversa.abs() % 4000));
  }

  static const _idLembrete = 1000;
  static const _maxLembretes = 400;

  /// Troca todos os lembretes agendados pelos de [lista] (o Android dispara mesmo com o
  /// app fechado, sem precisar de sincronizacao naquele momento).
  static Future<void> agendarLembretes(List<Lembrete> lista) async {
    if (Plataforma.desktop) {
      // no computador o app fica aberto na bandeja e dispara os lembretes na hora
      SegundoPlanoDesktop.definirLembretes(lista);
      return;
    }
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
  if (Cfg.calendario && Plataforma.temAgenda) {
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
      'Versão ${info.build} pronta. ${Plataforma.desktop ? 'Clique' : 'Toque'} para atualizar sem desinstalar.',
      payload: payloadAtualizar);
}

const tarefaSync = 'ava-sync';
const tarefaSocial = 'ava-sync-social';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    try {
      await Cfg.init();
      if (task == tarefaSocial) {
        await verificarSocial();
        return true;
      }
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
  if (Plataforma.desktop) {
    SegundoPlanoDesktop.iniciar();
    return;
  }
  final wm = Workmanager();
  if (Cfg.socialUsado && Cfg.socialNotificacoes) {
    await wm.registerPeriodicTask(
      tarefaSocial,
      tarefaSocial,
      frequency: const Duration(minutes: 15),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      constraints: Constraints(networkType: NetworkType.connected),
    );
  } else {
    await wm.cancelByUniqueName(tarefaSocial);
  }
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
