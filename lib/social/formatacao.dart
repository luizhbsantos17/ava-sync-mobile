/// Formatação das mensagens no estilo Discord, sem depender de pacote:
/// **negrito**, *itálico* ou _itálico_, ~~riscado~~, `código`, ```bloco```,
/// ||spoiler||, > citação, links e @menções.
class Trecho {
  final String texto;
  final bool negrito;
  final bool italico;
  final bool riscado;
  final bool codigo;
  final bool bloco;
  final bool spoiler;
  final bool citacao;
  final String? link;
  final String? mencao;

  const Trecho(
    this.texto, {
    this.negrito = false,
    this.italico = false,
    this.riscado = false,
    this.codigo = false,
    this.bloco = false,
    this.spoiler = false,
    this.citacao = false,
    this.link,
    this.mencao,
  });

  Trecho _com({bool? negrito, bool? italico, bool? riscado, bool? spoiler, bool? citacao}) => Trecho(
        texto,
        negrito: negrito ?? this.negrito,
        italico: italico ?? this.italico,
        riscado: riscado ?? this.riscado,
        codigo: codigo,
        bloco: bloco,
        spoiler: spoiler ?? this.spoiler,
        citacao: citacao ?? this.citacao,
        link: link,
        mencao: mencao,
      );

  @override
  String toString() => [
        texto,
        if (negrito) 'b',
        if (italico) 'i',
        if (riscado) 's',
        if (codigo) 'code',
        if (bloco) 'block',
        if (spoiler) 'spoiler',
        if (citacao) 'quote',
        if (link != null) 'link',
        if (mencao != null) '@$mencao',
      ].join('|');
}

final _url = RegExp(r'https?://[^\s<>()]+[^\s<>().,;:!?"\x27]', caseSensitive: false);
final _mencao = RegExp(r'@([a-zA-Z0-9_.]{2,24})');

/// Troca cada "@usuário" pelo nome que aparece no chat ("@ifes_3f2a1b_1234" vira
/// "@Mikame"; "@everyone" vira "@todos"). [nome] devolve null para deixar como está.
/// Usado na notificação, na busca e na prévia da conversa (#7).
String trocarMencoes(String texto, String? Function(String usuario) nome) => texto.replaceAllMapped(_mencao, (m) {
      final u = m.group(1)!.toLowerCase();
      if (u == 'everyone' || u == 'todos') return '@todos';
      final n = nome(u);
      return n == null ? m.group(0)! : '@$n';
    });

List<Trecho> formatar(String texto) {
  final out = <Trecho>[];
  // blocos de código primeiro: nada dentro deles é formatado
  final partes = texto.split('```');
  for (var i = 0; i < partes.length; i++) {
    final parte = partes[i];
    if (i.isOdd && i < partes.length - 1) {
      var codigo = parte;
      final nl = codigo.indexOf('\n');
      if (nl >= 0 && RegExp(r'^[a-zA-Z0-9+#-]{0,15}$').hasMatch(codigo.substring(0, nl))) codigo = codigo.substring(nl + 1);
      out.add(Trecho(codigo.replaceAll(RegExp(r'\n$'), ''), bloco: true, codigo: true));
    } else {
      final t = i.isOdd ? '```$parte' : parte;
      out.addAll(_linhas(t));
    }
  }
  return _juntar(out);
}

List<Trecho> _linhas(String texto) {
  final out = <Trecho>[];
  final linhas = texto.split('\n');
  for (var i = 0; i < linhas.length; i++) {
    var linha = linhas[i];
    var citacao = false;
    if (linha.startsWith('> ')) {
      citacao = true;
      linha = linha.substring(2);
    }
    final trechos = _inline(linha, const Trecho(''));
    out.addAll(citacao ? trechos.map((t) => t._com(citacao: true)) : trechos);
    if (i < linhas.length - 1) out.add(const Trecho('\n'));
  }
  return out;
}

const _marcas = [
  ('`', 'codigo'),
  ('||', 'spoiler'),
  ('**', 'negrito'),
  ('~~', 'riscado'),
  ('*', 'italico'),
  ('_', 'italico'),
];

List<Trecho> _inline(String texto, Trecho estilo) {
  if (texto.isEmpty) return const [];
  // procura a primeira marca que abre e fecha
  var melhor = -1;
  (String, String)? marca;
  var fim = -1;
  for (final m in _marcas) {
    var start = texto.indexOf(m.$1);
    while (start >= 0) {
      final close = texto.indexOf(m.$1, start + m.$1.length);
      if (close < 0) break;
      final dentro = texto.substring(start + m.$1.length, close);
      final valido = dentro.isNotEmpty &&
          dentro.trim() == dentro &&
          // "_" no meio de palavras (nome_de_arquivo) não vira itálico
          (m.$1 != '_' || ((start == 0 || !_letra(texto[start - 1])) && (close + 1 >= texto.length || !_letra(texto[close + 1]))));
      if (valido) {
        if (melhor < 0 || start < melhor) {
          melhor = start;
          marca = m;
          fim = close;
        }
        break;
      }
      start = texto.indexOf(m.$1, start + 1);
    }
  }
  if (marca == null) return _simples(texto, estilo);
  final antes = texto.substring(0, melhor);
  final dentro = texto.substring(melhor + marca.$1.length, fim);
  final depois = texto.substring(fim + marca.$1.length);
  final List<Trecho> meio;
  if (marca.$2 == 'codigo') {
    meio = [Trecho(dentro, codigo: true, citacao: estilo.citacao)];
  } else {
    final novo = switch (marca.$2) {
      'spoiler' => estilo._com(spoiler: true),
      'negrito' => estilo._com(negrito: true),
      'riscado' => estilo._com(riscado: true),
      _ => estilo._com(italico: true),
    };
    meio = _inline(dentro, novo);
  }
  return [..._simples(antes, estilo), ...meio, ..._inline(depois, estilo)];
}

bool _letra(String c) => RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(c);

/// Texto sem marcas: separa links e menções.
List<Trecho> _simples(String texto, Trecho estilo) {
  if (texto.isEmpty) return const [];
  final out = <Trecho>[];
  final achados = <(int, int, String?, String?)>[];
  for (final m in _url.allMatches(texto)) {
    achados.add((m.start, m.end, m.group(0), null));
  }
  for (final m in _mencao.allMatches(texto)) {
    final dentroDeLink = achados.any((a) => a.$3 != null && m.start >= a.$1 && m.start < a.$2);
    final antes = m.start > 0 ? texto[m.start - 1] : ' ';
    if (!dentroDeLink && !_letra(antes)) achados.add((m.start, m.end, null, m.group(1)!.toLowerCase()));
  }
  achados.sort((a, b) => a.$1.compareTo(b.$1));
  var pos = 0;
  for (final a in achados) {
    if (a.$1 < pos) continue;
    if (a.$1 > pos) out.add(_estilo(texto.substring(pos, a.$1), estilo));
    out.add(Trecho(
      texto.substring(a.$1, a.$2),
      negrito: estilo.negrito,
      italico: estilo.italico,
      riscado: estilo.riscado,
      spoiler: estilo.spoiler,
      citacao: estilo.citacao,
      link: a.$3,
      mencao: a.$4,
    ));
    pos = a.$2;
  }
  if (pos < texto.length) out.add(_estilo(texto.substring(pos), estilo));
  return out;
}

Trecho _estilo(String texto, Trecho e) => Trecho(texto,
    negrito: e.negrito, italico: e.italico, riscado: e.riscado, spoiler: e.spoiler, citacao: e.citacao);

/// Junta trechos vizinhos com o mesmo estilo.
List<Trecho> _juntar(List<Trecho> lista) {
  final out = <Trecho>[];
  for (final t in lista) {
    if (t.texto.isEmpty) continue;
    if (out.isNotEmpty) {
      final u = out.last;
      if (u.link == null && t.link == null && u.mencao == null && t.mencao == null && !u.bloco && !t.bloco &&
          u.negrito == t.negrito && u.italico == t.italico && u.riscado == t.riscado && u.codigo == t.codigo &&
          u.spoiler == t.spoiler && u.citacao == t.citacao) {
        out[out.length - 1] = Trecho(u.texto + t.texto,
            negrito: u.negrito, italico: u.italico, riscado: u.riscado, codigo: u.codigo, spoiler: u.spoiler, citacao: u.citacao);
        continue;
      }
    }
    out.add(t);
  }
  return out;
}

/// Mensagem só com emojis (até 3) aparece grande, como no Discord.
bool soEmojis(String texto) {
  final t = texto.replaceAll(RegExp(r'\s'), '');
  if (t.isEmpty || t.runes.length > 14) return false;
  var n = 0;
  for (final r in t.runes) {
    if (r == 0x200D || r == 0xFE0F || r == 0x20E3 || (r >= 0x1F3FB && r <= 0x1F3FF) || (r >= 0xE0020 && r <= 0xE007F)) continue;
    final emoji = (r >= 0x1F000 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x2300 && r <= 0x23FF) ||
        (r >= 0x2B00 && r <= 0x2BFF) || r == 0x00A9 || r == 0x00AE || r == 0x203C || r == 0x2049 || (r >= 0x2190 && r <= 0x21FF);
    if (!emoji) return false;
    if (!(r >= 0x1F1E6 && r <= 0x1F1FF)) n++;
  }
  return n >= 1 && n <= 3;
}

/// "@" de um cargo: o nome em minúsculas, sem acento e com _ no lugar de espaço
/// ("Monitor de Cálculo" vira @monitor_de_calculo).
String apelidoCargo(String nome) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in nome.toLowerCase().split('')) {
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  final t = b.toString().replaceAll(RegExp(r'[^a-z0-9_.]+'), '_').replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^_|_$'), '');
  return t.isEmpty ? 'cargo' : (t.length > 24 ? t.substring(0, 24) : t);
}
