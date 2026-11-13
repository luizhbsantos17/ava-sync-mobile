import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Erro da API. [sessao] = token invalido/expirado (o app volta para o login).
class MoodleErro implements Exception {
  final String msg;
  final bool sessao;
  MoodleErro(this.msg, {this.sessao = false});
  @override
  String toString() => msg;
}

/// Cliente da API REST do Moodle (Web Services), a mesma do app oficial.
///
/// 1. Login: POST /login/token.php (usuario, senha, service=moodle_mobile_app) -> token.
/// 2. Chamadas: POST /webservice/rest/server.php com wstoken, wsfunction e parametros.
/// 3. Arquivos: `fileurl?token=...` (o fileurl aponta para webservice/pluginfile.php).
/// O token so e anexado a enderecos do proprio Moodle.
class Moodle {
  final String site;
  final String token;
  final http.Client c;
  Moodle(this.site, this.token, {http.Client? cliente}) : c = cliente ?? http.Client();

  String get host => Uri.parse(site).host.toLowerCase();
  bool ehDoSite(String url) => (Uri.tryParse(url)?.host.toLowerCase() ?? '') == host;

  /// Confere se o site tem a API do app liberada. Devolve um aviso legivel ou null se ok.
  static Future<String?> verificarSite(String site, {http.Client? cliente}) async {
    final cl = cliente ?? http.Client();
    try {
      final r = await cl
          .post(Uri.parse('$site/lib/ajax/service-nologin.php?info=tool_mobile_get_public_config'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode([
                {'index': 0, 'methodname': 'tool_mobile_get_public_config', 'args': {}}
              ]))
          .timeout(const Duration(seconds: 20));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final cfg = (d is List && d.isNotEmpty) ? (d.first['data'] as Map?) : null;
      if (cfg == null) return 'Não consegui ler a configuração do site. Confira o endereço.';
      if (cfg['enablewebservices'] != 1 || cfg['enablemobilewebservice'] != 1) {
        return 'Este Moodle não libera a API do app (o administrador precisa ativar o serviço móvel).';
      }
      final tipo = cfg['typeoflogin'];
      if (tipo == 2 || tipo == 3) {
        return 'Este Moodle usa login pelo navegador (SSO). O login por usuário e senha pode não funcionar.';
      }
      return null;
    } catch (e) {
      return 'Não consegui acessar o site ($e).';
    }
  }

  /// Troca usuario e senha por um token. A senha so existe dentro desta funcao.
  static Future<String> gerarToken(String site, String usuario, String senha, {http.Client? cliente}) async {
    final cl = cliente ?? http.Client();
    final r = await cl.post(Uri.parse('$site/login/token.php'),
        body: {'username': usuario, 'password': senha, 'service': 'moodle_mobile_app'}).timeout(
        const Duration(seconds: 30));
    dynamic d;
    try {
      d = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw MoodleErro('Resposta inesperada do site (HTTP ${r.statusCode}). Confira o endereço.');
    }
    if (d is Map && d['token'] is String) return d['token'];
    throw MoodleErro(d is Map && d['error'] != null ? '${d['error']}' : 'Login recusado.');
  }

  /// Parametros aninhados -> formulario: lista vira chave[0], mapa vira chave[sub].
  static Map<String, String> achatar(Map<String, dynamic> p) {
    final out = <String, String>{};
    void add(String k, dynamic v) {
      if (v is List) {
        for (var i = 0; i < v.length; i++) {
          add('$k[$i]', v[i]);
        }
      } else if (v is Map) {
        v.forEach((kk, vv) => add('$k[$kk]', vv));
      } else if (v is bool) {
        out[k] = v ? '1' : '0';
      } else if (v != null) {
        out[k] = '$v';
      }
    }

    p.forEach(add);
    return out;
  }

  Future<dynamic> call(String funcao, [Map<String, dynamic> p = const {}]) async {
    final corpo = {'wstoken': token, 'wsfunction': funcao, 'moodlewsrestformat': 'json', ...achatar(p)};
    final r = await c
        .post(Uri.parse('$site/webservice/rest/server.php'), body: corpo)
        .timeout(const Duration(seconds: 90));
    if (r.statusCode != 200) throw MoodleErro('$funcao: HTTP ${r.statusCode}');
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    if (d is Map && d['exception'] != null) {
      final cod = d['errorcode'];
      if (cod == 'invalidtoken' || cod == 'accessexception') {
        throw MoodleErro('Sua sessão expirou. Entre de novo.', sessao: true);
      }
      throw MoodleErro('${d['message'] ?? cod}');
    }
    return d;
  }

  /// Como [call], mas uma funcao nao liberada no site nao derruba a sincronizacao.
  Future<dynamic> tentar(String funcao, dynamic padrao, [Map<String, dynamic> p = const {}]) async {
    try {
      return await call(funcao, p);
    } on MoodleErro catch (e) {
      if (e.sessao) rethrow;
      return padrao;
    } catch (_) {
      return padrao;
    }
  }

  /// URL de arquivo do Moodle com o token. pluginfile.php -> webservice/pluginfile.php.
  String comToken(String url) {
    var u = url;
    if (u.contains('/pluginfile.php') && !u.contains('/webservice/pluginfile.php')) {
      u = u.replaceFirst('/pluginfile.php', '/webservice/pluginfile.php');
    }
    if (u.contains('token=')) return u;
    return '$u${u.contains('?') ? '&' : '?'}token=$token';
  }

  /// Baixa um arquivo do Moodle. Devolve true se baixou agora (false se ja existia ou pulou).
  Future<bool> baixar(String url, File destino, {int? tamanho, int maxMb = 200}) async {
    if (!ehDoSite(url)) throw MoodleErro('endereço fora do Moodle');
    if (await destino.exists()) {
      if (tamanho == null || tamanho <= 0 || await destino.length() == tamanho) return false;
    }
    if (tamanho != null && tamanho > maxMb * 1024 * 1024) return false;
    await destino.parent.create(recursive: true);
    final resp = await c.send(http.Request('GET', Uri.parse(comToken(url)))).timeout(const Duration(seconds: 60));
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>();
      throw MoodleErro('download HTTP ${resp.statusCode}');
    }
    final ct = resp.headers['content-type'] ?? '';
    final tmp = File('${destino.path}.part');
    final sink = tmp.openWrite();
    var total = 0;
    try {
      await for (final bloco in resp.stream) {
        total += bloco.length;
        if (total > maxMb * 1024 * 1024) throw MoodleErro('maior que $maxMb MB');
        sink.add(bloco);
      }
    } finally {
      await sink.close();
    }
    // erro do Moodle vem como JSON no lugar do arquivo
    if (ct.contains('application/json') && total < 4096) {
      final txt = await tmp.readAsString();
      await tmp.delete();
      if (txt.contains('invalidtoken')) throw MoodleErro('Sua sessão expirou. Entre de novo.', sessao: true);
      throw MoodleErro('o Moodle recusou o arquivo');
    }
    await tmp.rename(destino.path);
    return true;
  }

  /// Le um arquivo pequeno do Moodle como texto (ex.: capitulo de livro).
  Future<String> ler(String url) async {
    if (!ehDoSite(url)) throw MoodleErro('endereço fora do Moodle');
    final r = await c.get(Uri.parse(comToken(url))).timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) throw MoodleErro('HTTP ${r.statusCode}');
    return utf8.decode(r.bodyBytes, allowMalformed: true);
  }

  /// Envia arquivos para a area de rascunho do usuario. Devolve o itemid.
  Future<int> upload(List<({String nome, Uint8List bytes})> arquivos) async {
    final req = http.MultipartRequest('POST', Uri.parse('$site/webservice/upload.php'));
    req.fields.addAll({'token': token, 'filearea': 'draft', 'itemid': '0'});
    for (var i = 0; i < arquivos.length; i++) {
      req.files.add(http.MultipartFile.fromBytes('file_${i + 1}', arquivos[i].bytes, filename: arquivos[i].nome));
    }
    final r = await http.Response.fromStream(await c.send(req).timeout(const Duration(minutes: 5)));
    final d = jsonDecode(utf8.decode(r.bodyBytes));
    if (d is Map && (d['error'] != null || d['exception'] != null)) {
      throw MoodleErro('Upload recusado: ${d['error'] ?? d['message']}');
    }
    if (d is List && d.isNotEmpty && d.first is Map && d.first['itemid'] != null) {
      return (d.first['itemid'] as num).toInt();
    }
    throw MoodleErro('Upload sem resposta do Moodle.');
  }
}
