import 'package:material_ui/material_ui.dart';
import 'package:workmanager/workmanager.dart';

import 'config.dart';
import 'estado_app.dart';
import 'fundo.dart';
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

class AvaSyncApp extends StatelessWidget {
  const AvaSyncApp({super.key});

  ThemeData _tema(Brightness b) => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B7F6B), brightness: b),
        useMaterial3: true,
        cardTheme: const CardThemeData(elevation: 0.5),
      );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AVA Sync',
      debugShowCheckedModeBanner: false,
      theme: _tema(Brightness.light),
      darkTheme: _tema(Brightness.dark),
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
