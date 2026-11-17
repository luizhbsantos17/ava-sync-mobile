import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'config.dart';
import 'plataforma.dart';
import 'util.dart';

/// Onde o app guarda as coisas.
///
/// - Arquivos baixados (PDFs, livros, imagens): pasta do app no armazenamento
///   externo (Android/data/(app)/files/AVA). Nao precisa de permissao e da para
///   ver pelo cabo USB. Se nao existir, usa a pasta interna.
/// - snapshot.json (tudo o que as telas mostram) e estado.json (o que ja foi visto):
///   pasta interna do app.
class Store {
  static Directory? _base, _dados;
  static Directory? baseTeste; // usado nos testes

  /// Pasta escolhida pela pessoa (só no computador), sempre com a subpasta "AVA Sync".
  static Directory? pastaEscolhida() {
    if (!Plataforma.desktop || Cfg.pastaArquivos.isEmpty) return null;
    return Directory('${Cfg.pastaArquivos}${Platform.pathSeparator}AVA Sync');
  }

  /// Troca a pasta dos arquivos. Com [mover], leva os arquivos já baixados junto.
  /// [nova] vazia volta para a pasta padrão.
  static Future<void> trocarPasta(String nova, {bool mover = true}) async {
    final antes = await base();
    await Cfg.setPastaArquivos(nova);
    _base = null;
    final depois = await base();
    if (!mover || antes.path == depois.path || !await antes.exists()) return;
    await for (final e in antes.list(followLinks: false)) {
      final destino = '${depois.path}${Platform.pathSeparator}${e.uri.pathSegments.where((s) => s.isNotEmpty).last}';
      try {
        await e.rename(destino);
      } catch (_) {
        // outro disco: copia e apaga
        if (e is File) {
          await e.copy(destino);
          await e.delete();
        } else if (e is Directory) {
          await _copiarPasta(e, Directory(destino));
          await e.delete(recursive: true);
        }
      }
    }
  }

  static Future<void> _copiarPasta(Directory de, Directory para) async {
    await para.create(recursive: true);
    await for (final e in de.list(followLinks: false)) {
      final nome = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (e is File) await e.copy('${para.path}${Platform.pathSeparator}$nome');
      if (e is Directory) await _copiarPasta(e, Directory('${para.path}${Platform.pathSeparator}$nome'));
    }
  }

  static Future<Directory> base() async {
    if (baseTeste != null) return baseTeste!;
    if (_base != null) return _base!;
    final escolhida = pastaEscolhida();
    if (escolhida != null) {
      try {
        await escolhida.create(recursive: true);
        return _base = escolhida;
      } catch (_) {
        // pasta sumiu (pendrive tirado, sem permissão): usa a padrão
      }
    }
    Directory? d;
    try {
      d = await getExternalStorageDirectory();
    } catch (_) {}
    d ??= await getApplicationDocumentsDirectory();
    _base = Directory('${d.path}/AVA');
    await _base!.create(recursive: true);
    return _base!;
  }

  static Future<Directory> dados() async {
    if (baseTeste != null) return baseTeste!;
    if (_dados != null) return _dados!;
    _dados = await getApplicationSupportDirectory();
    await _dados!.create(recursive: true);
    return _dados!;
  }

  static Future<Map<String, dynamic>> lerJson(String nome) async {
    final f = File('${(await dados()).path}/$nome');
    if (!await f.exists()) return {};
    try {
      return mapa(jsonDecode(await f.readAsString()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> gravarJson(String nome, Map<String, dynamic> d) async {
    final f = File('${(await dados()).path}/$nome');
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(d));
    await tmp.rename(f.path);
  }

  static Future<Map<String, dynamic>> snapshot() => lerJson('snapshot.json');
  static Future<void> salvarSnapshot(Map<String, dynamic> d) => gravarJson('snapshot.json', d);
  static Future<Map<String, dynamic>> estado() => lerJson('estado.json');
  static Future<void> salvarEstado(Map<String, dynamic> d) => gravarJson('estado.json', d);

  static Future<void> apagarTudo() async {
    for (final d in [await base(), await dados()]) {
      if (await d.exists()) {
        for (final e in d.listSync()) {
          try {
            await e.delete(recursive: true);
          } catch (_) {}
        }
      }
    }
  }

  static Future<int> tamanho() async {
    final d = await base();
    var t = 0;
    if (!await d.exists()) return 0;
    await for (final e in d.list(recursive: true, followLinks: false)) {
      if (e is File) t += await e.length();
    }
    return t;
  }

  static Future<void> limparArquivos() async {
    final d = await base();
    if (await d.exists()) await d.delete(recursive: true);
    await d.create(recursive: true);
  }
}
