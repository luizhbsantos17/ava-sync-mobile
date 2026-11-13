import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'moodle.dart';
import 'util.dart';

/// Hosts que ficam so como link: videos, documentos com login, reunioes,
/// formularios e bibliotecas virtuais (leitores protegidos, sem arquivo para baixar).
const hostsSoLink = [
  'youtube.com', 'youtu.be', 'vimeo.com', 'drive.google.com', 'docs.google.com', 'forms.gle',
  'forms.office.com', 'meet.google.com', 'classroom.google.com', 'zoom.us', 'teams.microsoft.com',
  'sharepoint.com', 'onedrive.live.com', '1drv.ms', 'bvirtual.com.br', 'digitalpages.com.br',
  'minhabiblioteca.com.br', 'pearson.com', 'bibliotecavirtual', 'dliportal', 'elsevier',
  'springer.com', 'scribd.com',
];

const _extArquivo = [
  '.pdf', '.doc', '.docx', '.ppt', '.pptx', '.pps', '.ppsx', '.xls', '.xlsx', '.odt', '.odp', '.ods',
  '.zip', '.rar', '.7z', '.txt', '.csv', '.png', '.jpg', '.jpeg', '.gif', '.mp3', '.mp4', '.pkt', '.ipynb',
];

final _imgRe = RegExp(r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])(.*?)\2''', caseSensitive: false, dotAll: true);
final _aRe = RegExp(r'''(<a\b[^>]*?\bhref\s*=\s*)(["'])(.*?)\2''', caseSensitive: false, dotAll: true);

/// Imagens embutidas no HTML do Moodle e livros (recurso "Livro").
///
/// O HTML que a API devolve aponta imagens para .../pluginfile.php, que so abrem com
/// login. Aqui cada imagem e baixada (com token, se for do Moodle; sem token, se for
/// externa) e o src passa a ser o caminho do arquivo no celular. O leitor do app
/// mostra caminhos que comecam com "/" usando Image.file.
class Midia {
  final Moodle m;
  final Directory pastaImagens;
  final http.Client externo;

  /// false: nao baixa nada agora (materia de semestre antigo); as imagens do Moodle
  /// sao carregadas pela internet quando a tela abre, e os arquivos quando tocados.
  final bool baixar;
  final int maxMb;
  final Map<String, String?> _cache = {};

  Midia(this.m, this.pastaImagens, {http.Client? externo, this.baixar = true, this.maxMb = 100})
      : externo = externo ?? http.Client();

  Directory get pastaArquivos => Directory('${pastaImagens.parent.path}/_arquivos');

  /// Arquivo do Moodle linkado dentro de um texto (ex.: "clique aqui" -> notas.pdf).
  Future<String?> arquivoLinkado(String url) async {
    final chave = 'a:$url';
    if (_cache.containsKey(chave)) return _cache[chave];
    String? local;
    try {
      final uri = Uri.parse(url.replaceAll('?forcedownload=1', ''));
      final nome = uri.pathSegments.isEmpty ? 'arquivo' : Uri.decodeComponent(uri.pathSegments.last);
      final f = File('${pastaArquivos.path}/${hashCurto(uri.path)}_${nomeSeguro(nome, 80)}');
      if (await f.exists()) {
        local = f.path;
      } else {
        await m.baixar(url, f, maxMb: maxMb);
        if (await f.exists()) local = f.path;
      }
    } catch (_) {}
    _cache[chave] = local;
    return local;
  }

  Future<String?> imagem(String url) async {
    if (_cache.containsKey(url)) return _cache[url];
    String? local;
    try {
      final uri = Uri.parse(url);
      final base = uri.pathSegments.isEmpty ? 'imagem' : Uri.decodeComponent(uri.pathSegments.last);
      final f = File('${pastaImagens.path}/${hashCurto(url.split('token=').first)}_${nomeSeguro(base, 60)}');
      if (await f.exists()) {
        local = f.path;
      } else if (m.ehDoSite(url)) {
        await m.baixar(url, f, maxMb: 30);
        if (await f.exists()) local = f.path;
      } else if (uri.scheme == 'http' || uri.scheme == 'https') {
        if (await baixarExterno(externo, url, f, 30) != null) local = f.path;
      }
    } catch (_) {}
    _cache[url] = local;
    return local;
  }

  /// Baixa as imagens do HTML e troca o src pelo caminho local.
  Future<String> html(String? h, {String? baseUrl}) async {
    if (h == null || h.isEmpty) return '';
    if (!baixar) return h;
    return _links(await _imagens(h, baseUrl: baseUrl));
  }

  /// Links para arquivos do proprio Moodle (pluginfile.php) sao baixados e passam a
  /// apontar para o arquivo local. Links para atividades do Moodle (mod/.../view.php)
  /// ficam como estao: o app abre a atividade dentro dele mesmo.
  Future<String> _links(String h) async {
    if (!h.toLowerCase().contains('pluginfile.php')) return h;
    final buf = StringBuffer();
    var ultimo = 0;
    for (final mt in _aRe.allMatches(h)) {
      buf.write(h.substring(ultimo, mt.start));
      final href = desescapar(mt.group(3)!.trim());
      String? local;
      if (href.contains('pluginfile.php') && m.ehDoSite(href)) local = await arquivoLinkado(href);
      buf.write(local == null ? mt.group(0) : '${mt.group(1)}${mt.group(2)}$local${mt.group(2)}');
      ultimo = mt.end;
    }
    buf.write(h.substring(ultimo));
    return buf.toString();
  }

  Future<String> _imagens(String h, {String? baseUrl}) async {
    if (!h.toLowerCase().contains('<img')) return h;
    final buf = StringBuffer();
    var ultimo = 0;
    for (final mt in _imgRe.allMatches(h)) {
      buf.write(h.substring(ultimo, mt.start));
      var src = desescapar(mt.group(3)!.trim());
      if (baseUrl != null && !src.startsWith('data:')) src = Uri.parse(baseUrl).resolve(src).toString();
      String? local;
      if (src.startsWith('http://') || src.startsWith('https://')) local = await imagem(src);
      buf.write(local == null ? mt.group(0) : '${mt.group(1)}${mt.group(2)}$local${mt.group(2)}');
      ultimo = mt.end;
    }
    buf.write(h.substring(ultimo));
    return buf.toString();
  }

  /// Livro do Moodle -> um HTML so, com sumario e capitulos na ordem. Devolve true se mudou.
  Future<bool> salvarLivro(Map<String, dynamic> mod, File destino) async {
    final conteudos = lista(mod['contents']).map(mapa).toList();
    final capitulos = <String, Map<String, dynamic>>{};
    for (final c in conteudos) {
      if (c['type'] == 'file' && c['filename'] == 'index.html') {
        capitulos[('${c['filepath'] ?? '/'}').replaceAll('/', '')] = c;
      }
    }
    if (capitulos.isEmpty) return false;

    final ordem = <({String id, String titulo, int nivel})>[];
    final estrutura = conteudos.where((c) => c['filename'] == 'structure').firstOrNull;
    dynamic itens;
    try {
      itens = estrutura == null ? null : jsonDecode('${estrutura['content']}');
    } catch (_) {}
    void andar(dynamic l, int nivel) {
      for (final it in lista(l).map(mapa)) {
        ordem.add((id: '${it['href'] ?? ''}'.split('/').first, titulo: '${it['title'] ?? ''}', nivel: nivel));
        andar(it['subitems'], nivel + 1);
      }
    }

    andar(itens, 0);
    if (ordem.isEmpty) {
      var i = 0;
      for (final e in capitulos.entries) {
        i++;
        ordem.add((id: e.key, titulo: '${e.value['content'] ?? 'Capítulo $i'}', nivel: 0));
      }
    }

    final partes = StringBuffer();
    final sumario = StringBuffer();
    for (final cap in ordem) {
      final c = capitulos[cap.id];
      if (c == null) continue;
      String corpo;
      try {
        corpo = await html(await m.ler('${c['fileurl']}'));
      } catch (e) {
        corpo = '<p><i>Capítulo não baixado ($e).</i></p>';
      }
      final tag = cap.nivel == 0 ? 'h2' : 'h3';
      sumario.write('<li>${'&nbsp;' * (cap.nivel * 4)}${_esc(cap.titulo)}</li>');
      partes.write('<$tag>${_esc(cap.titulo)}</$tag>\n$corpo\n<hr>\n');
    }
    if (partes.isEmpty) return false;
    final doc = '<h1>${_esc('${mod['name'] ?? 'Livro'}')}</h1><p><b>Sumário</b></p><ul>$sumario</ul><hr>$partes';
    return escreverSeMudou(destino, doc);
  }

  /// Recurso URL: se for link direto para um arquivo publico (PDF, PPT...), baixa sem token.
  /// Devolve o arquivo salvo, ou null (fica so o link).
  Future<File?> baixarLink(String url, String nome, Directory pasta, int maxMb) async {
    if (!baixar) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) return null;
    final host = uri.host.toLowerCase();
    if (m.ehDoSite(url) || hostsSoLink.any(host.contains)) return null;
    final caminho = uri.path.toLowerCase();
    final ext = _extArquivo.where(caminho.endsWith).firstOrNull;
    if (ext == null) return null; // pagina: abre no navegador
    final f = File('${pasta.path}/${nomeSeguro(nome, 80)}$ext');
    if (await f.exists()) return f;
    try {
      return await baixarExterno(externo, url, f, maxMb) != null ? f : null;
    } catch (_) {
      return null;
    }
  }
}

String _esc(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

/// GET sem token e sem cookies. Devolve o content-type, ou null se nao baixou.
Future<String?> baixarExterno(http.Client c, String url, File destino, int maxMb) async {
  final req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Mozilla/5.0 (AVA Sync)';
  final r = await c.send(req).timeout(const Duration(seconds: 30));
  if (r.statusCode >= 400) {
    await r.stream.drain<void>();
    return null;
  }
  final ct = (r.headers['content-type'] ?? '').split(';').first.trim().toLowerCase();
  if (ct == 'text/html') {
    await r.stream.drain<void>(); // tela de login ou pagina: nao e o arquivo
    return null;
  }
  await destino.parent.create(recursive: true);
  final tmp = File('${destino.path}.part');
  final sink = tmp.openWrite();
  var total = 0;
  var estourou = false;
  try {
    await for (final b in r.stream) {
      total += b.length;
      if (total > maxMb * 1024 * 1024) {
        estourou = true;
        break;
      }
      sink.add(b);
    }
  } finally {
    await sink.close();
  }
  if (estourou) {
    await tmp.delete();
    return null;
  }
  await tmp.rename(destino.path);
  return ct;
}
