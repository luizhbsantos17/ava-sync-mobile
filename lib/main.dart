import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'atualizacao.dart';
import 'config.dart';
import 'estado_app.dart';
import 'fundo.dart';
import 'tema.dart';
import 'util.dart';
import 'telas/atualizar.dart';
import 'telas/inicio.dart';
import 'telas/login.dart';
import 'telas/social.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cfg.init();
  temaAtual.value = Tema.deTexto(Cfg.temaJson);
  try {
    await Notif.init();
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {}
  runApp(const AvaSyncApp());
  await app.carregar();
  Notif.aoTocar = (payload) {
    if (payload == payloadAtualizar) unawaited(procurarAtualizacao(forcar: true));
    if (payload != null && payload.startsWith('social:')) unawaited(_abrirSocial(payload));
  };
  String? abriuPor;
  try {
    abriuPor = await Notif.payloadDeAbertura();
  } catch (_) {}
  unawaited(procurarAtualizacao(forcar: abriuPor == payloadAtualizar));
  if (abriuPor != null && abriuPor.startsWith('social:')) unawaited(_abrirSocial(abriuPor));
  if (app.logado) {
    await agendar();
    if (!Cfg.permissaoPedida) {
      await Cfg.setPermissaoPedida(true);
      await Notif.pedirPermissao();
    }
    // abre com os dados salvos e atualiza se a ultima sincronizacao tem mais de 1 h
    final ult = (app.snap['gerado_em'] as num?)?.toInt() ?? 0;
    if (DateTime.now().millisecondsSinceEpoch ~/ 1000 - ult > 3600) app.sincronizar();
  }
}

final navegador = GlobalKey<NavigatorState>();

/// Toque numa notificação do Social: abre a conversa.
Future<void> _abrirSocial(String payload) async {
  for (var i = 0; i < 20 && (navegador.currentState == null || app.carregando); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (!app.logado) return;
  await navegador.currentState?.push(SocialTela.rota(abrir: payload));
}

/// Procura versao nova e, se houver, pergunta se quer atualizar.
/// [forcar]: pergunta mesmo que a pessoa tenha tocado em "Depois" antes.
Future<void> procurarAtualizacao({bool forcar = false}) async {
  final info = await Atualizacao.verificarAuto();
  if (info == null || (!forcar && !Atualizacao.devePerguntar(info, agoraSeg()))) return;
  // espera a tela inicial ficar pronta
  for (var i = 0; i < 20 && (navegador.currentContext == null || app.carregando); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final ctx = navegador.currentContext;
  if (ctx == null || !ctx.mounted) return;
  await oferecerAtualizacao(ctx, info, automatico: !forcar);
}

class AvaSyncApp extends StatelessWidget {
  const AvaSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Tema>(
      valueListenable: temaAtual,
      builder: (context, tema, _) => MaterialApp(
        navigatorKey: navegador,
        title: 'AVA Sync',
        debugShowCheckedModeBanner: false,
        theme: tema.construir(Brightness.light),
        darkTheme: tema.construir(Brightness.dark),
        themeMode: tema.themeMode,
        builder: (context, filho) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(tema.fonte)),
          child: filho!,
        ),
        home: ListenableBuilder(
          listenable: app,
          builder: (context, _) {
            if (app.carregando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            return app.logado ? const InicioTela() : const LoginTela();
          },
        ),
      ),
    );
  }
}
