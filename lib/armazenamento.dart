import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

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

  static Future<Directory> base() async {
    if (baseTeste != null) return baseTeste!;
    if (_base != null) return _base!;
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
