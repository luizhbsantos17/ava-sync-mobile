import 'dart:convert';

import 'package:http/http.dart' as http;

/// Busca a versão publicada pelo workflow do repositório.
class AtualizacaoInfo {
  final int build;
  final int buildInstalado;
  final String apkUrl;
  final String releaseUrl;

  const AtualizacaoInfo({
    required this.build,
    required this.buildInstalado,
    required this.apkUrl,
    required this.releaseUrl,
  });

  bool get disponivel => build > buildInstalado;
}

class Atualizacao {
  static const _repo = 'luizhbsantos17/ava-sync-mobile';
  static const buildInstalado = int.fromEnvironment('AVA_SYNC_BUILD', defaultValue: 0);

  static Future<AtualizacaoInfo> verificar({http.Client? cliente}) async {
    final client = cliente ?? http.Client();
    try {
      final response = await client
          .get(
            Uri.parse('https://api.github.com/repos/$_repo/releases/tags/latest'),
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
      final apk = assets.where((e) => e['name'] == 'AVA-Sync.apk').firstOrNull;
      final apkUrl = '${apk?['browser_download_url'] ?? ''}';
      if (apkUrl.isEmpty) throw Exception('O APK da versão publicada ainda não está disponível.');

      return AtualizacaoInfo(
        build: build,
        buildInstalado: buildInstalado,
        apkUrl: apkUrl,
        releaseUrl: '${release['html_url'] ?? 'https://github.com/$_repo/releases'}',
      );
    } finally {
      if (cliente == null) client.close();
    }
  }
}
