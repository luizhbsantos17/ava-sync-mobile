import 'dart:async';

import '../atualizacao.dart';
import '../compromissos.dart';
import '../config.dart';
import '../estado_app.dart';
import '../fundo.dart';
import '../social/escuta.dart';
import '../util.dart';

/// Segundo plano no computador. No Android o sistema (workmanager) acorda o app;
/// no computador o app continua aberto na bandeja e estes relógios fazem o mesmo trabalho:
/// sincronizar o AVA, manter a escuta do Social ligada, disparar lembretes e procurar atualização.
class SegundoPlanoDesktop {
  static Timer? _relogio;
  static List<Lembrete> _lembretes = const [];
  static int _ultimoMinuto = 0;
  static int _ultimaVerificacaoApp = 0;
  static const intervaloAtualizacao = 6 * 3600;

  /// Liga (ou confirma) os relógios. Pode ser chamado várias vezes.
  static void iniciar() {
    _ultimoMinuto = agoraSeg();
    _relogio ??= Timer.periodic(const Duration(seconds: 30), (_) => unawaited(_tique()));
  }

  static void parar() {
    _relogio?.cancel();
    _relogio = null;
  }

  /// Troca os lembretes pendentes (chamado depois de cada sincronização).
  static void definirLembretes(List<Lembrete> lista) {
    _lembretes = List.of(lista)..sort((a, b) => a.quando.compareTo(b.quando));
  }

  /// Lembretes que venceram entre [desde] (exclusivo) e [ate] (inclusivo). Puro, testável.
  static List<Lembrete> vencidos(List<Lembrete> lista, int desde, int ate) =>
      lista.where((l) => l.quando > desde && l.quando <= ate).toList();

  /// Hora de sincronizar o AVA? Puro, testável.
  static bool deveSincronizar({required int agora, required int ultima, required int intervaloHoras}) =>
      agora - ultima >= intervaloHoras * 3600;

  static Future<void> _tique() async {
    final agora = agoraSeg();

    // lembretes de prazo (3 dias, 1 dia e 3 h antes)
    for (final l in vencidos(_lembretes, _ultimoMinuto, agora)) {
      try {
        await Notif.mostrar(1000 + l.quando % 4000, l.titulo, l.corpo);
      } catch (_) {}
    }
    _ultimoMinuto = agora;

    if (!app.logado) return;

    // Social: a escuta em tempo real cuida das mensagens (aqui só garante que está ligada)
    if (Cfg.socialUsado && !EscutaSocial.ligada) EscutaSocial.ligar();

    // AVA (mesmo intervalo escolhido em Ajustes)
    final ultima = (app.snap['gerado_em'] as num?)?.toInt() ?? 0;
    if (Cfg.autoSync &&
        !app.sincronizando &&
        deveSincronizar(agora: agora, ultima: ultima, intervaloHoras: Cfg.intervaloHoras)) {
      await app.sincronizar();
    }

    // versão nova do app
    if (Cfg.verificarAtualizacoes && agora - _ultimaVerificacaoApp >= intervaloAtualizacao) {
      _ultimaVerificacaoApp = agora;
      if (Atualizacao.buildInstalado > 0) {
        try {
          await avisarAtualizacao();
        } catch (_) {}
      }
    }
  }
}
