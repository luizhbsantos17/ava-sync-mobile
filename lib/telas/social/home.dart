import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../fundo.dart';
import '../../social/api.dart';
import '../../social/models.dart';
import 'amigos.dart';
import 'chat.dart';
import 'grupo.dart';
import 'painel.dart';
import 'perfil.dart';
import 'widgets.dart';

/// Entrada do Social: barra de grupos à esquerda (como no Discord), mensagens
/// diretas, amigos e o seu perfil.
class SocialTela extends StatefulWidget {
  /// `social:<conversa>:<canal>` vindo de uma notificação.
  final String? abrir;
  const SocialTela({super.key, this.abrir});

  static Route<void> rota({String? abrir}) =>
      MaterialPageRoute(settings: const RouteSettings(name: 'social'), builder: (_) => SocialTela(abrir: abrir));

  @override
  State<SocialTela> createState() => _SocialTelaState();
}

class _SocialTelaState extends State<SocialTela> {
  static String? _selecionado; // null = mensagens diretas
  int _aba = 0;

  /// Tela larga: conversa aberta ao lado da lista.
  final _chat = ValueNotifier<ChatAberto?>(null);

  /// A partir desta largura o Social mostra lista e conversa lado a lado.
  static const larguraPainel = 760.0;

  @override
  void dispose() {
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
    unawaited(_iniciar());
  }

  Future<void> _iniciar() async {
    await social.start();
    unawaited(Notif.pedirPermissao());
    unawaited(agendar());
    final a = widget.abrir;
    if (a != null && mounted) await abrirDeNotificacao(context, a);
  }

  @override
  Widget build(BuildContext context) {
    if (!SocialApi.configured) {
      return Scaffold(appBar: AppBar(), body: const Vazio(icone: Icons.cloud_off_rounded, titulo: 'Social indisponível', texto: 'Esta versão foi compilada sem o servidor do Social.'));
    }
    return ListenableBuilder(
      listenable: social,
      builder: (context, _) {
        if (!social.ready) {
          return Scaffold(
            appBar: AppBar(leading: const BackButton(), title: const Text('Social')),
            body: social.error == null
                ? const Center(child: CircularProgressIndicator())
                : Vazio(
                    icone: Icons.cloud_off_rounded,
                    titulo: 'Não foi possível conectar ao Social',
                    texto: social.error!,
                    acao: FilledButton(onPressed: () => social.refresh(showLoading: true), child: const Text('Tentar de novo')),
                  ),
          );
        }
        final naoLidasDm = social.conversations.where((c) => c.direta && !c.muted).fold(0, (s, c) => s + c.unread);
        final naoLidasGrupos = social.conversations.where((c) => !c.direta && !c.muted).fold(0, (s, c) => s + c.mentions);
        final largo = MediaQuery.sizeOf(context).width >= larguraPainel;
        Widget corpo = IndexedStack(index: _aba, children: [
          _Conversas(
            selecionado: _selecionado,
            aoSelecionar: (id) => setState(() => _selecionado = id),
            painel: largo ? _PainelChat(_chat) : null,
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
          bottomNavigationBar: NavigationBar(
            height: 64,
            selectedIndex: _aba,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
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
        );
      },
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

class _Conversas extends StatelessWidget {
  final String? selecionado;
  final void Function(String?) aoSelecionar;

  /// Tela larga: a conversa aberta, mostrada à direita da lista.
  final Widget? painel;
  const _Conversas({required this.selecionado, required this.aoSelecionar, this.painel});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grupos = social.conversations.where((c) => !c.direta).toList();
    final atual = selecionado == null ? null : social.conversation(selecionado!);
    final selecionadoValido = atual != null && !atual.direta;
    final dms = social.conversations.where((c) => c.direta).toList();
    final naoLidasDm = dms.where((c) => !c.muted).fold(0, (s, c) => s + c.unread);
    final lista = Container(
      color: cs.surfaceContainerLow,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: selecionadoValido ? _PainelGrupo(key: ValueKey(atual.id), c: atual) : _PainelDiretas(key: const ValueKey('dm'), dms: dms),
      ),
    );

    return SafeArea(
      bottom: false,
      child: Row(children: [
        Container(
          width: 72,
          color: cs.surfaceContainerLowest,
          child: ListView(padding: const EdgeInsets.only(top: 8, bottom: 16), children: [
            _ItemBarra(
              selecionado: !selecionadoValido,
              naoLido: naoLidasDm > 0,
              contador: naoLidasDm,
              tooltip: 'Mensagens diretas',
              aoTocar: () => aoSelecionar(null),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: !selecionadoValido ? cs.primary : cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(!selecionadoValido ? 15 : 24)),
                child: Icon(Icons.chat_bubble_rounded, color: !selecionadoValido ? cs.onPrimary : cs.onSurfaceVariant),
              ),
            ),
            Center(child: Container(width: 32, height: 2, margin: const EdgeInsets.symmetric(vertical: 6), color: cs.outlineVariant)),
            for (final g in grupos)
              _ItemBarra(
                selecionado: g.id == selecionado,
                naoLido: !g.muted && g.unread > 0,
                contador: g.muted ? 0 : g.mentions,
                tooltip: g.nome,
                aoTocar: () => aoSelecionar(g.id),
                child: Opacity(opacity: g.muted ? .55 : 1, child: IconeGrupo(conversa: g, selecionado: g.id == selecionado)),
              ),
            _ItemBarra(
              selecionado: false,
              tooltip: 'Criar ou entrar em um grupo',
              aoTocar: () => _novoGrupo(context),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: cs.surfaceContainerHigh, shape: BoxShape.circle),
                child: const Icon(Icons.add_rounded, color: corOnline, size: 28),
              ),
            ),
          ]),
        ),
        if (painel == null) Expanded(child: lista) else SizedBox(width: 300, child: lista),
        if (painel != null) ...[const VerticalDivider(width: 1), Expanded(child: painel!)],
      ]),
    );
  }

  Future<void> _novoGrupo(BuildContext context) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.group_add_rounded), title: const Text('Criar grupo'), subtitle: const Text('Para você e seus amigos'), onTap: () => Navigator.pop(ctx, 'criar')),
          ListTile(leading: const Icon(Icons.login_rounded), title: const Text('Entrar com convite'), onTap: () => Navigator.pop(ctx, 'entrar')),
          ListTile(
            leading: const Icon(Icons.school_outlined),
            title: const Text('Grupo de matéria (professor)'),
            subtitle: const Text('O AVA confirma que você é professor e adiciona a turma'),
            onTap: () => Navigator.pop(ctx, 'materia'),
          ),
        ]),
      ),
    );
    if (!context.mounted) return;
    switch (op) {
      case 'criar':
        final id = await criarGrupo(context);
        if (id != null) aoSelecionar(id);
      case 'entrar':
        await entrarComConvite(context);
      case 'materia':
        await criarGrupoDeMateria(context);
    }
  }
}

class _ItemBarra extends StatelessWidget {
  final bool selecionado;
  final bool naoLido;
  final int contador;
  final String tooltip;
  final VoidCallback aoTocar;
  final Widget child;
  const _ItemBarra({required this.selecionado, this.naoLido = false, this.contador = 0, required this.tooltip, required this.aoTocar, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Stack(alignment: Alignment.centerLeft, children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 4,
          height: selecionado ? 40 : (naoLido ? 8 : 0),
          decoration: BoxDecoration(color: cs.onSurface, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
        ),
        Center(
          child: Tooltip(
            message: tooltip,
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                aoTocar();
              },
              child: Stack(clipBehavior: Clip.none, children: [
                child,
                if (contador > 0) Positioned(right: -4, bottom: -4, child: Contador(contador)),
              ]),
            ),
          ),
        ),
      ]),
    );
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
                  itemBuilder: (context, i) => _ItemDireta(c: lista[i]),
                ),
        ),
      ),
    ]);
  }
}

class _ItemDireta extends StatelessWidget {
  final SocialConversation c;
  const _ItemDireta({required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final peer = c.peer == null ? null : social.profile(c.peer!.userKey);
    final unread = c.unread > 0 && !c.muted;
    return InkWell(
      onTap: () {
        final ch = c.primeiroCanal;
        if (ch != null) abrirChat(context, c, ch);
      },
      onLongPress: peer == null ? null : () => mostrarPerfil(context, peer.userKey),
      onSecondaryTap: peer == null ? null : () => mostrarPerfil(context, peer.userKey),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                  child: Text(c.preview, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: unread ? cs.onSurface : cs.onSurfaceVariant, fontWeight: unread ? FontWeight.w600 : null)),
                ),
                if (c.muted) Icon(Icons.notifications_off_outlined, size: 15, color: cs.onSurfaceVariant),
                if (unread) Contador(c.unread),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _PainelGrupo extends StatelessWidget {
  final SocialConversation c;
  const _PainelGrupo({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final admin = c.role.gerencia;
    return RefreshIndicator(
      onRefresh: social.refresh,
      child: ListView(padding: EdgeInsets.zero, children: [
        InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrupoConfigTela(conversationId: c.id))),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [corDe(c.id).withValues(alpha: .35), Colors.transparent]),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(c.nome, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800))),
                const Icon(Icons.chevron_right_rounded),
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
                if (c.muted) Icon(Icons.notifications_off_outlined, size: 15, color: cs.onSurfaceVariant),
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
        SecaoTitulo(
          'Canais de texto',
          acao: admin
              ? IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: 'Criar canal',
                  icon: const Icon(Icons.add_rounded, size: 20),
                  onPressed: () async {
                    final nome = await pedirTexto(context, titulo: 'Criar canal', rotulo: 'Nome do canal', max: 32, botao: 'Criar');
                    if (nome == null || nome.trim().isEmpty) return;
                    try {
                      await social.groupAction('create_channel', {'conversationId': c.id, 'name': nome});
                    } catch (e) {
                      if (context.mounted) mostrarAviso(context, e);
                    }
                  },
                )
              : null,
        ),
        for (final ch in c.channels) _ItemCanal(c: c, ch: ch),
        const SizedBox(height: 16),
      ]),
    );
  }
}

class _ItemCanal extends StatelessWidget {
  final SocialConversation c;
  final SocialChannel ch;
  const _ItemCanal({required this.c, required this.ch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unread = ch.unread > 0 && !c.muted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => abrirChat(context, c, ch),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
            child: Row(children: [
              Icon(ch.onlyAdmins ? Icons.campaign_outlined : Icons.tag_rounded, size: 21, color: unread ? cs.onSurface : cs.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(ch.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15.5, fontWeight: unread ? FontWeight.w800 : FontWeight.w500, color: unread ? cs.onSurface : cs.onSurfaceVariant)),
              ),
              if (ch.mentions > 0 && !c.muted) Contador(ch.mentions) else if (unread) Container(width: 8, height: 8, decoration: BoxDecoration(color: cs.onSurface, shape: BoxShape.circle)),
            ]),
          ),
        ),
      ),
    );
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
        if (c == null || canal == null) {
          return const Vazio(
              icone: Icons.forum_outlined,
              titulo: 'Nenhuma conversa aberta',
              texto: 'Escolha um canal ou uma mensagem direta na lista ao lado.');
        }
        return ChatTela(key: ValueKey('${c.id}:${canal.id}'), conversa: c, canal: canal);
      },
    );
  }
}
