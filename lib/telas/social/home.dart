import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../config.dart';
import '../../fundo.dart';
import '../../plataforma.dart';
import '../../social/api.dart';
import '../../social/models.dart';
import 'amigos.dart';
import 'chat.dart';
import 'grupo.dart';
import 'painel.dart';
import 'perfil.dart';
import 'voz.dart';
import 'widgets.dart';

/// Entrada do Social: barra de grupos à esquerda (como no Discord), mensagens
/// diretas, amigos e o seu perfil.
class SocialTela extends StatefulWidget {
  /// `social:<conversa>:<canal>` vindo de uma notificação.
  final String? abrir;
  const SocialTela({super.key, this.abrir});

  static Route<void> rota({String? abrir}) => PageRouteBuilder(
        settings: const RouteSettings(name: 'social'),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (_, _, _) => SocialTela(abrir: abrir),
        transitionsBuilder: (_, a, _, child) {
          final curva = CurvedAnimation(parent: a, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
          return FadeTransition(
            opacity: curva,
            child: ScaleTransition(scale: Tween(begin: .96, end: 1.0).animate(curva), child: child),
          );
        },
      );

  @override
  State<SocialTela> createState() => _SocialTelaState();
}

class _SocialTelaState extends State<SocialTela> {
  static String? _selecionado; // null = mensagens diretas
  int _aba = 0;
  bool _recolhida = Cfg.socialListaRecolhida;

  /// Tela larga: conversa aberta ao lado da lista.
  final _chat = ValueNotifier<ChatAberto?>(null);

  /// Mesmo objeto a cada redesenho: atualizar a lista não redesenha a conversa aberta.
  late final Widget _painel = _PainelChat(_chat);

  /// A partir desta largura o Social mostra lista e conversa lado a lado.
  static const larguraPainel = 760.0;

  @override
  void dispose() {
    social.telaFechada();
    _chat.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // abrir uma conversa a partir de Amigos ou Você volta para a aba Conversas
    _chat.addListener(() {
      if (_aba != 0 && mounted) setState(() => _aba = 0);
    });
    social.telaAberta();
    unawaited(_iniciar());
  }

  Future<void> _iniciar() async {
    await social.start();
    unawaited(Notif.pedirPermissao());
    unawaited(agendar());
    final a = widget.abrir;
    if (a != null && mounted) await abrirDeNotificacao(context, a);
  }

  void _alternarLista() {
    setState(() => _recolhida = !_recolhida);
    unawaited(Cfg.setSocialListaRecolhida(_recolhida));
  }

  @override
  Widget build(BuildContext context) {
    if (!SocialApi.configured) {
      return Scaffold(appBar: AppBar(), body: const Vazio(icone: Icons.cloud_off_rounded, titulo: 'Social indisponível', texto: 'Esta versão foi compilada sem o servidor do Social.'));
    }
    final largo = MediaQuery.sizeOf(context).width >= larguraPainel;
    return CallbackShortcuts(
      bindings: {
        // Ctrl+B recolhe/mostra a lista lateral (computador)
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
          if (largo) _alternarLista();
        },
      },
      child: ListenableBuilder(
        listenable: social,
        builder: (context, _) {
          if (!social.ready) {
            return Scaffold(
              appBar: AppBar(leading: const BackButton(), title: const Text('Social')),
              body: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: social.error == null
                    ? const _Carregando(key: ValueKey('carregando'))
                    : Vazio(
                        key: const ValueKey('erro'),
                        icone: Icons.cloud_off_rounded,
                        titulo: 'Não foi possível conectar ao Social',
                        texto: social.error!,
                        acao: FilledButton(onPressed: () => social.refresh(showLoading: true), child: const Text('Tentar de novo')),
                      ),
              ),
            );
          }
          final naoLidasDm = social.conversations.where((c) => c.direta && c.notify == NotificarGrupo.tudo).fold(0, (s, c) => s + c.unread);
          final naoLidasGrupos = social.conversations.where((c) => !c.direta && c.notify != NotificarGrupo.nada).fold(0, (s, c) => s + c.mentions);
          Widget corpo = IndexedStack(index: _aba, children: [
            _Conversas(
              selecionado: _selecionado,
              aoSelecionar: (id) => setState(() => _selecionado = id),
              painel: largo ? _painel : null,
              recolhida: largo && _recolhida,
              aoAlternarLista: largo ? _alternarLista : null,
            ),
            const AmigosAba(),
            const VoceAba(),
          ]);
          if (largo) {
            // abrir uma conversa (de Amigos, por exemplo) volta para a aba Conversas
            corpo = PainelConversa(notifier: _chat, child: corpo);
          }
          return Scaffold(
            body: corpo,
            bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
              const BarraVoz(),
              NavigationBar(
              height: 64,
              selectedIndex: _aba,
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              animationDuration: const Duration(milliseconds: 380),
              onDestinationSelected: (i) {
                HapticFeedback.selectionClick();
                setState(() => _aba = i);
              },
              destinations: [
                NavigationDestination(
                  icon: Badge(isLabelVisible: naoLidasDm + naoLidasGrupos > 0, label: Text('${naoLidasDm + naoLidasGrupos}'), child: const Icon(Icons.forum_outlined)),
                  selectedIcon: const Icon(Icons.forum_rounded),
                  label: 'Conversas',
                ),
                NavigationDestination(
                  icon: Badge(isLabelVisible: social.pendingFriends > 0, label: Text('${social.pendingFriends}'), child: const Icon(Icons.people_alt_outlined)),
                  selectedIcon: const Icon(Icons.people_alt_rounded),
                  label: 'Amigos',
                ),
                NavigationDestination(
                  icon: social.me == null ? const Icon(Icons.person_outline) : SocialAvatar(profile: social.me!, size: 26),
                  label: 'Você',
                ),
              ],
            ),
            ]),
          );
        },
      ),
    );
  }
}

/// Esqueleto pulsando enquanto o Social conecta (no lugar de uma rodinha solta).
class _Carregando extends StatefulWidget {
  const _Carregando({super.key});
  @override
  State<_Carregando> createState() => _CarregandoState();
}

class _CarregandoState extends State<_Carregando> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween(begin: .35, end: .8).animate(_c),
      child: ListView(padding: const EdgeInsets.all(16), physics: const NeverScrollableScrollPhysics(), children: [
        for (var i = 0; i < 7; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              CircleAvatar(radius: 22, backgroundColor: cs.surfaceContainerHighest),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(height: 12, width: 120.0 + 20 * (i % 3), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                  const SizedBox(height: 8),
                  Container(height: 10, width: 200.0 - 25 * (i % 4), decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(6))),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

/// Abre a conversa de uma notificação (`social:<conversa>:<canal>`).
Future<void> abrirDeNotificacao(BuildContext context, String payload) async {
  final p = payload.split(':');
  if (p.length < 2) return;
  if (!social.ready) await social.refresh();
  final c = social.conversation(p[1]);
  if (c == null || !context.mounted) return;
  final canal = c.channels.where((ch) => p.length > 2 && ch.id == p[2]).firstOrNull ?? c.primeiroCanal;
  if (canal == null) return;
  await abrirChat(context, c, canal);
}

// ------------------------------------------------------------ menus de grupo e conversa
Future<void> menuDoGrupo(BuildContext context, SocialConversation c, Offset? posicao) async {
  final op = await abrirMenu<String>(context, posicao: posicao, titulo: c.nome, itens: [
    if (c.unread > 0) const ItemMenu('lido', 'Marcar como lido', icone: Icons.mark_chat_read_outlined),
    ItemMenu('notif', 'Notificações', icone: Icons.notifications_outlined, detalhe: c.notify.rotulo),
    if (c.tipo == TipoConversa.grupo) const ItemMenu('convidar', 'Convidar pessoas', icone: Icons.person_add_alt_1_rounded),
    if (c.pode(Permissao.gerenciarCanais)) const ItemMenu('canal', 'Criar canal', icone: Icons.add_rounded),
    const ItemMenu('config', 'Configurações do grupo', icone: Icons.settings_outlined),
    const ItemMenu.divisor(),
    const ItemMenu('sair', 'Sair do grupo', icone: Icons.logout_rounded, perigo: true),
  ]);
  if (op == null || !context.mounted) return;
  try {
    switch (op) {
      case 'lido':
        await social.marcarGrupoLido(c.id);
      case 'notif':
        await configurarNotificacoes(context, c);
      case 'convidar':
        await convidarPessoas(context, c.id, c.nome);
      case 'canal':
        await dialogoCanal(context, conversationId: c.id, categorias: c.categories);
      case 'config':
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrupoConfigTela(conversationId: c.id)));
      case 'sair':
        if (await confirmar(context, titulo: 'Sair de ${c.nome}?', texto: 'Para voltar, você vai precisar de um convite novo.', botao: 'Sair', perigo: true)) {
          await social.leaveGroup(c.id);
        }
    }
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e);
  }
}

Future<void> _menuDaDireta(BuildContext context, SocialConversation c, Offset? posicao) async {
  final peer = c.peer;
  final op = await abrirMenu<String>(context, posicao: posicao, titulo: c.nome, itens: [
    if (c.unread > 0) const ItemMenu('lido', 'Marcar como lida', icone: Icons.mark_chat_read_outlined),
    if (peer != null) const ItemMenu('perfil', 'Ver perfil', icone: Icons.person_outline_rounded),
    ItemMenu('silenciar', c.notify == NotificarGrupo.tudo ? 'Silenciar conversa' : 'Voltar a avisar',
        icone: c.notify == NotificarGrupo.tudo ? Icons.notifications_off_outlined : Icons.notifications_active_outlined),
    if (peer != null && peer.username.isNotEmpty) const ItemMenu('copiar', 'Copiar nome de usuário', icone: Icons.alternate_email_rounded),
  ]);
  if (op == null || !context.mounted) return;
  try {
    switch (op) {
      case 'lido':
        await social.marcarGrupoLido(c.id);
      case 'perfil':
        await mostrarPerfil(context, peer!.userKey);
      case 'silenciar':
        await social.setNotify(c.id, notify: c.notify == NotificarGrupo.tudo ? NotificarGrupo.nada : NotificarGrupo.tudo);
      case 'copiar':
        await copiar(context, '@${peer!.username}', 'Nome de usuário copiado');
    }
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e);
  }
}

// ------------------------------------------------------------ conversas
class _Conversas extends StatelessWidget {
  final String? selecionado;
  final void Function(String?) aoSelecionar;

  /// Tela larga: a conversa aberta, mostrada à direita da lista.
  final Widget? painel;
  final bool recolhida;
  final VoidCallback? aoAlternarLista;
  const _Conversas({required this.selecionado, required this.aoSelecionar, this.painel, this.recolhida = false, this.aoAlternarLista});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final atual = selecionado == null ? null : social.conversation(selecionado!);
    final selecionadoValido = atual != null && !atual.direta;
    final dms = social.conversations.where((c) => c.direta).toList();
    final lista = Container(
      color: cs.surfaceContainerLow,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: child),
        ),
        child: selecionadoValido ? _PainelGrupo(key: ValueKey(atual.id), c: atual) : _PainelDiretas(key: const ValueKey('dm'), dms: dms),
      ),
    );

    return SafeArea(
      bottom: false,
      child: Row(children: [
        _BarraGrupos(
          selecionado: selecionadoValido ? atual.id : null,
          aoSelecionar: aoSelecionar,
          recolhida: recolhida,
          aoAlternarLista: aoAlternarLista,
        ),
        if (painel == null)
          Expanded(child: lista)
        else
          AnimatedContainer(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            width: recolhida ? 0 : 300,
            child: ClipRect(child: OverflowBox(alignment: Alignment.centerLeft, minWidth: 300, maxWidth: 300, child: lista)),
          ),
        if (painel != null) ...[
          if (!recolhida) const VerticalDivider(width: 1),
          Expanded(child: painel!),
        ],
      ]),
    );
  }
}

/// Barra da esquerda com as conversas diretas e os grupos. Os grupos podem ser
/// arrastados para mudar a ordem (segurar no celular, arrastar com o mouse no computador).
class _BarraGrupos extends StatefulWidget {
  final String? selecionado;
  final void Function(String?) aoSelecionar;
  final bool recolhida;
  final VoidCallback? aoAlternarLista;
  const _BarraGrupos({required this.selecionado, required this.aoSelecionar, required this.recolhida, this.aoAlternarLista});

  @override
  State<_BarraGrupos> createState() => _BarraGruposState();
}

class _BarraGruposState extends State<_BarraGrupos> {
  int? _arrastando;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grupos = social.grupos;
    final dms = social.conversations.where((c) => c.direta).toList();
    final naoLidasDm = dms.where((c) => c.notify == NotificarGrupo.tudo).fold(0, (s, c) => s + c.unread);
    final dmSelecionado = widget.selecionado == null;
    return Container(
      width: 72,
      color: cs.surfaceContainerLowest,
      child: Column(children: [
        if (widget.aoAlternarLista != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: IconButton(
              tooltip: widget.recolhida ? 'Mostrar a lista (Ctrl+B)' : 'Recolher a lista (Ctrl+B)',
              onPressed: widget.aoAlternarLista,
              icon: AnimatedRotation(
                turns: widget.recolhida ? .5 : 0,
                duration: const Duration(milliseconds: 260),
                child: const Icon(Icons.menu_open_rounded),
              ),
            ),
          ),
        const SizedBox(height: 6),
        _ItemBarra(
          selecionado: dmSelecionado,
          naoLido: naoLidasDm > 0,
          contador: naoLidasDm,
          tooltip: 'Mensagens diretas',
          aoTocar: () => widget.aoSelecionar(null),
          construir: (hover) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: dmSelecionado || hover ? cs.primary : cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(dmSelecionado || hover ? 15 : 24),
            ),
            child: Icon(Icons.chat_bubble_rounded, color: dmSelecionado || hover ? cs.onPrimary : cs.onSurfaceVariant),
          ),
        ),
        Center(child: Container(width: 32, height: 2, margin: const EdgeInsets.symmetric(vertical: 6), color: cs.outlineVariant)),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: grupos.length,
            proxyDecorator: (child, _, a) => AnimatedBuilder(
              animation: a,
              builder: (context, c) => Transform.scale(scale: 1 + .12 * Curves.easeOut.transform(a.value), child: c),
              child: Material(color: Colors.transparent, child: child),
            ),
            onReorderStart: (i) {
              HapticFeedback.mediumImpact();
              _arrastando = i;
            },
            onReorderEnd: (i) {
              // segurou e soltou no mesmo lugar (celular): abre o menu do grupo
              final de = _arrastando;
              _arrastando = null;
              if (Plataforma.celular && de != null && (i == de || i == de + 1) && de < grupos.length) {
                unawaited(menuDoGrupo(context, grupos[de], null));
              }
            },
            onReorderItem: (de, para) {
              if (de == para) return;
              unawaited(social.moverGrupo(de, para));
            },
            footer: _ItemBarra(
              key: const ValueKey('novo-grupo'),
              selecionado: false,
              tooltip: 'Criar ou entrar em um grupo',
              aoTocar: () => _novoGrupo(context),
              construir: (hover) => AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: hover ? corOnline : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(hover ? 15 : 24)),
                child: Icon(Icons.add_rounded, color: hover ? Colors.white : corOnline, size: 28),
              ),
            ),
            itemBuilder: (context, i) {
              final g = grupos[i];
              final sel = g.id == widget.selecionado;
              final silenciado = g.notify != NotificarGrupo.tudo;
              final item = _ItemBarra(
                selecionado: sel,
                naoLido: g.notify != NotificarGrupo.nada && g.unread > 0 && !silenciado,
                contador: g.notify == NotificarGrupo.nada ? 0 : g.mentions,
                tooltip: g.nome,
                aoTocar: () => widget.aoSelecionar(g.id),
                aoMenuMouse: (pos) => menuDoGrupo(context, g, pos),
                construir: (hover) => Opacity(opacity: silenciado && !sel ? .55 : 1, child: IconeGrupo(conversa: g, selecionado: sel || hover)),
              );
              return KeyedSubtree(
                key: ValueKey(g.id),
                child: Plataforma.desktop
                    ? ReorderableDragStartListener(index: i, child: item)
                    : ReorderableDelayedDragStartListener(index: i, child: item),
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _novoGrupo(BuildContext context) async {
    final op = await abrirMenu<String>(context, titulo: 'Novo grupo', itens: const [
      ItemMenu('criar', 'Criar grupo', icone: Icons.group_add_rounded, detalhe: 'Para você e seus amigos'),
      ItemMenu('entrar', 'Entrar com convite', icone: Icons.login_rounded),
      ItemMenu('materia', 'Grupo de matéria (professor)', icone: Icons.school_outlined, detalhe: 'O AVA confirma que você é professor e adiciona a turma'),
    ]);
    if (!context.mounted) return;
    switch (op) {
      case 'criar':
        final id = await criarGrupo(context);
        if (id != null) widget.aoSelecionar(id);
      case 'entrar':
        await entrarComConvite(context);
      case 'materia':
        await criarGrupoDeMateria(context);
    }
  }
}

class _ItemBarra extends StatefulWidget {
  final bool selecionado;
  final bool naoLido;
  final int contador;
  final String tooltip;
  final VoidCallback aoTocar;
  final void Function(Offset posicao)? aoMenuMouse;
  final Widget Function(bool hover) construir;
  const _ItemBarra({
    super.key,
    required this.selecionado,
    this.naoLido = false,
    this.contador = 0,
    required this.tooltip,
    required this.aoTocar,
    this.aoMenuMouse,
    required this.construir,
  });

  @override
  State<_ItemBarra> createState() => _ItemBarraState();
}

class _ItemBarraState extends State<_ItemBarra> {
  bool _hover = false;
  bool _apertado = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(alignment: Alignment.centerLeft, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          width: 4,
          height: widget.selecionado ? 40 : (_hover ? 20 : (widget.naoLido ? 8 : 0)),
          decoration: BoxDecoration(color: cs.onSurface, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
        ),
        Center(
          child: Tooltip(
            message: widget.tooltip,
            preferBelow: false,
            waitDuration: const Duration(milliseconds: 350),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _hover = true),
              onExit: (_) => setState(() => _hover = false),
              child: GestureDetector(
                onTapDown: (_) => setState(() => _apertado = true),
                onTapCancel: () => setState(() => _apertado = false),
                onTapUp: (_) => setState(() => _apertado = false),
                onTap: () {
                  HapticFeedback.selectionClick();
                  widget.aoTocar();
                },
                onSecondaryTapUp: widget.aoMenuMouse == null ? null : (d) => widget.aoMenuMouse!(d.globalPosition),
                child: AnimatedScale(
                  scale: _apertado ? .92 : 1,
                  duration: const Duration(milliseconds: 120),
                  child: Stack(clipBehavior: Clip.none, children: [
                    widget.construir(_hover),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                        child: widget.contador > 0 ? Contador(widget.contador, key: ValueKey(widget.contador)) : const SizedBox.shrink(),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Anima a entrada só na primeira vez que o item aparece (rolar não repete).
class _SurgirUmaVez extends StatelessWidget {
  static final Set<String> _vistos = {};
  final String chave;
  final int ordem;
  final Widget child;
  const _SurgirUmaVez({required this.chave, required this.ordem, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!_vistos.add(chave)) return child;
    return Surgir(ordem: ordem, child: child);
  }
}

class _PainelDiretas extends StatefulWidget {
  final List<SocialConversation> dms;
  const _PainelDiretas({super.key, required this.dms});
  @override
  State<_PainelDiretas> createState() => _PainelDiretasState();
}

class _PainelDiretasState extends State<_PainelDiretas> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final lista = widget.dms.where((c) => _filtro.isEmpty || c.nome.toLowerCase().contains(_filtro.toLowerCase())).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
        child: Row(children: [
          const Expanded(child: Text('Mensagens', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
          IconButton(tooltip: 'Voltar ao Acadêmico', icon: const Icon(Icons.school_outlined), onPressed: () => Navigator.of(context).maybePop()),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: TextField(
          onChanged: (v) => setState(() => _filtro = v),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: 'Buscar conversas',
            filled: true,
            fillColor: cs.surfaceContainerHighest,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
      ),
      Expanded(
        child: RefreshIndicator(
          onRefresh: social.refresh,
          child: lista.isEmpty
              ? ListView(children: const [
                  SizedBox(
                    height: 380,
                    child: Vazio(icone: Icons.chat_bubble_outline_rounded, titulo: 'Nenhuma conversa ainda', texto: 'Abra o perfil de um amigo ou de alguém de um grupo e toque em Mensagem.'),
                  ),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 16),
                  itemCount: lista.length,
                  itemBuilder: (context, i) => _SurgirUmaVez(chave: 'dm:${lista[i].id}', ordem: i, child: _ItemDireta(c: lista[i])),
                ),
        ),
      ),
    ]);
  }
}

/// Na tela larga, o canal aberto ao lado fica marcado na lista.
bool _aberto(BuildContext context, String canalId) => PainelConversa.watch(context)?.value?.canal.id == canalId;

class _ItemDireta extends StatelessWidget {
  final SocialConversation c;
  const _ItemDireta({required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peer = c.peer == null ? null : social.profile(c.peer!.userKey);
    final unread = c.unread > 0 && c.notify == NotificarGrupo.tudo;
    final ch = c.primeiroCanal;
    return Tocavel(
      margem: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      selecionado: ch != null && _aberto(context, ch.id),
      aoTocar: ch == null ? null : () => abrirChat(context, c, ch),
      aoMenu: (pos) => _menuDaDireta(context, c, pos),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(children: [
          if (peer != null) SocialAvatar(profile: peer, size: 46, fundoBorda: cs.surfaceContainerLow) else IconeGrupo(conversa: c, size: 46),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: unread ? FontWeight.w800 : FontWeight.w600, fontSize: 15.5))),
                if (c.lastAt != null) Text(quandoCurto(c.lastAt!), style: TextStyle(fontSize: 11.5, color: unread ? cs.onSurface : cs.onSurfaceVariant)),
              ]),
              const SizedBox(height: 2),
              Row(children: [
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    transitionBuilder: (w, a) => FadeTransition(opacity: a, child: w),
                    child: Text(c.preview,
                        key: ValueKey(c.preview),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: unread ? cs.onSurface : cs.onSurfaceVariant, fontWeight: unread ? FontWeight.w600 : null)),
                  ),
                ),
                if (c.notify != NotificarGrupo.tudo) Icon(Icons.notifications_off_outlined, size: 15, color: cs.onSurfaceVariant),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
                  child: unread ? Contador(c.unread, key: ValueKey(c.unread)) : const SizedBox.shrink(),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ painel do grupo
/// Linha da lista de canais: título "canais de texto", categoria ou canal.
class _Entrada {
  final String chave;
  final SocialCategory? categoria;
  final SocialChannel? canal;
  final bool titulo;
  const _Entrada.titulo()
      : chave = 'titulo',
        categoria = null,
        canal = null,
        titulo = true;
  _Entrada.categoria(SocialCategory this.categoria)
      : chave = 'cat:${categoria.id}',
        canal = null,
        titulo = false;
  _Entrada.canal(SocialChannel this.canal)
      : chave = 'ch:${canal.id}',
        categoria = null,
        titulo = false;
}

class _PainelGrupo extends StatefulWidget {
  final SocialConversation c;
  const _PainelGrupo({super.key, required this.c});

  @override
  State<_PainelGrupo> createState() => _PainelGrupoState();
}

class _PainelGrupoState extends State<_PainelGrupo> {
  /// Categorias recolhidas (vale enquanto o app estiver aberto).
  static final Set<String> _recolhidas = {};
  int? _arrastando;

  SocialConversation get c => widget.c;

  List<_Entrada> _entradas() {
    final ids = {for (final k in c.categories) k.id};
    final soltos = c.channels.where((ch) => ch.categoryId == null || !ids.contains(ch.categoryId)).toList();
    return [
      if (soltos.isNotEmpty || c.categories.isEmpty) const _Entrada.titulo(),
      for (final ch in soltos) _Entrada.canal(ch),
      for (final k in c.categories) ...[
        _Entrada.categoria(k),
        for (final ch in c.channels.where((ch) => ch.categoryId == k.id))
          // recolhida: só mostra os canais com mensagem não lida (como no Discord)
          if (!_recolhidas.contains(k.id) || (ch.unread > 0 && c.notify != NotificarGrupo.nada)) _Entrada.canal(ch),
      ],
    ];
  }

  /// Depois de soltar: categoria de cada canal = a categoria acima dele; arrastar uma
  /// categoria leva os canais dela junto. Canais escondidos (categoria recolhida) ficam.
  Future<void> _soltar(List<_Entrada> antes, int de, int para) async {
    final lista = [...antes];
    final item = lista.removeAt(de);
    lista.insert(para, item);
    final ordemCats = [for (final e in lista) if (e.categoria != null) e.categoria!.id];
    final visiveis = <String>{for (final e in lista) if (e.canal != null) e.canal!.id};
    final porCategoria = <String?, List<String>>{};
    if (item.categoria != null) {
      // mudou só a ordem das categorias: canais continuam onde estavam
      for (final ch in c.channels) {
        final cat = ch.categoryId != null && ordemCats.contains(ch.categoryId) ? ch.categoryId : null;
        porCategoria.putIfAbsent(cat, () => []).add(ch.id);
      }
    } else {
      String? atual;
      for (final e in lista) {
        if (e.categoria != null) atual = e.categoria!.id;
        if (e.titulo) atual = null;
        if (e.canal != null) porCategoria.putIfAbsent(atual, () => []).add(e.canal!.id);
      }
      for (final ch in c.channels.where((ch) => !visiveis.contains(ch.id))) {
        porCategoria.putIfAbsent(ch.categoryId, () => []).add(ch.id);
      }
    }
    final canais = <({String id, String? categoria})>[
      for (final id in porCategoria[null] ?? const <String>[]) (id: id, categoria: null),
      for (final cat in ordemCats)
        for (final id in porCategoria[cat] ?? const <String>[]) (id: id, categoria: cat),
    ];
    try {
      await social.organizarCanais(c.id, ordemCats, canais);
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  Future<void> _menuCanal(SocialChannel ch, Offset? pos) async {
    final admin = c.pode(Permissao.gerenciarCanais);
    final op = await abrirMenu<String>(context, posicao: pos, titulo: ch.voz ? ch.name : '#${ch.name}', itens: [
      ch.voz
          ? ItemMenu('abrir', voz.estaEm(ch.id) ? 'Abrir a chamada' : 'Entrar na chamada', icone: Icons.call_rounded)
          : const ItemMenu('abrir', 'Abrir', icone: Icons.open_in_new_rounded),
      if (ch.unread > 0) const ItemMenu('lido', 'Marcar como lido', icone: Icons.mark_chat_read_outlined),
      ItemMenu('notif', 'Notificações do grupo', icone: Icons.notifications_outlined, detalhe: c.notify.rotulo),
      const ItemMenu('copiar', 'Copiar nome do canal', icone: Icons.copy_rounded),
      if (admin) ...[
        const ItemMenu.divisor(),
        const ItemMenu('editar', 'Editar canal', icone: Icons.edit_outlined),
        const ItemMenu('excluir', 'Excluir canal', icone: Icons.delete_outline_rounded, perigo: true),
      ],
    ]);
    if (op == null || !mounted) return;
    try {
      switch (op) {
        case 'abrir':
          await (ch.voz ? entrarNaVoz(context, c, ch) : abrirChat(context, c, ch));
        case 'lido':
          social.markChannelSeen(c.id, ch.id);
          unawaited(social.api.call('read', {'channelId': ch.id}).catchError((_) => null));
        case 'notif':
          await configurarNotificacoes(context, c);
        case 'copiar':
          await copiar(context, '#${ch.name}', 'Nome do canal copiado');
        case 'editar':
          await dialogoCanal(context, conversationId: c.id, categorias: c.categories, canal: ch);
        case 'excluir':
          if (c.channels.length <= 1) {
            mostrarAviso(context, 'O grupo precisa ter pelo menos um canal.');
          } else if (await confirmar(context,
              titulo: 'Excluir #${ch.name}?', texto: 'O canal e todas as mensagens dele serão apagados para todos. Não dá para desfazer.', botao: 'Excluir', perigo: true)) {
            await social.groupAction('delete_channel', {'channelId': ch.id});
          }
      }
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  Future<void> _menuCategoria(SocialCategory k, Offset? pos) async {
    final admin = c.pode(Permissao.gerenciarCanais);
    final recolhida = _recolhidas.contains(k.id);
    final op = await abrirMenu<String>(context, posicao: pos, titulo: k.name, itens: [
      ItemMenu('recolher', recolhida ? 'Expandir' : 'Recolher', icone: recolhida ? Icons.unfold_more_rounded : Icons.unfold_less_rounded),
      if (admin) ...[
        const ItemMenu('canal', 'Criar canal aqui', icone: Icons.add_rounded),
        const ItemMenu('renomear', 'Renomear categoria', icone: Icons.drive_file_rename_outline),
        const ItemMenu.divisor(),
        const ItemMenu('excluir', 'Excluir categoria', icone: Icons.delete_outline_rounded, perigo: true, detalhe: 'Os canais ficam, só saem da categoria'),
      ],
    ]);
    if (op == null || !mounted) return;
    try {
      switch (op) {
        case 'recolher':
          _alternar(k.id);
        case 'canal':
          await dialogoCanal(context, conversationId: c.id, categorias: c.categories, categoriaInicial: k.id);
        case 'renomear':
          final v = await pedirTexto(context, titulo: 'Renomear categoria', inicial: k.name, max: 32);
          if (v != null && v.trim().isNotEmpty) await social.groupAction('update_category', {'categoryId': k.id, 'name': v.trim()});
        case 'excluir':
          if (await confirmar(context, titulo: 'Excluir ${k.name}?', texto: 'A categoria some; os canais dela continuam no grupo.', botao: 'Excluir', perigo: true)) {
            await social.groupAction('delete_category', {'categoryId': k.id});
          }
      }
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  void _alternar(String id) => setState(() => _recolhidas.contains(id) ? _recolhidas.remove(id) : _recolhidas.add(id));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final admin = c.pode(Permissao.gerenciarCanais);
    final destaque = c.accentColor == null ? corDe(c.id) : Color(c.accentColor!);
    final entradas = _entradas();
    final cabecalho = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (c.bannerPath != null)
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrupoConfigTela(conversationId: c.id))),
          child: FundoSocial(path: c.bannerPath, cor: destaque, altura: 96),
        ),
      Tocavel(
        raio: BorderRadius.zero,
        aoTocar: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrupoConfigTela(conversationId: c.id))),
        aoMenu: (pos) => menuDoGrupo(context, c, pos),
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 4, 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [destaque.withValues(alpha: .35), Colors.transparent]),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(c.nome, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
              Builder(
                builder: (ctx) => IconButton(
                  tooltip: 'Opções do grupo',
                  icon: const Icon(Icons.expand_more_rounded),
                  onPressed: () {
                    final box = ctx.findRenderObject() as RenderBox?;
                    final pos = box?.localToGlobal(box.size.bottomLeft(Offset.zero));
                    menuDoGrupo(context, c, Plataforma.desktop ? pos : null);
                  },
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${c.memberCount} ${c.memberCount == 1 ? 'membro' : 'membros'}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              if (c.tipo == TipoConversa.materia)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: cs.tertiaryContainer, borderRadius: BorderRadius.circular(5)),
                  child: Text('MATÉRIA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.onTertiaryContainer)),
                ),
              if (c.role != Cargo.member) EtiquetaCargo(c.role),
              if (c.notify != NotificarGrupo.tudo)
                Tooltip(
                  message: c.notify.rotulo,
                  child: Icon(c.notify == NotificarGrupo.nada ? Icons.notifications_off_outlined : Icons.alternate_email_rounded, size: 15, color: cs.onSurfaceVariant),
                ),
            ]),
            if (c.description != null) ...[
              const SizedBox(height: 8),
              Text(c.description!, maxLines: 3, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
      if (c.tipo == TipoConversa.grupo)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: OutlinedButton.icon(onPressed: () => convidarPessoas(context, c.id, c.nome), icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Convidar')),
        ),
      if (!c.hasKey)
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: corAusente.withValues(alpha: .15), borderRadius: BorderRadius.circular(10)),
          child: const Text('Aguardando a chave do grupo. Ela chega quando outro membro abrir o app.', style: TextStyle(fontSize: 12.5)),
        ),
      if (admin && Plataforma.celular && c.channels.length > 1)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text('Segure um canal para arrastar ou ver as opções.', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ),
    ]);

    return RefreshIndicator(
      onRefresh: social.refresh,
      child: ReorderableListView.builder(
        header: cabecalho,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.only(bottom: 16),
        itemCount: entradas.length,
        proxyDecorator: (child, _, a) => AnimatedBuilder(
          animation: a,
          builder: (context, w) => Material(
            elevation: 8 * a.value,
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(10),
            shadowColor: Colors.black54,
            child: w,
          ),
          child: child,
        ),
        onReorderStart: (i) {
          HapticFeedback.mediumImpact();
          _arrastando = i;
        },
        onReorderEnd: (i) {
          // segurou e soltou no mesmo lugar (celular): menu do canal ou da categoria
          final de = _arrastando;
          _arrastando = null;
          if (!Plataforma.celular || de == null || !(i == de || i == de + 1) || de >= entradas.length) return;
          final e = entradas[de];
          if (e.canal != null) unawaited(_menuCanal(e.canal!, null));
          if (e.categoria != null) unawaited(_menuCategoria(e.categoria!, null));
        },
        onReorderItem: (de, para) {
          if (de == para) return;
          if (entradas[de].titulo) return;
          unawaited(_soltar(entradas, de, para));
        },
        itemBuilder: (context, i) {
          final e = entradas[i];
          Widget item;
          if (e.titulo) {
            item = SecaoTitulo(
              'Canais de texto',
              acao: admin
                  ? IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Criar canal',
                      icon: const Icon(Icons.add_rounded, size: 20),
                      onPressed: () => dialogoCanal(context, conversationId: c.id, categorias: c.categories),
                    )
                  : null,
            );
          } else if (e.categoria != null) {
            final k = e.categoria!;
            final recolhida = _recolhidas.contains(k.id);
            item = Tocavel(
              raio: BorderRadius.circular(6),
              margem: const EdgeInsets.fromLTRB(6, 10, 6, 0),
              aoTocar: () => _alternar(k.id),
              aoMenu: Plataforma.desktop || !admin ? (pos) => _menuCategoria(k, pos) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 2, 0, 2),
                child: Row(children: [
                  AnimatedRotation(
                    turns: recolhida ? -.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.expand_more_rounded, size: 16, color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(k.name.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .6, color: cs.onSurfaceVariant)),
                  ),
                  if (admin)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Criar canal em ${k.name}',
                      icon: const Icon(Icons.add_rounded, size: 18),
                      onPressed: () => dialogoCanal(context, conversationId: c.id, categorias: c.categories, categoriaInicial: k.id),
                    ),
                ]),
              ),
            );
          } else {
            final ch = e.canal!;
            item = _SurgirUmaVez(
              chave: 'ch:${ch.id}',
              ordem: i,
              child: _ItemCanal(c: c, ch: ch, aoMenu: Plataforma.desktop || !admin ? (pos) => _menuCanal(ch, pos) : null),
            );
          }
          if (!admin || e.titulo) return KeyedSubtree(key: ValueKey(e.chave), child: item);
          return KeyedSubtree(
            key: ValueKey(e.chave),
            child: Plataforma.desktop ? ReorderableDragStartListener(index: i, child: item) : ReorderableDelayedDragStartListener(index: i, child: item),
          );
        },
      ),
    );
  }
}

class _ItemCanal extends StatelessWidget {
  final SocialConversation c;
  final SocialChannel ch;
  final void Function(Offset? posicao)? aoMenu;
  const _ItemCanal({required this.c, required this.ch, this.aoMenu});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = !ch.voz && ch.unread > 0 && c.notify != NotificarGrupo.nada;
    final aberto = _aberto(context, ch.id);
    final linha = Tocavel(
      margem: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      selecionado: aberto,
      aoTocar: () => ch.voz ? entrarNaVoz(context, c, ch) : abrirChat(context, c, ch),
      aoMenu: aoMenu,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        child: Row(children: [
          Icon(ch.voz ? Icons.volume_up_rounded : (ch.onlyAdmins ? Icons.campaign_outlined : Icons.tag_rounded),
              size: 21, color: unread || aberto ? cs.onSurface : cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: unread ? FontWeight.w800 : FontWeight.w500,
                color: unread || aberto ? cs.onSurface : cs.onSurfaceVariant,
              ),
              child: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            transitionBuilder: (w, a) => ScaleTransition(scale: a, child: w),
            child: ch.mentions > 0 && c.notify != NotificarGrupo.nada
                ? Contador(ch.mentions, key: ValueKey('m${ch.mentions}'))
                : unread
                    ? Container(key: const ValueKey('ponto'), width: 8, height: 8, decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle))
                    : ch.voz && ch.userLimit != null
                        ? Text('${ch.naVoz.length}/${ch.userLimit}', key: const ValueKey('lim'), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant))
                        : const SizedBox.shrink(key: ValueKey('nada')),
          ),
        ]),
      ),
    );
    if (!ch.voz) return linha;
    return Column(mainAxisSize: MainAxisSize.min, children: [linha, PessoasDoCanal(c: c, ch: ch)]);
  }
}

/// Painel da direita na tela larga: a conversa aberta, ou um convite para escolher uma.
class _PainelChat extends StatelessWidget {
  final ValueNotifier<ChatAberto?> chat;
  const _PainelChat(this.chat);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ChatAberto?>(
      valueListenable: chat,
      builder: (context, aberto, _) {
        // a conversa pode ter sumido (saiu do grupo, foi removido)
        final c = aberto == null ? null : social.conversation(aberto.conversa.id);
        final canal = c?.channels.where((ch) => ch.id == aberto!.canal.id).firstOrNull ?? c?.primeiroCanal;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          transitionBuilder: (child, a) => FadeTransition(
            opacity: a,
            child: SlideTransition(position: Tween(begin: const Offset(0, .015), end: Offset.zero).animate(a), child: child),
          ),
          child: c == null || canal == null
              ? const Vazio(
                  key: ValueKey('vazio'),
                  icone: Icons.forum_outlined,
                  titulo: 'Nenhuma conversa aberta',
                  texto: 'Escolha um canal ou uma mensagem direta na lista ao lado.')
              : canal.voz
                  ? const VozTela(key: ValueKey('voz'))
                  : ChatTela(key: ValueKey('${c.id}:${canal.id}'), conversa: c, canal: canal),
        );
      },
    );
  }
}
