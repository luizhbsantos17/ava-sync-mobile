import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'armazenamento.dart';
import 'config.dart';
import 'plataforma.dart';

/// Salva um arquivo (anexo do Social, imagem) onde a pessoa escolher.
///
/// Pergunta com o diálogo do sistema; no computador, com "perguntar onde salvar"
/// desligado, grava direto em Downloads/AVA Sync (ou na pasta escolhida em Ajustes).
/// Devolve onde salvou, ou null se a pessoa cancelou.
Future<String?> salvarArquivo(String nome, Uint8List bytes, {String mime = 'application/octet-stream'}) async {
  final limpo = nome.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  if (Plataforma.desktop && !Cfg.perguntarOndeSalvar) {
    final base = Store.pastaEscolhida()?.path ?? (await getDownloadsDirectory())?.path ?? (await Store.base()).path;
    final pasta = Directory('$base${Platform.pathSeparator}${Store.pastaEscolhida() == null ? 'AVA Sync' : 'Social'}');
    await pasta.create(recursive: true);
    final f = File(nomeLivre(pasta.path, limpo, (p) => File(p).existsSync()));
    await f.writeAsBytes(bytes, flush: true);
    return f.path;
  }
  final uri = await FilePicker.saveFile(fileName: limpo, bytes: bytes, mimeType: mime, dialogTitle: 'Salvar arquivo');
  if (uri == null) return null;
  return uri.scheme == 'file' ? uri.toFilePath() : limpo;
}

/// "foto.png" já existe: "foto (2).png", "foto (3).png"... (puro, testável)
String nomeLivre(String pasta, String nome, bool Function(String caminho) existe) {
  final sep = Platform.pathSeparator;
  var caminho = '$pasta$sep$nome';
  if (!existe(caminho)) return caminho;
  final ponto = nome.lastIndexOf('.');
  final raiz = ponto > 0 ? nome.substring(0, ponto) : nome;
  final ext = ponto > 0 ? nome.substring(ponto) : '';
  for (var i = 2;; i++) {
    caminho = '$pasta$sep$raiz ($i)$ext';
    if (!existe(caminho)) return caminho;
  }
}

/// Abre a pasta no gerenciador de arquivos do sistema.
Future<bool> abrirPasta(String caminho) => launchUrl(Uri.directory(caminho));
