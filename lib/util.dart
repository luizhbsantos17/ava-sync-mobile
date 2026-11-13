import 'dart:convert';
import 'dart:io';

/// Titulo -> nome de arquivo/pasta valido no Android.
String nomeSeguro(String? texto, [int limite = 80]) {
  var t = desescapar(texto ?? 'sem_nome');
  t = t.replaceAll(RegExp(r'[/\\]'), '-');
  t = t.replaceAll(RegExp(r'[<>:"|?*\x00-\x1f]'), '');
  t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
  while (t.endsWith('.')) {
    t = t.substring(0, t.length - 1);
  }
  if (t.length > limite) t = t.substring(0, limite).trim();
  return t.isEmpty ? 'sem_nome' : t;
}

String desescapar(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&nbsp;', ' ');

/// HTML -> texto simples (busca, IA, notificacoes).
String semHtml(String? html) {
  if (html == null || html.isEmpty) return '';
  var t = html.replaceAll(RegExp(r'<(script|style)[^>]*>.*?</\1>', caseSensitive: false, dotAll: true), '');
  t = t.replaceAll(RegExp(r'<br\s*/?>|</p>|</li>|</h\d>|</div>', caseSensitive: false), '\n');
  t = t.replaceAll(RegExp(r'<li[^>]*>', caseSensitive: false), '- ');
  t = t.replaceAll(RegExp(r'<[^>]+>'), '');
  t = desescapar(t);
  return t.replaceAll(RegExp(r'\n\s*\n\s*\n+'), '\n\n').trim();
}

/// Hash curto e estavel (FNV-1a 32 bits) para nomes de arquivo.
String hashCurto(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h.toRadixString(16).padLeft(8, '0');
}

int agoraSeg() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

DateTime? deSeg(dynamic ts) {
  final n = ts is int ? ts : int.tryParse('${ts ?? ''}');
  if (n == null || n == 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(n * 1000);
}

String _dd(int n) => n.toString().padLeft(2, '0');

String fmtData(dynamic ts, {bool hora = true}) {
  final d = deSeg(ts);
  if (d == null) return '-';
  final base = '${_dd(d.day)}/${_dd(d.month)}/${d.year}';
  return hora ? '$base ${_dd(d.hour)}:${_dd(d.minute)}' : base;
}

const _dias = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

/// "hoje 23:59", "amanhã 08:00", "sex 14/11 23:59", "há 2 dias"
String fmtRelativo(dynamic ts) {
  final d = deSeg(ts);
  if (d == null) return '-';
  final agora = DateTime.now();
  final hoje = DateTime(agora.year, agora.month, agora.day);
  final dia = DateTime(d.year, d.month, d.day);
  final diff = dia.difference(hoje).inDays;
  final h = '${_dd(d.hour)}:${_dd(d.minute)}';
  if (diff == 0) return 'hoje $h';
  if (diff == 1) return 'amanhã $h';
  if (diff == -1) return 'ontem $h';
  if (diff < -1) return 'há ${-diff} dias';
  if (diff < 7) return '${_dias[d.weekday - 1]} ${_dd(d.day)}/${_dd(d.month)} $h';
  return '${_dd(d.day)}/${_dd(d.month)}/${d.year} $h';
}

String fmtTamanho(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

/// Escreve so se o conteudo mudou. Devolve true se escreveu.
Future<bool> escreverSeMudou(File f, String conteudo) async {
  if (await f.exists()) {
    try {
      if (await f.readAsString() == conteudo) return false;
    } catch (_) {}
  }
  await f.parent.create(recursive: true);
  await f.writeAsString(conteudo);
  return true;
}

Map<String, dynamic> mapa(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<dynamic> lista(dynamic v) => v is List ? v : const [];
