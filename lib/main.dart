import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'atualizacao.dart';
import 'config.dart';
import 'estado_app.dart';
import 'fundo.dart';
import 'util.dart';
import 'telas/atualizar.dart';
import 'telas/inicio.dart';
import 'telas/login.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Cfg.init();
  try {
    await Notif.init();
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {}
  runApp(const AvaSyncApp());
  await app.carregar();
  Notif.aoTocar = (payload) {
    if (payload == payloadAtualizar) unawaited(procurarAtualizacao(forcar: true));
  };
  String? abriuPor;
  try {
    abriuPor = await Notif.payloadDeAbertura();
  } catch (_) {}
  unawaited(procurarAtualizacao(forcar: abriuPor == payloadAtualizar));
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

  ThemeData _tema(Brightness b) {
    const violet = Color(0xFFB49AFF);
    const background = Color(0xFF100D17);
    const surface = Color(0xFF1A1622);
    final scheme = ColorScheme.fromSeed(seedColor: violet, brightness: b).copyWith(
      primary: b == Brightness.dark ? violet : const Color(0xFF6845C4),
      surface: b == Brightness.dark ? background : const Color(0xFFF8F6FC),
      error: const Color(0xFFFF8A98),
    );
    return ThemeData(
      colorScheme: scheme,
      brightness: b,
      scaffoldBackgroundColor: b == Brightness.dark ? background : const Color(0xFFF8F6FC),
      useMaterial3: true,
      appBarTheme: AppBarTheme(
        backgroundColor: b == Brightness.dark ? background : const Color(0xFFF8F6FC),
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: b == Brightness.dark ? surface : Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: b == Brightness.dark ? const Color(0xFF17131F) : Colors.white,
        indicatorColor: b == Brightness.dark ? const Color(0xFF3C2C58) : const Color(0xFFECE5FA),
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll(TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: b == Brightness.dark ? const Color(0xFF201A2A) : const Color(0xFFF0EDF5),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      listTileTheme: ListTileThemeData(iconColor: scheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.4), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navegador,
      title: 'AVA Sync',
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
      themeMode: ThemeMode.dark,
      home: ListenableBuilder(
        listenable: app,
        builder: (context, _) {
          if (app.carregando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
          return app.logado ? const InicioTela() : const LoginTela();
        },
      ),
    );
  }
}
