import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:tray_manager/tray_manager.dart' as bandeja;
import 'package:window_manager/window_manager.dart' as wm;

import '../atualizacao.dart';
import '../config.dart';
import '../estado_app.dart';
import 'iniciar_com_sistema.dart';
import 'segundo_plano.dart';

/// Janela, bandeja do sistema e "abrir com o sistema" no computador.
///
/// Fechar a janela só esconde (o app segue na bandeja sincronizando e avisando).
/// "Sair" no menu da bandeja encerra de verdade.
class JanelaDesktop {
  JanelaDesktop._();
  static final instancia = JanelaDesktop._();

  /// Argumento usado quando o sistema abre o app no login: começa escondido.
  static const argOculto = '--oculto';

  static String get nomeApp => Atualizacao.canal == 'beta' ? 'AVA Sync Teste' : 'AVA Sync';

  /// Porta local usada para garantir uma única cópia aberta (a segunda só pede para a
  /// primeira mostrar a janela e fecha). Beta usa outra porta para rodar junto.
  static int get _porta => Atualizacao.canal == 'beta' ? 47232 : 47231;
  static ServerSocket? _servidor;

  wm.Window? _janela;
  bandeja.TrayIcon? _icone; // precisa ficar guardado: se for coletado, o ícone some
  bool _saindo = false;

  /// Devolve false se já existe outra cópia aberta (e pede a ela para aparecer).
  static Future<bool> garantirUnica() async {
    try {
      _servidor = await ServerSocket.bind(InternetAddress.loopbackIPv4, _porta);
      _servidor!.listen((s) {
        s.listen((_) {}, onDone: s.destroy, onError: (_) => s.destroy());
        instancia.mostrar();
      });
      return true;
    } on SocketException {
      try {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, _porta, timeout: const Duration(seconds: 2));
        s.write('mostrar');
        await s.flush();
        await s.close();
        return false;
      } catch (_) {
        return true; // porta ocupada por outro programa: segue normalmente
      }
    }
  }

  Future<void> iniciar(List<String> args) async {
    final janela = _janela = wm.WindowManager.instance.getCurrent();
    if (janela != null) {
      janela.title = nomeApp;
      janela.minimumSize = const Size(420, 560).toNative();
      janela.setSize(const Size(1280, 820).toNative(), false);
      janela.center();
      janela.addListener((evento) {
        if (evento is wm.WindowCloseRequestedEvent && !_saindo && Cfg.fecharParaBandeja && _icone != null) {
          evento.request.cancel();
          janela.hide();
        }
      });
      if (!args.contains(argOculto)) {
        janela.show();
        janela.focus();
      }
    }
    _criarBandeja();
    await IniciarComSistema.aplicar(Cfg.iniciarComSistema, nome: nomeApp, argumentos: const [argOculto]);
    SegundoPlanoDesktop.iniciar();
  }

  void _criarBandeja() {
    try {
      final icone = bandeja.TrayIcon.create();
      if (icone == null) return;
      icone.icon = bandeja.ImageAsset.fromAsset('assets/desktop/bandeja.png');
      icone.setTooltip(nomeApp);
      final menu = bandeja.Menu.create()!;
      void item(String rotulo, VoidCallback acao) {
        final i = bandeja.MenuItem.createWithLabelAndType(rotulo, bandeja.MenuItemType.normal)!;
        i.addListener((e) {
          if (e is bandeja.MenuItemClickedEvent) acao();
        });
        menu.addItem(i);
      }

      item('Abrir $nomeApp', mostrar);
      item('Sincronizar agora', () {
        if (app.logado) unawaited(app.sincronizar());
      });
      menu.addSeparator();
      item('Sair', () => unawaited(sair()));
      icone.setContextMenu(menu);
      icone.setContextMenuTrigger(bandeja.ContextMenuTrigger.rightClicked);
      icone.addListener((e) {
        if (e is bandeja.TrayIconClickedEvent || e is bandeja.TrayIconDoubleClickedEvent) mostrar();
      });
      icone.setVisible(true);
      _icone = icone;
    } catch (_) {
      // sem bandeja (alguns ambientes Linux): fechar a janela encerra o app
      _icone = null;
    }
  }

  void mostrar() {
    final j = _janela;
    if (j == null) return;
    if (j.isMinimized) j.restore();
    j.show();
    j.focus();
  }

  Future<void> sair() async {
    _saindo = true;
    SegundoPlanoDesktop.parar();
    _icone?.dispose();
    _icone = null;
    await _servidor?.close();
    exit(0);
  }
}
