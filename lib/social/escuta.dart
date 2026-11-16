import 'dart:async';

import 'package:flutter/widgets.dart';

import '../config.dart';
import '../plataforma.dart';
import 'api.dart';
import 'notificacoes.dart';

/// Escuta de mensagens novas em tempo real, para notificar na hora.
///
/// Fica sempre ligada no computador (o app mora na bandeja) e no celular enquanto o app
/// está aberto. Usa a ação `inbox` do servidor, que segura a chamada até chegar mensagem
/// (long polling): quando chega, a resposta volta em ~1 s e já pedimos a próxima.
/// Se o servidor ainda não tiver `inbox` (Edge Function antiga), cai para perguntar
/// `notifications` a cada [intervaloSemInbox].
class EscutaSocial {
  static int _geracao = 0;
  static bool _ligada = false;
  static SocialApi? _api;

  static const intervaloSemInbox = Duration(seconds: 5);

  static bool get ligada => _ligada;
  static AppLifecycleListener? _ciclo;

  /// Liga a escuta conforme a plataforma: no computador, sempre; no celular, só com o
  /// app na frente (fechado, quem avisa é o segundo plano do Android).
  static void iniciarNoApp() {
    ligar();
    if (Plataforma.celular) {
      _ciclo ??= AppLifecycleListener(onResume: ligar, onPause: desligar, onDetach: desligar);
    }
  }

  static void ligar() {
    if (_ligada) return;
    _ligada = true;
    unawaited(_rodar(++_geracao));
  }

  static void desligar() {
    _ligada = false;
    _geracao++;
  }

  /// Espera entre tentativas depois de [falhas] erros seguidos (puro, testável):
  /// 2 s, 4 s, 8 s... até 60 s, para não martelar o servidor sem internet.
  static Duration espera(int falhas) => Duration(seconds: falhas <= 0 ? 0 : (1 << falhas.clamp(1, 6)).clamp(2, 60));

  static Future<void> _rodar(int geracao) async {
    var temInbox = true;
    var falhas = 0;
    bool viva() => _ligada && geracao == _geracao;
    while (viva()) {
      if (!Cfg.socialUsado || !Cfg.socialNotificacoes || !SocialApi.configured || await Cfg.token() == null) {
        await Future<void>.delayed(const Duration(seconds: 30));
        continue;
      }
      final api = _api ??= SocialApi();
      final since = Cfg.socialUltimaNotif.isEmpty
          ? DateTime.now().toUtc().subtract(const Duration(minutes: 2)).toIso8601String()
          : Cfg.socialUltimaNotif;
      try {
        final r = temInbox
            ? await api.call('inbox', {'since': since}, const Duration(seconds: 45))
            : await api.call('notifications', {'since': since});
        if (!viva()) return;
        await NotifSocial.processar(Map<String, dynamic>.from(r as Map));
        falhas = 0;
        if (!temInbox) await Future<void>.delayed(intervaloSemInbox);
      } on SocialApiException catch (e) {
        if (temInbox && e.message.contains('desconhecida')) {
          temInbox = false; // servidor ainda sem tempo real
          continue;
        }
        falhas++;
        await Future<void>.delayed(espera(falhas));
      } catch (_) {
        falhas++;
        await Future<void>.delayed(espera(falhas));
      }
    }
  }
}
