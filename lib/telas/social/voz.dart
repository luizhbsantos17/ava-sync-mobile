import 'dart:async';

import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' show MediaDevice, ScreenSelectDialog, VideoTrack, VideoTrackRenderer, VideoViewFit;
import 'package:material_ui/material_ui.dart';

import '../../plataforma.dart';
import '../../social/models.dart';
import '../../social/voz.dart';
import 'painel.dart';
import 'perfil.dart';
import 'widgets.dart';

VozController get voz => VozController.instance;

/// Entra no canal de voz e mostra a chamada (ao lado na tela larga, ou numa tela nova).
Future<void> entrarNaVoz(BuildContext context, SocialConversation c, SocialChannel ch) async {
  final painel = PainelConversa.maybeOf(context);
  final nav = Navigator.of(context);
  if (!voz.estaEm(ch.id)) {
    HapticFeedback.mediumImpact();
    try {
      await voz.entrar(c, ch);
    } catch (e) {
      if (context.mounted) mostrarAviso(context, voz.erro ?? e);
      return;
    }
  }
  if (painel != null) {
    painel.value = ChatAberto(c, ch);
  } else {
    await nav.push(MaterialPageRoute(builder: (_) => const VozTela()));
  }
}

String _duracao(DateTime? desde) {
  if (desde == null) return '';
  final d = DateTime.now().difference(desde);
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  String dd(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${dd(m)}:${dd(s)}' : '${dd(m)}:${dd(s)}';
}

/// Barra fixa "Conectado à voz" (como a do Discord): aparece em todo o Social
/// enquanto a chamada está ativa.
class BarraVoz extends StatelessWidget {
  const BarraVoz({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: voz,
      builder: (context, _) {
        final ativa = voz.ativa;
        return AnimatedSize(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: !ativa
              ? const SizedBox(width: double.infinity)
              : Material(
                  color: cs.surfaceContainerHigh,
                  child: InkWell(
                    onTap: () {
                      final c = voz.conversa, ch = voz.canal;
                      if (c != null && ch != null) entrarNaVoz(context, c, ch);
                    },
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                      child: Row(children: [
                        _Sinal(estado: voz.estado),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                            Text(
                              switch (voz.estado) {
                                EstadoVoz.conectando => 'Conectando…',
                                EstadoVoz.reconectando => 'Reconectando…',
                                _ => 'Voz conectada',
                              },
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: voz.estado == EstadoVoz.conectado ? corOnline : corAusente,
                              ),
                            ),
                            _Relogio(
                              texto: () => '${voz.canal?.name ?? ''} / ${voz.conversa?.nome ?? ''}  ${_duracao(voz.desde)}',
                              estilo: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                            ),
                          ]),
                        ),
                        _BotaoRedondo(
                          icone: voz.mudo ? Icons.mic_off_rounded : Icons.mic_rounded,
                          dica: voz.mudo ? 'Ligar microfone' : 'Desligar microfone',
                          vermelho: voz.mudo,
                          aoTocar: voz.alternarMudo,
                        ),
                        _BotaoRedondo(
                          icone: voz.surdo ? Icons.headset_off_rounded : Icons.headset_rounded,
                          dica: voz.surdo ? 'Voltar a ouvir' : 'Ensurdecer (não ouvir ninguém)',
                          vermelho: voz.surdo,
                          aoTocar: voz.alternarSurdo,
                        ),
                        _BotaoRedondo(icone: Icons.call_end_rounded, dica: 'Sair da chamada', vermelho: true, cheio: true, aoTocar: voz.sair),
                      ]),
                    ),
                  ),
                ),
        );
      },
    );
  }
}

/// Texto que se atualiza a cada segundo (duração da chamada) sem redesenhar a tela toda.
class _Relogio extends StatefulWidget {
  final String Function() texto;
  final TextStyle estilo;
  const _Relogio({required this.texto, required this.estilo});
  @override
  State<_Relogio> createState() => _RelogioState();
}

class _RelogioState extends State<_Relogio> {
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text(widget.texto(), maxLines: 1, overflow: TextOverflow.ellipsis, style: widget.estilo);
}

class _Sinal extends StatelessWidget {
  final EstadoVoz estado;
  const _Sinal({required this.estado});

  @override
  Widget build(BuildContext context) {
    final cor = estado == EstadoVoz.conectado ? corOnline : corAusente;
    return Icon(estado == EstadoVoz.conectado ? Icons.graphic_eq_rounded : Icons.sync_rounded, color: cor, size: 22);
  }
}

class _BotaoRedondo extends StatelessWidget {
  final IconData icone;
  final String dica;
  final bool vermelho;
  final bool cheio;
  final bool ativo;
  final double tamanho;
  final FutureOr<void> Function() aoTocar;
  const _BotaoRedondo({
    required this.icone,
    required this.dica,
    required this.aoTocar,
    this.vermelho = false,
    this.cheio = false,
    this.ativo = false,
    this.tamanho = 40,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fundo = cheio
        ? corOcupado
        : ativo
            ? cs.primary
            : vermelho
                ? corOcupado.withValues(alpha: .15)
                : Colors.transparent;
    final cor = cheio ? Colors.white : (ativo ? cs.onPrimary : (vermelho ? corOcupado : cs.onSurfaceVariant));
    return Tooltip(
      message: dica,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: fundo,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              HapticFeedback.selectionClick();
              aoTocar();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: tamanho,
              height: tamanho,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: Icon(icone, key: ValueKey(icone), color: cor, size: tamanho * .5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pessoas num canal de voz, embaixo do canal na lista (como no Discord).
class PessoasDoCanal extends StatelessWidget {
  final SocialConversation c;
  final SocialChannel ch;
  const PessoasDoCanal({super.key, required this.c, required this.ch});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voz,
      builder: (context, _) {
        // no canal em que estou, a lista vem ao vivo da chamada (com quem está falando)
        final aoVivo = voz.estaEm(ch.id) ? voz.pessoas : null;
        final itens = aoVivo != null
            ? [for (final p in aoVivo) (key: p.userKey, falando: p.falando, mudo: p.mudo, surdo: p.surdo, video: p.camera != null, tela: p.tela != null)]
            : [for (final p in ch.naVoz) (key: p.userKey, falando: false, mudo: p.muted, surdo: p.deafened, video: p.video, tela: p.screen)];
        if (itens.isEmpty) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;
        return Padding(
          padding: const EdgeInsets.only(left: 34, right: 8, bottom: 4),
          child: Column(children: [
            for (final p in itens)
              Tocavel(
                aoTocar: () => mostrarPerfil(context, p.key),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  child: Row(children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.falando ? corOnline : Colors.transparent, width: 2)),
                      child: SocialAvatar(profile: social.profile(p.key), size: 22, presenca: false),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(social.profile(p.key).displayName,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.5, color: p.falando ? cs.onSurface : cs.onSurfaceVariant)),
                    ),
                    if (p.tela) const _Etiqueta('AO VIVO', corOcupado),
                    if (p.video) Icon(Icons.videocam_rounded, size: 15, color: cs.onSurfaceVariant),
                    if (p.mudo) Icon(Icons.mic_off_rounded, size: 15, color: corOcupado.withValues(alpha: .9)),
                    if (p.surdo) Icon(Icons.headset_off_rounded, size: 15, color: corOcupado.withValues(alpha: .9)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }
}

class _Etiqueta extends StatelessWidget {
  final String texto;
  final Color cor;
  const _Etiqueta(this.texto, this.cor);
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(right: 4),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(4)),
        child: Text(texto, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: .4)),
      );
}

// ------------------------------------------------------------ tela da chamada
class VozTela extends StatefulWidget {
  const VozTela({super.key});
  @override
  State<VozTela> createState() => _VozTelaState();
}

class _VozTelaState extends State<VozTela> {
  /// Quem está em destaque (vídeo grande). Null = escolhe sozinho (quem compartilha a tela).
  String? _foco;

  // ignore: experimental_member_use
  Future<String?> _escolherTela() => ScreenSelectDialog.show(
        context,
        titleText: 'O que você quer compartilhar?',
        screenTabText: 'Tela inteira',
        windowTabText: 'Janela',
        cancelText: 'Cancelar',
        shareText: 'Compartilhar',
      );

  Future<void> _menuPessoa(PessoaNaVoz p, Offset? pos) async {
    final c = voz.conversa;
    final podeTirar = c != null && !p.eu && c.pode(Permissao.expulsar);
    final op = await abrirMenu<String>(context, posicao: pos, titulo: p.nome, itens: [
      const ItemMenu('perfil', 'Ver perfil', icone: Icons.person_outline_rounded),
      if (p.camera != null || p.tela != null) ItemMenu('foco', _foco == p.userKey ? 'Tirar do destaque' : 'Pôr em destaque', icone: Icons.fullscreen_rounded),
      if (!p.eu) const ItemMenu('volume', 'Volume desta pessoa', icone: Icons.volume_up_rounded),
      if (podeTirar) ...[const ItemMenu.divisor(), const ItemMenu('tirar', 'Desconectar da chamada', icone: Icons.call_end_rounded, perigo: true)],
    ]);
    if (op == null || !mounted) return;
    switch (op) {
      case 'perfil':
        await mostrarPerfil(context, p.userKey);
      case 'foco':
        setState(() => _foco = _foco == p.userKey ? null : p.userKey);
      case 'volume':
        await _volume(p);
      case 'tirar':
        try {
          await voz.desconectar(p.userKey);
        } catch (e) {
          if (mounted) mostrarAviso(context, e);
        }
    }
  }

  Future<void> _volume(PessoaNaVoz p) async {
    var v = voz.volumes[p.userKey] ?? 1.0;
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Volume de ${p.nome}'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Slider(
              value: v,
              max: 2,
              divisions: 20,
              label: '${(v * 100).round()}%',
              onChanged: (x) {
                set(() => v = x);
                unawaited(voz.definirVolume(p.userKey, x));
              },
            ),
            Text('${(v * 100).round()}% (só neste aparelho)'),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Pronto'))],
        ),
      ),
    );
  }

  Future<void> _dispositivos() async {
    final mics = await voz.microfones();
    final saidas = await voz.saidas();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const SecaoTitulo('Microfone'),
          for (final d in mics) _Dispositivo(d: d, aoEscolher: () => voz.usarMicrofone(d), icone: Icons.mic_none_rounded),
          const SecaoTitulo('Saída de som'),
          for (final d in saidas) _Dispositivo(d: d, aoEscolher: () => voz.usarSaida(d), icone: Icons.speaker_rounded),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: voz,
      builder: (context, _) {
        final ch = voz.canal;
        if (!voz.ativa || ch == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Vazio(
              icone: Icons.call_end_rounded,
              titulo: voz.erro ?? 'Você saiu da chamada',
              texto: 'Entre de novo pelo canal de voz na lista.',
            ),
          );
        }
        final pessoas = voz.pessoas;
        final focoId = _foco ?? pessoas.where((p) => p.tela != null).firstOrNull?.userKey;
        final foco = pessoas.where((p) => p.userKey == focoId).firstOrNull;
        final outros = foco == null ? pessoas : [for (final p in pessoas) if (p.userKey != foco.userKey) p];
        return Scaffold(
          backgroundColor: Color.lerp(cs.surface, Colors.black, .55),
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Row(children: [
              const Icon(Icons.volume_up_rounded, size: 22),
              const SizedBox(width: 6),
              Flexible(child: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              const Tooltip(message: 'Áudio e vídeo cifrados de ponta a ponta', child: Icon(Icons.lock_rounded, size: 16, color: corOnline)),
            ]),
            actions: [
              if (Plataforma.desktop) IconButton(tooltip: 'Microfone e saída de som', icon: const Icon(Icons.settings_voice_rounded), onPressed: _dispositivos),
            ],
          ),
          body: Column(children: [
            if (voz.estado != EstadoVoz.conectado)
              LinearProgressIndicator(minHeight: 2, color: corAusente, backgroundColor: Colors.transparent),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: foco == null
                    ? _Grade(pessoas: pessoas, aoMenu: _menuPessoa, aoTocar: (p) => setState(() => _foco = p.userKey))
                    : Column(children: [
                        Expanded(
                          child: _Quadro(
                            p: foco,
                            grande: true,
                            aoMenu: (pos) => _menuPessoa(foco, pos),
                            aoTocar: () => setState(() => _foco = null),
                          ),
                        ),
                        if (outros.isNotEmpty)
                          SizedBox(
                            height: 110,
                            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(top: 8), children: [
                              for (final p in outros)
                                SizedBox(
                                  width: 160,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: _Quadro(p: p, aoMenu: (pos) => _menuPessoa(p, pos), aoTocar: () => setState(() => _foco = p.userKey)),
                                  ),
                                ),
                            ]),
                          ),
                      ]),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 14),
                child: Wrap(alignment: WrapAlignment.center, spacing: 10, runSpacing: 10, children: [
                  _BotaoRedondo(
                    tamanho: 54,
                    icone: voz.mudo ? Icons.mic_off_rounded : Icons.mic_rounded,
                    dica: voz.mudo ? 'Ligar microfone' : 'Desligar microfone',
                    vermelho: voz.mudo,
                    aoTocar: voz.alternarMudo,
                  ),
                  _BotaoRedondo(
                    tamanho: 54,
                    icone: voz.surdo ? Icons.headset_off_rounded : Icons.headset_rounded,
                    dica: voz.surdo ? 'Voltar a ouvir' : 'Ensurdecer',
                    vermelho: voz.surdo,
                    aoTocar: voz.alternarSurdo,
                  ),
                  _BotaoRedondo(
                    tamanho: 54,
                    icone: voz.cameraLigada ? Icons.videocam_rounded : Icons.videocam_off_rounded,
                    dica: voz.cameraLigada ? 'Desligar câmera' : 'Ligar câmera',
                    ativo: voz.cameraLigada,
                    aoTocar: voz.alternarCamera,
                  ),
                  _BotaoRedondo(
                    tamanho: 54,
                    icone: voz.telaLigada ? Icons.stop_screen_share_rounded : Icons.screen_share_rounded,
                    dica: voz.telaLigada ? 'Parar de compartilhar' : 'Compartilhar a tela',
                    ativo: voz.telaLigada,
                    aoTocar: () => voz.alternarTela(_escolherTela),
                  ),
                  _BotaoRedondo(
                    tamanho: 54,
                    icone: Icons.call_end_rounded,
                    dica: 'Sair da chamada',
                    cheio: true,
                    aoTocar: () async {
                      final nav = Navigator.of(context);
                      final painel = PainelConversa.maybeOf(context);
                      await voz.sair();
                      if (painel == null && nav.canPop()) nav.pop();
                    },
                  ),
                ]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Dispositivo extends StatelessWidget {
  final MediaDevice d;
  final Future<void> Function() aoEscolher;
  final IconData icone;
  const _Dispositivo({required this.d, required this.aoEscolher, required this.icone});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icone),
        title: Text(d.label.isEmpty ? 'Dispositivo' : d.label),
        onTap: () async {
          await aoEscolher();
          if (context.mounted) Navigator.pop(context);
        },
      );
}

class _Grade extends StatelessWidget {
  final List<PessoaNaVoz> pessoas;
  final Future<void> Function(PessoaNaVoz, Offset?) aoMenu;
  final void Function(PessoaNaVoz) aoTocar;
  const _Grade({required this.pessoas, required this.aoMenu, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final n = pessoas.length.clamp(1, 99);
      // colunas para que os quadros fiquem o maior possível
      var colunas = 1;
      var melhor = 0.0;
      for (var k = 1; k <= n; k++) {
        final linhas = (n / k).ceil();
        final w = (c.maxWidth - 8 * (k - 1)) / k;
        final h = (c.maxHeight - 8 * (linhas - 1)) / linhas;
        final lado = w * 9 / 16 < h ? w : h * 16 / 9;
        if (lado > melhor) {
          melhor = lado;
          colunas = k;
        }
      }
      final linhas = (n / colunas).ceil();
      final altura = ((c.maxHeight - 8 * (linhas - 1)) / linhas).clamp(80.0, 600.0);
      return SingleChildScrollView(
        child: Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          for (final (i, p) in pessoas.indexed)
            Surgir(
              ordem: i,
              child: SizedBox(
                width: (c.maxWidth - 8 * (colunas - 1)) / colunas,
                height: altura,
                child: _Quadro(p: p, aoMenu: (pos) => aoMenu(p, pos), aoTocar: () => aoTocar(p)),
              ),
            ),
        ]),
      );
    });
  }
}

/// Quadro de uma pessoa: vídeo (tela ou câmera) ou a foto, com anel verde quando fala.
class _Quadro extends StatelessWidget {
  final PessoaNaVoz p;
  final bool grande;
  final void Function(Offset?) aoMenu;
  final VoidCallback aoTocar;
  const _Quadro({required this.p, required this.aoMenu, required this.aoTocar, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final VideoTrack? video = p.tela ?? p.camera;
    final perfil = social.profile(p.userKey);
    return GestureDetector(
      onTap: aoTocar,
      onLongPress: () => aoMenu(null),
      onSecondaryTapUp: (d) => aoMenu(d.globalPosition),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        decoration: BoxDecoration(
          color: Color.lerp(corDe(p.userKey), Colors.black, .55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.falando ? corOnline : Colors.transparent, width: 3),
          boxShadow: p.falando ? [BoxShadow(color: corOnline.withValues(alpha: .45), blurRadius: 14)] : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(fit: StackFit.expand, children: [
          if (video != null)
            VideoTrackRenderer(video, fit: p.tela != null ? VideoViewFit.contain : VideoViewFit.cover)
          else
            Center(
              child: AnimatedScale(
                scale: p.falando ? 1 + (p.nivel * .25).clamp(0, .15) : 1,
                duration: const Duration(milliseconds: 120),
                child: SocialAvatar(profile: perfil, size: grande ? 110 : 64, presenca: false),
              ),
            ),
          Positioned(
            left: 8,
            bottom: 8,
            right: 8,
            child: Row(children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (p.mudo) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.mic_off_rounded, size: 14, color: corOcupado)),
                    if (p.surdo) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.headset_off_rounded, size: 14, color: corOcupado)),
                    Flexible(
                      child: Text(p.eu ? '${p.nome} (você)' : p.nome,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  ]),
                ),
              ),
              if (p.tela != null) ...[const SizedBox(width: 6), const _Etiqueta('AO VIVO', corOcupado)],
            ]),
          ),
        ]),
      ),
    );
  }
}
