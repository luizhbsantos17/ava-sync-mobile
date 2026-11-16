import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win;

/// Navegador embutido usado pelo Q-Acadêmico. Esconde a diferença entre plataformas:
/// - Android, iOS e macOS: `webview_flutter` (o navegador do próprio sistema);
/// - Windows: `webview_windows` (Microsoft Edge WebView2, que já vem no Windows 10/11);
/// - Linux: sem navegador embutido por enquanto ([suportado] é falso).
abstract class NavegadorWeb {
  /// [aoTerminar]: a página terminou de carregar (url final).
  /// [aoFalhar]: a página principal não carregou (mensagem do erro).
  factory NavegadorWeb({void Function(String url)? aoTerminar, void Function(String erro)? aoFalhar}) =>
      Platform.isWindows ? _NavegadorWindows(aoTerminar, aoFalhar) : _NavegadorPadrao(aoTerminar, aoFalhar);

  static bool get suportado => !Platform.isLinux;

  Future<void> carregar(String url);
  Future<void> rodarJs(String codigo);

  /// Resultado do script. Pode vir como texto entre aspas (JSON) em algumas plataformas.
  Future<Object?> rodarJsComResultado(String codigo);
  Future<String?> urlAtual();
  Future<void> recarregar();
  Widget widget();
  void descartar();
}

class _NavegadorPadrao implements NavegadorWeb {
  final WebViewController _c = WebViewController();

  _NavegadorPadrao(void Function(String)? aoTerminar, void Function(String)? aoFalhar) {
    _c
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) => aoTerminar?.call(url),
          onWebResourceError: (e) {
            if (e.isForMainFrame == true) aoFalhar?.call(e.description);
          },
        ),
      );
  }

  @override
  Future<void> carregar(String url) => _c.loadRequest(Uri.parse(url));
  @override
  Future<void> rodarJs(String codigo) => _c.runJavaScript(codigo);
  @override
  Future<Object?> rodarJsComResultado(String codigo) => _c.runJavaScriptReturningResult(codigo);
  @override
  Future<String?> urlAtual() => _c.currentUrl();
  @override
  Future<void> recarregar() => _c.reload();
  @override
  Widget widget() => WebViewWidget(controller: _c);
  @override
  void descartar() {}
}

class _NavegadorWindows implements NavegadorWeb {
  final _c = win.WebviewController();
  late final Future<void> _pronto;
  final _subs = <StreamSubscription<dynamic>>[];
  String? _url;

  _NavegadorWindows(void Function(String)? aoTerminar, void Function(String)? aoFalhar) {
    _pronto = _iniciar(aoTerminar, aoFalhar);
  }

  Future<void> _iniciar(void Function(String)? aoTerminar, void Function(String)? aoFalhar) async {
    await _c.initialize();
    _subs
      ..add(_c.url.listen((u) => _url = u))
      ..add(
        _c.loadingState.listen((s) {
          if (s == win.LoadingState.navigationCompleted) aoTerminar?.call(_url ?? '');
        }),
      )
      ..add(_c.onLoadError.listen((e) => aoFalhar?.call('Erro ao carregar a página (${e.name}).')));
  }

  @override
  Future<void> carregar(String url) async {
    await _pronto;
    await _c.loadUrl(url);
  }

  @override
  Future<void> rodarJs(String codigo) async {
    await _pronto;
    await _c.executeScript(codigo);
  }

  @override
  Future<Object?> rodarJsComResultado(String codigo) async {
    await _pronto;
    return await _c.executeScript(codigo);
  }

  @override
  Future<String?> urlAtual() async => _url;

  @override
  Future<void> recarregar() async {
    await _pronto;
    await _c.reload();
  }

  @override
  Widget widget() => FutureBuilder<void>(
    future: _pronto,
    builder: (context, s) {
      if (s.hasError) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'Não consegui abrir o navegador embutido. Instale o Microsoft Edge WebView2 e tente de novo.',
              textAlign: TextAlign.center,
            ),
          ),
        );
      }
      if (s.connectionState != ConnectionState.done) return const SizedBox.shrink();
      return win.Webview(_c);
    },
  );

  @override
  void descartar() {
    for (final s in _subs) {
      s.cancel();
    }
    _c.dispose();
  }
}
