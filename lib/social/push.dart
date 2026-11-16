import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../fundo.dart';
import '../util.dart';
import 'api.dart';
import 'notificacoes.dart';

/// Push do Social no Android (Firebase Cloud Messaging).
///
/// O servidor manda só um aviso "tem mensagem nova" para o celular; o Android acorda o app
/// (PushService.kt), que roda [aoReceberPush]: busca as mensagens cifradas, decifra aqui
/// no aparelho e mostra a notificação com quem mandou e o texto. O Google não vê nada disso.
class PushSocial {
  static const canal = MethodChannel('avasync/push');

  /// Registra (ou renova, a cada 7 dias) o token deste celular no servidor do Social.
  static Future<void> registrar() async {
    if (!Platform.isAndroid || !SocialApi.configured) return;
    try {
      final token = await canal.invokeMethod<String>('token');
      if (token == null || token.isEmpty) return; // build sem Firebase
      final agora = agoraSeg();
      if (token == Cfg.pushToken && agora - Cfg.pushRegistradoEm < 7 * 86400) return;
      await SocialApi().call('push_register', {'token': token});
      await Cfg.setPushToken(token, agora);
    } catch (_) {
      // sem internet ou servidor antigo: tenta de novo na próxima vez que o app abrir
    }
  }

  /// Ao sair da conta: este celular deixa de receber avisos.
  static Future<void> esquecer() async {
    final token = Cfg.pushToken;
    if (token.isEmpty) return;
    try {
      await SocialApi().call('push_unregister', {'token': token});
    } catch (_) {}
    await Cfg.setPushToken('', 0);
  }
}

/// Roda num Flutter sem tela quando chega um push com o app fechado (PushService.kt).
@pragma('vm:entry-point')
Future<void> aoReceberPush() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    await Cfg.init();
    await Notif.init();
    await verificarSocial();
  } catch (_) {
    // sem internet: o segundo plano (~15 min) ou a próxima abertura do app mostram depois
  } finally {
    try {
      await PushSocial.canal.invokeMethod<void>('pronto');
    } catch (_) {}
  }
}
