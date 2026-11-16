import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'config.dart';
import 'plataforma.dart';
import 'util.dart';

/// Busca a versão publicada pelo workflow do repositório.
class AtualizacaoInfo {
  final int build;
  final int buildInstalado;
  /// Arquivo de instalação desta plataforma (APK no Android, instalador no Windows...).
  final String apkUrl;
  final String releaseUrl;
  final String versao;
  final String notas;

  const AtualizacaoInfo({
    required this.build,
    required this.buildInstalado,
    required this.apkUrl,
    required this.releaseUrl,
    this.versao = '',
    this.notas = '',
  });

  bool get disponivel => build > buildInstalado;
}

/// Texto do CHANGELOG que o workflow coloca depois do cabecalho (Build/Versao/Commit).
String notasDaRelease(String body) {
  final partes = body.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n'));
  if (partes.length < 2) return '';
  return partes.skip(1).join('\n\n').trim();
}

class Atualizacao {
  static const _repo = 'luizhbsantos17/ava-sync-mobile';
  static const canal = String.fromEnvironment('AVA_SYNC_CHANNEL', defaultValue: 'production');
  static const _tagRelease = canal == 'beta' ? 'beta' : 'latest';
  static String get _nomeArquivo => nomeDoArquivo(beta: canal == 'beta', plataforma: Plataforma.nome);

  /// Nome do arquivo publicado na release para cada plataforma (o workflow usa os mesmos).
  static String nomeDoArquivo({required bool beta, required String plataforma}) {
    final base = beta ? 'AVA-Sync-Beta' : 'AVA-Sync';
    return switch (plataforma) {
      'Windows' => '$base-Windows.exe',
      'Linux' => '$base-Linux.tar.gz',
      'macOS' => '$base-macOS.zip',
      _ => '$base.apk',
    };
  }
  static const buildInstalado = int.fromEnvironment('AVA_SYNC_BUILD', defaultValue: 0);

  static Future<AtualizacaoInfo> verificar({http.Client? cliente}) async {
    final client = cliente ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/tags/$_tagRelease'),
            headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'AVA-Sync-Mobile'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw Exception(response.statusCode == 404
            ? 'Ainda não há uma versão publicada para baixar.'
            : 'O GitHub respondeu com o código ${response.statusCode}.');
      }

      final release = jsonDecode(response.body) as Map<String, dynamic>;
      final body = '${release['body'] ?? ''}';
      final build = int.tryParse(RegExp(r'Build:\s*(\d+)', caseSensitive: false).firstMatch(body)?.group(1) ?? '');
      if (build == null) throw Exception('Não consegui identificar a versão publicada.');

      final assets = (release['assets'] as List<dynamic>? ?? const []).map((e) => e as Map<String, dynamic>);
      final apk = assets.where((e) => e['name'] == _nomeArquivo).firstOrNull;
      final apkUrl = '${apk?['browser_download_url'] ?? ''}';
      if (apkUrl.isEmpty) {
        throw Exception('O arquivo da versão publicada para ${Plataforma.nome} ainda não está disponível.');
      }

      return AtualizacaoInfo(
        build: build,
        buildInstalado: buildInstalado,
        apkUrl: apkUrl,
        releaseUrl: '${release['html_url'] ?? 'https://github.com/$_repo/releases'}',
        versao: RegExp(r'Vers\S*o:[ \t]*([^\r\n]+)', caseSensitive: false).firstMatch(body)?.group(1)?.trim() ?? '',
        notas: notasDaRelease(body),
      );
    } finally {
      if (cliente == null) client.close();
    }
  }

  /// Verificacao automatica (ao abrir o app e no segundo plano). Nunca lanca erro:
  /// sem internet ou com o GitHub fora do ar, so devolve null.
  static Future<AtualizacaoInfo?> verificarAuto({http.Client? cliente}) async {
    if (!Cfg.verificarAtualizacoes || buildInstalado == 0) return null;
    try {
      final info = await verificar(cliente: cliente);
      await Cfg.setUpdUltimaVerificacao(agoraSeg());
      return info.disponivel ? info : null;
    } catch (_) {
      return null;
    }
  }

  /// Deve perguntar agora? (a pessoa pode ter tocado em "Depois" para este build)
  static bool devePerguntar(AtualizacaoInfo info, int agora) =>
      info.disponivel && !(Cfg.updAdiadoBuild == info.build && agora < Cfg.updAdiadoAte);
}

/// Download do APK dentro do app. Grava num arquivo temporario e so renomeia quando o
/// tamanho bate com o anunciado pelo servidor, para nunca instalar um APK cortado.
class DownloadApk {
  /// Sem receber nenhum byte por este tempo, desiste (em vez de ficar parado para sempre).
  static const ociosoMax = Duration(seconds: 45);

  static Future<File> baixar(
    String url,
    Directory pasta, {
    void Function(int recebido, int? total)? progresso,
    http.Client? cliente,
    bool Function()? cancelado,
    Duration ocioso = ociosoMax,
    String nome = 'AVA-Sync.apk',
  }) async {
    final client = cliente ?? http.Client();
    await pasta.create(recursive: true);
    final destino = File('${pasta.path}/$nome');
    final parcial = File('${destino.path}.part');
    IOSink? sink;
    try {
      final req = http.Request('GET', Uri.parse(url))
        ..headers['User-Agent'] = 'AVA-Sync-Mobile'
        ..headers['Accept'] = 'application/octet-stream';
      final resp = await client.send(req).timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) throw Exception('O download respondeu com o código ${resp.statusCode}.');
      final total = resp.contentLength;
      if (await parcial.exists()) await parcial.delete();
      sink = parcial.openWrite();
      var recebido = 0;
      progresso?.call(0, total);
      await for (final bloco in resp.stream.timeout(ocioso,
          onTimeout: (s) => s.addError(Exception('O download parou de receber dados. Tente de novo.')))) {
        if (cancelado?.call() ?? false) throw const DownloadCancelado();
        sink.add(bloco);
        recebido += bloco.length;
        progresso?.call(recebido, total);
        if (total != null && recebido >= total) break; // terminou: nao espera o servidor fechar
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (total != null && recebido != total) {
        throw Exception('Download incompleto ($recebido de $total bytes). Tente de novo.');
      }
      if (recebido < 1024 * 1024) throw Exception('O arquivo baixado não parece um instalador válido.');
      if (await destino.exists()) await destino.delete();
      return await parcial.rename(destino.path);
    } catch (_) {
      await sink?.close();
      if (await parcial.exists()) await parcial.delete();
      rethrow;
    } finally {
      if (cliente == null) client.close();
    }
  }
}

class DownloadCancelado implements Exception {
  const DownloadCancelado();
  @override
  String toString() => 'Download cancelado.';
}
