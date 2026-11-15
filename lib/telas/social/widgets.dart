import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../social/formatacao.dart';
import '../../social/models.dart';
import '../../social/service.dart';

SocialService get social => SocialService.instance;

// ------------------------------------------------------------ cores
const corOnline = Color(0xFF23A55A);
const corOcupado = Color(0xFFF23F43);
const corAusente = Color(0xFFF0B232);
const corOffline = Color(0xFF80848E);

Color corPresenca(Presenca p) => switch (p) {
      Presenca.online => corOnline,
      Presenca.busy => corOcupado,
      Presenca.away => corAusente,
      _ => corOffline,
    };

const _paleta = [
  Color(0xFF5865F2),
  Color(0xFF3BA55C),
  Color(0xFFFAA61A),
  Color(0xFFED4245),
  Color(0xFFEB459E),
  Color(0xFF00A8FC),
  Color(0xFF9B59B6),
  Color(0xFF1ABC9C),
  Color(0xFFE67E22),
  Color(0xFF607D8B),
];

Color corDe(String chave) {
  var h = 0;
  for (final c in chave.codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  return _paleta[h % _paleta.length];
}

const coresBanner = [
  0xFF5865F2, 0xFF3BA55C, 0xFFFAA61A, 0xFFED4245, 0xFFEB459E, 0xFF00A8FC,
  0xFF9B59B6, 0xFF1ABC9C, 0xFFE67E22, 0xFF2C2F33, 0xFF607D8B, 0xFFB5838D,
];

String iniciais(String nome) {
  final partes = nome.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (partes.isEmpty) return '?';
  if (partes.length == 1) return partes.first.characters.take(2).toString().toUpperCase();
  return '${partes.first.characters.first}${partes.last.characters.first}'.toUpperCase();
}

// ------------------------------------------------------------ datas
const _meses = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
String dois(int n) => n.toString().padLeft(2, '0');
String hora(DateTime d) => '${dois(d.hour)}:${dois(d.minute)}';

bool mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

String quando(DateTime d) {
  final hoje = DateTime.now();
  if (mesmoDia(d, hoje)) return 'Hoje às ${hora(d)}';
  if (mesmoDia(d, hoje.subtract(const Duration(days: 1)))) return 'Ontem às ${hora(d)}';
  return '${dois(d.day)}/${dois(d.month)}/${d.year} ${hora(d)}';
}

String quandoCurto(DateTime d) {
  final hoje = DateTime.now();
  if (mesmoDia(d, hoje)) return hora(d);
  if (mesmoDia(d, hoje.subtract(const Duration(days: 1)))) return 'Ontem';
  if (hoje.difference(d).inDays < 7) return const ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'][d.weekday - 1];
  return '${dois(d.day)}/${dois(d.month)}';
}

String dia(DateTime d) {
  final hoje = DateTime.now();
  if (mesmoDia(d, hoje)) return 'Hoje';
  if (mesmoDia(d, hoje.subtract(const Duration(days: 1)))) return 'Ontem';
  return '${d.day} de ${_meses[d.month - 1]}. de ${d.year}';
}

String visto(DateTime? d) {
  if (d == null) return 'Offline';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 60) return 'Visto há ${diff.inMinutes.clamp(1, 59)} min';
  if (diff.inHours < 24) return 'Visto há ${diff.inHours} h';
  return 'Visto em ${dois(d.day)}/${dois(d.month)}';
}

String tamanho(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

// ------------------------------------------------------------ imagens
/// Imagem do armazenamento do Social (foto de perfil, ícone ou anexo).
class SocialImagem extends StatefulWidget {
  final String path;
  final String? conversationId;
  final BoxFit fit;
  final Widget Function(BuildContext context) placeholder;
  const SocialImagem({super.key, required this.path, this.conversationId, this.fit = BoxFit.cover, required this.placeholder});

  @override
  State<SocialImagem> createState() => _SocialImagemState();
}

class _SocialImagemState extends State<SocialImagem> {
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void didUpdateWidget(SocialImagem old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _carregar();
  }

  void _carregar() {
    _bytes = social.cachedBytes(widget.path);
    if (_bytes != null) return;
    final f = widget.conversationId == null ? social.image(widget.path) : social.attachment(widget.conversationId!, widget.path);
    f.then((b) {
      if (mounted && b != null) setState(() => _bytes = b);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _bytes;
    if (b == null) return widget.placeholder(context);
    return Image.memory(b, fit: widget.fit, gaplessPlayback: true, errorBuilder: (c, _, _) => widget.placeholder(c));
  }
}

class SocialAvatar extends StatelessWidget {
  final SocialProfile profile;
  final double size;
  final bool presenca;
  final Color? fundoBorda;
  const SocialAvatar({super.key, required this.profile, this.size = 40, this.presenca = true, this.fundoBorda});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cor = corDe(profile.userKey);
    Widget base(BuildContext _) => Container(
          color: cor,
          alignment: Alignment.center,
          child: Text(iniciais(profile.displayName),
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * .38)),
        );
    final img = ClipOval(
      child: SizedBox.square(
        dimension: size,
        child: profile.avatarPath == null ? base(context) : SocialImagem(path: profile.avatarPath!, placeholder: base),
      ),
    );
    if (!presenca) return img;
    final dot = size * .32;
    return SizedBox.square(
      dimension: size,
      child: Stack(clipBehavior: Clip.none, children: [
        img,
        Positioned(
          right: -1,
          bottom: -1,
          child: Container(
            width: dot,
            height: dot,
            decoration: BoxDecoration(shape: BoxShape.circle, color: fundoBorda ?? cs.surface),
            padding: EdgeInsets.all(dot * .18),
            child: PontoPresenca(profile.presence),
          ),
        ),
      ]),
    );
  }
}

class PontoPresenca extends StatelessWidget {
  final Presenca presenca;
  const PontoPresenca(this.presenca, {super.key});

  @override
  Widget build(BuildContext context) {
    final cor = corPresenca(presenca);
    return switch (presenca) {
      Presenca.busy => Container(
          decoration: BoxDecoration(shape: BoxShape.circle, color: cor),
          alignment: Alignment.center,
          child: FractionallySizedBox(widthFactor: .6, heightFactor: .22, child: Container(color: Theme.of(context).colorScheme.surface)),
        ),
      Presenca.away => CustomPaint(painter: _Lua(cor, Theme.of(context).colorScheme.surface)),
      Presenca.online => Container(decoration: BoxDecoration(shape: BoxShape.circle, color: cor)),
      _ => Container(decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: cor, width: 2.2))),
    };
  }
}

class _Lua extends CustomPainter {
  final Color cor;
  final Color fundo;
  _Lua(this.cor, this.fundo);
  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width / 2;
    canvas.drawCircle(Offset(r, r), r, Paint()..color = cor);
    canvas.drawCircle(Offset(r * .55, r * .55), r * .6, Paint()..color = fundo);
  }

  @override
  bool shouldRepaint(_Lua old) => old.cor != cor || old.fundo != fundo;
}

class IconeGrupo extends StatelessWidget {
  final SocialConversation conversa;
  final double size;
  final bool selecionado;
  const IconeGrupo({super.key, required this.conversa, this.size = 48, this.selecionado = false});

  @override
  Widget build(BuildContext context) {
    if (conversa.direta && conversa.peer != null) return SocialAvatar(profile: conversa.peer!, size: size);
    final cor = corDe(conversa.id);
    final raio = BorderRadius.circular(selecionado ? size * .3 : size / 2);
    Widget base(BuildContext _) => Container(
          color: cor,
          alignment: Alignment.center,
          child: conversa.tipo == TipoConversa.materia && conversa.iconPath == null
              ? Icon(Icons.school_rounded, color: Colors.white, size: size * .5)
              : Text(iniciais(conversa.nome), style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * .34)),
        );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: size,
      height: size,
      decoration: BoxDecoration(borderRadius: raio),
      clipBehavior: Clip.antiAlias,
      child: conversa.iconPath == null ? base(context) : SocialImagem(path: conversa.iconPath!, placeholder: base),
    );
  }
}

class Contador extends StatelessWidget {
  final int n;
  final bool mencao;
  const Contador(this.n, {super.key, this.mencao = true});

  @override
  Widget build(BuildContext context) {
    if (n <= 0) return const SizedBox.shrink();
    return Container(
      constraints: const BoxConstraints(minWidth: 18),
      height: 18,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: mencao ? corOcupado : Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: Theme.of(context).colorScheme.surface, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(n > 99 ? '99+' : '$n', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800, height: 1)),
    );
  }
}

class EtiquetaCargo extends StatelessWidget {
  final Cargo cargo;
  const EtiquetaCargo(this.cargo, {super.key});

  @override
  Widget build(BuildContext context) {
    if (cargo == Cargo.member) return const SizedBox.shrink();
    final cor = cargo == Cargo.owner ? corAusente : const Color(0xFF5865F2);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(color: cor.withValues(alpha: .18), borderRadius: BorderRadius.circular(4)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(cargo == Cargo.owner ? Icons.star_rounded : Icons.shield_rounded, size: 11, color: cor),
        const SizedBox(width: 2),
        Text(cargo.rotulo.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: cor, letterSpacing: .4)),
      ]),
    );
  }
}

// ------------------------------------------------------------ texto formatado
class TextoMensagem extends StatefulWidget {
  final String texto;
  final TextStyle? estilo;

  /// username → (nome para mostrar, é você?)
  final ({String nome, bool eu})? Function(String username)? resolverMencao;
  final void Function(String username)? aoTocarMencao;
  const TextoMensagem(this.texto, {super.key, this.estilo, this.resolverMencao, this.aoTocarMencao});

  @override
  State<TextoMensagem> createState() => _TextoMensagemState();
}

class _TextoMensagemState extends State<TextoMensagem> {
  final Set<int> _revelados = {};
  final List<TapGestureRecognizer> _toques = [];

  @override
  void dispose() {
    for (final t in _toques) {
      t.dispose();
    }
    super.dispose();
  }

  TapGestureRecognizer _toque(VoidCallback f) {
    final t = TapGestureRecognizer()..onTap = f;
    _toques.add(t);
    return t;
  }

  @override
  Widget build(BuildContext context) {
    for (final t in _toques) {
      t.dispose();
    }
    _toques.clear();
    final cs = Theme.of(context).colorScheme;
    final base = widget.estilo ?? DefaultTextStyle.of(context).style;
    final trechos = formatar(widget.texto);
    if (soEmojis(widget.texto)) {
      return Text(widget.texto, style: base.copyWith(fontSize: 40, height: 1.15));
    }
    final blocos = <Widget>[];
    var spans = <InlineSpan>[];
    var inicioLinha = true;

    void fecharLinha() {
      if (spans.isEmpty) return;
      blocos.add(Text.rich(TextSpan(children: spans), style: base));
      spans = [];
    }

    for (var i = 0; i < trechos.length; i++) {
      final t = trechos[i];
      if (t.bloco) {
        fecharLinha();
        blocos.add(Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6), border: Border.all(color: cs.outlineVariant)),
          child: SelectableText(t.texto, style: base.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) * .9)),
        ));
        inicioLinha = true;
        continue;
      }
      if (t.citacao && inicioLinha) {
        spans.add(TextSpan(text: '▍ ', style: base.copyWith(color: cs.outline, fontWeight: FontWeight.w900)));
      }
      inicioLinha = t.texto.endsWith('\n');
      var estilo = base.copyWith(
        color: t.citacao ? cs.onSurfaceVariant : null,
        fontWeight: t.negrito ? FontWeight.w700 : null,
        fontStyle: t.italico ? FontStyle.italic : null,
        decoration: t.riscado ? TextDecoration.lineThrough : null,
      );
      if (t.codigo) {
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(4)),
            child: Text(t.texto, style: estilo.copyWith(fontFamily: 'monospace', fontSize: (base.fontSize ?? 14) * .88)),
          ),
        ));
        continue;
      }
      if (t.spoiler && !_revelados.contains(i)) {
        spans.add(TextSpan(
          text: t.texto,
          style: estilo.copyWith(color: Colors.transparent, backgroundColor: cs.onSurface.withValues(alpha: .75)),
          recognizer: _toque(() => setState(() => _revelados.add(i))),
        ));
        continue;
      }
      if (t.spoiler) estilo = estilo.copyWith(backgroundColor: cs.onSurface.withValues(alpha: .1));
      if (t.link != null) {
        final url = t.link!;
        spans.add(TextSpan(
          text: t.texto,
          style: estilo.copyWith(color: const Color(0xFF00A8FC), decoration: TextDecoration.underline, decorationColor: const Color(0xFF00A8FC)),
          recognizer: _toque(() => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication)),
        ));
        continue;
      }
      if (t.mencao != null) {
        final r = widget.resolverMencao?.call(t.mencao!);
        final todos = t.mencao == 'everyone' || t.mencao == 'todos';
        if (r != null || todos) {
          final destaque = todos || r!.eu;
          spans.add(TextSpan(
            text: todos ? '@todos' : '@${r!.nome}',
            style: estilo.copyWith(
              color: const Color(0xFF5865F2),
              fontWeight: FontWeight.w600,
              backgroundColor: const Color(0xFF5865F2).withValues(alpha: destaque ? .3 : .15),
            ),
            recognizer: todos ? null : _toque(() => widget.aoTocarMencao?.call(t.mencao!)),
          ));
          continue;
        }
      }
      spans.add(TextSpan(text: t.texto, style: estilo));
    }
    fecharLinha();
    if (blocos.length == 1) return blocos.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: blocos);
  }
}

// ------------------------------------------------------------ utilidades de UI
void mostrarAviso(BuildContext context, Object erro) {
  if (!context.mounted) return;
  final texto = '$erro'.replaceFirst(RegExp(r'^(Exception|StateError|Bad state|FormatException): ?'), '');
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating));
}

Future<void> copiar(BuildContext context, String texto, [String aviso = 'Copiado']) async {
  await Clipboard.setData(ClipboardData(text: texto));
  if (context.mounted) mostrarAviso(context, aviso);
}

Future<bool> confirmar(BuildContext context, {required String titulo, required String texto, String botao = 'Confirmar', bool perigo = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: perigo ? FilledButton.styleFrom(backgroundColor: corOcupado, foregroundColor: Colors.white) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(botao),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<String?> pedirTexto(BuildContext context, {required String titulo, String inicial = '', String rotulo = '', int max = 64, int linhas = 1, String botao = 'Salvar', String? dica}) async {
  final c = TextEditingController(text: inicial);
  final r = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: max,
        minLines: 1,
        maxLines: linhas,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: rotulo.isEmpty ? null : rotulo, helperText: dica, helperMaxLines: 3),
        onSubmitted: linhas == 1 ? (v) => Navigator.pop(ctx, v) : null,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: Text(botao)),
      ],
    ),
  );
  c.dispose();
  return r;
}

/// Título de seção no estilo Discord ("CANAIS DE TEXTO").
class SecaoTitulo extends StatelessWidget {
  final String texto;
  final Widget? acao;
  const SecaoTitulo(this.texto, {super.key, this.acao});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 8, 6),
        child: Row(children: [
          Expanded(
            child: Text(texto.toUpperCase(),
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          ?acao,
        ]),
      );
}

class Vazio extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String texto;
  final Widget? acao;
  const Vazio({super.key, required this.icone, required this.titulo, required this.texto, this.acao});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cs.primaryContainer.withValues(alpha: .6), shape: BoxShape.circle),
            child: Icon(icone, size: 38, color: cs.primary),
          ),
          const SizedBox(height: 14),
          Text(titulo, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 6),
          Text(texto, textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
          if (acao != null) ...[const SizedBox(height: 16), acao!],
        ]),
      ),
    );
  }
}
