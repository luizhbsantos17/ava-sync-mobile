import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../config.dart';
import '../../social/feed.dart';
import '../../social/formatacao.dart';
import '../../social/models.dart';
import '../../plataforma.dart';
import '../../salvar.dart';
import 'painel.dart';
import 'emojis.dart';
import 'grupo.dart';
import 'perfil.dart';
import 'widgets.dart';

class ChatTela extends StatefulWidget {
  final SocialConversation conversa;
  final SocialChannel canal;
  const ChatTela({super.key, required this.conversa, required this.canal});

  @override
  State<ChatTela> createState() => _ChatTelaState();
}

class _AnexoPendente {
  final String nome;
  final Uint8List bytes;
  SocialAttachment? pronto;
  bool falhou = false;
  _AnexoPendente(this.nome, this.bytes);
  bool get imagem => RegExp(r'\.(png|jpe?g|gif|webp|heic)$', caseSensitive: false).hasMatch(nome);
}

class _ChatTelaState extends State<ChatTela> with WidgetsBindingObserver {
  late final ChannelFeed feed;
  final _texto = TextEditingController();
  late final _foco = FocusNode(onKeyEvent: _tecla);
  final _scroll = ScrollController();
  SocialGroupInfo? _info;
  SocialMessage? _respondendo;
  SocialMessage? _editando;
  final List<_AnexoPendente> _anexos = [];
  bool _longeDoFim = false;
  int _novasAbaixo = 0;
  int _ultimoTotal = 0;
  Set<String>? _vistasNaAbertura;
  String? _destaque;
  List<SocialMember> _sugestoes = const [];
  List<SocialRole> _sugestoesCargo = const [];
  bool _sugTodos = false;

  /// Muda quando as sugestões de @menção mudam: só a caixa de sugestões redesenha
  /// (digitar não redesenha a conversa inteira).
  final _sugMudou = ValueNotifier<int>(0);

  /// Chave de cada mensagem, para rolar até ela (não lidas, menções, resposta).
  final Map<String, GlobalKey> _chaves = {};
  GlobalKey _chave(String id) => _chaves.putIfAbsent(id, GlobalKey.new);
  final _chaveNovas = GlobalKey();

  /// Ao abrir: quantas não lidas havia e até quando eu tinha lido.
  late int _naoLidasAbertura = widget.canal.unread;
  late final DateTime? _lidoAte = widget.canal.lastReadAt;
  late bool _bannerNovas = widget.canal.unread > 0;
  final Set<String> _mencoesVistas = {};
  bool _pulando = false;
  bool _membrosLado = Cfg.socialMembrosVisiveis;

  SocialConversation get conversa => social.conversation(widget.conversa.id) ?? widget.conversa;
  String get _me => social.me?.userKey ?? '';
  /// Permissão neste grupo: pelo cargo (dono/admin têm todas) ou pelos cargos personalizados.
  bool _pode(Permissao p) => _info?.pode(p) ?? conversa.pode(p);
  bool get _podeEscrever => !widget.canal.onlyAdmins || _pode(Permissao.enviarAvisos);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    feed = ChannelFeed(social, widget.conversa, widget.canal)..addListener(_mudou);
    social.activeChannelId = widget.canal.id;
    _texto.text = social.draft(widget.canal.id);
    _texto.addListener(_digitando);
    _scroll.addListener(_rolou);
    unawaited(feed.open());
    unawaited(_carregarInfo());
  }

  Future<void> _carregarInfo() async {
    try {
      final i = await social.groupInfo(widget.conversa.id);
      if (mounted) setState(() => _info = i);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      social.activeChannelId = widget.canal.id;
      feed.resume();
      feed.markRead(force: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      feed.pause();
      if (social.activeChannelId == widget.canal.id) social.activeChannelId = null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(social.saveDraft(widget.canal.id, _editando == null ? _texto.text : ''));
    if (social.activeChannelId == widget.canal.id) social.activeChannelId = null;
    if (_texto.text.isNotEmpty) feed.typingNow(active: false);
    // a leitura é limitada a uma a cada 3 s: ao sair, marca de novo para não ficar
    // "não lida" a última mensagem que chegou com a conversa aberta (fora do build)
    final conversa = widget.conversa.id, canal = widget.canal.id;
    Future(() {
      social.markChannelSeen(conversa, canal);
      unawaited(social.api.call('read', {'channelId': canal}).catchError((_) => null));
    });
    feed.removeListener(_mudou);
    feed.dispose();
    _texto.dispose();
    _foco.dispose();
    _scroll.dispose();
    _sugMudou.dispose();
    super.dispose();
  }

  void _mudou() {
    if (!mounted) return;
    final total = feed.messages.length;
    if (_vistasNaAbertura == null && !feed.loading) _vistasNaAbertura = {for (final m in feed.messages) m.id};
    if (total > _ultimoTotal && _longeDoFim && _ultimoTotal > 0) {
      final novas = feed.messages.sublist(_ultimoTotal.clamp(0, total)).where((m) => m.senderId != _me).length;
      _novasAbaixo += novas;
    }
    _ultimoTotal = total;
    setState(() {});
  }

  void _rolou() {
    final longe = _scroll.hasClients && _scroll.offset > 400;
    if (longe != _longeDoFim) setState(() => _longeDoFim = longe);
    if (!longe && _novasAbaixo > 0) setState(() => _novasAbaixo = 0);
    if (_scroll.hasClients && _scroll.position.pixels > _scroll.position.maxScrollExtent - 600) unawaited(feed.loadOlder());
    // a linha "Novas mensagens" apareceu na tela: some o aviso do topo
    if (_bannerNovas && _naTela(_chaveNovas)) setState(() => _bannerNovas = false);
  }

  bool _naTela(GlobalKey k) {
    final box = k.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return false;
    final y = box.localToGlobal(Offset.zero).dy;
    return y > 0 && y < MediaQuery.sizeOf(context).height - 80;
  }

  /// Primeira mensagem que eu ainda não tinha lido quando abri o canal.
  SocialMessage? get _primeiraNaoLida {
    if (_naoLidasAbertura <= 0) return null;
    final lido = _lidoAte;
    if (lido != null) {
      for (final m in feed.messages) {
        if (m.senderId != _me && m.createdAt.isAfter(lido)) return m;
      }
      return null;
    }
    final desde = feed.unreadSince;
    if (desde == null) return null;
    for (final m in feed.messages) {
      if (m.createdAt == desde) return m;
    }
    return null;
  }

  bool _marcaMe(SocialMessage m) {
    if (m.senderId == _me || m.deleted) return false;
    final cargos = _info?.member(_me)?.roleIds ?? conversa.myRoles;
    if (m.mentions.contains(_me)) return true;
    if (!conversa.suppressEveryone && m.mentions.contains('everyone')) return true;
    return !conversa.suppressRoles && cargos.any((r) => m.mentions.contains('role:$r'));
  }

  /// Menções a mim que chegaram depois da última leitura e ainda não visitei.
  List<SocialMessage> get _mencoesPendentes => [
        for (final m in feed.messages)
          if (_marcaMe(m) && (_lidoAte == null || m.createdAt.isAfter(_lidoAte)) && !_mencoesVistas.contains(m.id)) m,
      ];

  int get _qtdMencoes {
    final carregadas = _mencoesPendentes.length;
    final doServidor = widget.canal.mentions - _mencoesVistas.length;
    return carregadas > doServidor ? carregadas : doServidor.clamp(0, 999);
  }

  /// Rola (carregando mensagens antigas se precisar) até a mensagem e pisca ela.
  Future<void> _irPara(String id) async {
    if (_pulando) return;
    _pulando = true;
    try {
      for (var volta = 0; volta < 60 && mounted; volta++) {
        final ctx = _chaves[id]?.currentContext;
        if (ctx != null && ctx.mounted) {
          await Scrollable.ensureVisible(ctx, alignment: .35, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
          if (!mounted) return;
          setState(() => _destaque = id);
          Future<void>.delayed(const Duration(milliseconds: 1600), () {
            if (mounted && _destaque == id) setState(() => _destaque = null);
          });
          return;
        }
        if (!_scroll.hasClients) return;
        final pos = _scroll.position;
        if (pos.pixels >= pos.maxScrollExtent - 4) {
          if (!feed.hasMore) return;
          await feed.loadOlder();
        } else {
          await _scroll.animateTo((pos.pixels + pos.viewportDimension * .85).clamp(0, pos.maxScrollExtent),
              duration: const Duration(milliseconds: 90), curve: Curves.linear);
        }
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      _pulando = false;
    }
  }

  Future<void> _pularParaNaoLidas() async {
    for (var i = 0; i < 10 && _primeiraNaoLida == null && feed.hasMore && mounted; i++) {
      await feed.loadOlder();
    }
    final alvo = _primeiraNaoLida;
    if (alvo != null) await _irPara(alvo.id);
    if (mounted) setState(() => _bannerNovas = false);
  }

  Future<void> _pularParaMencao() async {
    for (var i = 0; i < 10 && _mencoesPendentes.isEmpty && _qtdMencoes > 0 && feed.hasMore && mounted; i++) {
      await feed.loadOlder();
    }
    final lista = _mencoesPendentes;
    if (lista.isEmpty) {
      setState(() => _mencoesVistas.add('_fim_${_mencoesVistas.length}'));
      return;
    }
    final alvo = lista.first; // a mais antiga primeiro
    setState(() => _mencoesVistas.add(alvo.id));
    await _irPara(alvo.id);
  }

  void _limparSugestoes() {
    _sugestoes = const [];
    _sugestoesCargo = const [];
    _sugTodos = false;
    _sugMudou.value++;
  }

  /// Computador: Enter envia, Shift+Enter quebra linha, Esc cancela, ↑ edita a última.
  KeyEventResult _tecla(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed || !Plataforma.desktop) return KeyEventResult.ignored;
      if (_sugTodos) {
        _inserirApelido('todos');
      } else if (_sugestoesCargo.isNotEmpty) {
        _inserirApelido(apelidoCargo(_sugestoesCargo.first.name));
      } else if (_sugestoes.isNotEmpty) {
        _inserirMencao(_sugestoes.first);
      } else {
        unawaited(_enviar());
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape) {
      if (_sugestoes.isNotEmpty || _sugestoesCargo.isNotEmpty || _sugTodos) {
        _limparSugestoes();
      } else if (_editando != null) {
        setState(() => _editando = null);
        _texto.clear();
      } else if (_respondendo != null) {
        setState(() => _respondendo = null);
      } else {
        return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp && _texto.text.isEmpty && _editando == null) {
      for (final m in feed.messages.reversed) {
        if (m.senderId == _me && !m.deleted && !m.locked && m.localId == null && m.text.isNotEmpty) {
          _editar(m);
          return KeyEventResult.handled;
        }
      }
    }
    return KeyEventResult.ignored;
  }

  void _irParaFim() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(0, duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
    setState(() => _novasAbaixo = 0);
  }

  Map<String, String> get _usernames => {
        for (final r in _cargosMarcaveis) apelidoCargo(r.name): 'role:${r.id}',
        for (final m in _info?.members ?? const <SocialMember>[])
          if (m.profile.username.isNotEmpty) m.profile.username.toLowerCase(): m.userKey,
      };

  List<SocialRole> get _cargosMarcaveis {
    final i = _info;
    if (i == null || conversa.direta) return const [];
    final todos = i.pode(Permissao.mencionarTodos);
    return [for (final r in i.roles) if (r.mentionable || todos) r];
  }

  ({String nome, bool eu})? _resolver(String username) {
    final i = _info;
    if (i != null) {
      for (final r in i.roles) {
        if (apelidoCargo(r.name) == username) return (nome: r.name, eu: i.member(_me)?.roleIds.contains(r.id) ?? false);
      }
    }
    for (final m in _info?.members ?? const <SocialMember>[]) {
      if (m.profile.username.toLowerCase() == username) return (nome: m.nome, eu: m.userKey == _me);
    }
    return null;
  }

  void _abrirPerfilPorUsername(String username) {
    final key = _usernames[username];
    if (key != null) unawaited(mostrarPerfil(context, key, grupo: _info, mudou: _carregarInfo));
  }

  // ------------------------------------------------------------ digitar e enviar
  void _digitando() {
    final t = _texto.text;
    if (t.trim().isNotEmpty && _editando == null) feed.typingNow();
    // sugestões de @menção
    final sel = _texto.selection.baseOffset;
    final antes = sel >= 0 && sel <= t.length ? t.substring(0, sel) : t;
    final m = RegExp(r'(^|\s)@([a-zA-Z0-9_.]{0,24})$').firstMatch(antes);
    List<SocialMember> sug = const [];
    List<SocialRole> sugCargo = const [];
    var todos = false;
    if (m != null && !conversa.direta && (_info?.pode(Permissao.mencionarTodos) ?? conversa.pode(Permissao.mencionarTodos))) {
      final q = m.group(2)!.toLowerCase();
      todos = const ['todos', 'all', 'everyone'].any((x) => x.startsWith(q));
    }
    if (m != null && _info != null) {
      final q = m.group(2)!.toLowerCase();
      sug = _info!.members
          .where((x) => x.userKey != _me && (x.profile.username.contains(q) || x.nome.toLowerCase().contains(q)))
          .take(6)
          .toList();
      sugCargo = _cargosMarcaveis.where((r) => apelidoCargo(r.name).contains(q) || r.name.toLowerCase().contains(q)).take(4).toList();
    }
    final mudou = sug.length != _sugestoes.length || sugCargo.length != _sugestoesCargo.length || todos != _sugTodos ||
        (sug.isNotEmpty && sug.first.userKey != _sugestoes.first.userKey);
    _sugestoes = sug;
    _sugestoesCargo = sugCargo;
    _sugTodos = todos;
    if (mudou) _sugMudou.value++;
  }

  void _inserirMencao(SocialMember m) => _inserirApelido(m.profile.username);

  void _inserirApelido(String apelido) {
    final t = _texto.text;
    final sel = _texto.selection.baseOffset.clamp(0, t.length);
    final antes = t.substring(0, sel);
    final depois = t.substring(sel);
    final novo = antes.replaceFirst(RegExp(r'@[a-zA-Z0-9_.]*$'), '@$apelido ');
    _texto.value = TextEditingValue(text: novo + depois, selection: TextSelection.collapsed(offset: novo.length));
    _limparSugestoes();
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (_editando != null) {
      final m = _editando!;
      setState(() => _editando = null);
      _texto.clear();
      if (texto.isEmpty || texto == m.text) return;
      try {
        await feed.edit(m, texto, usernames: _usernames);
      } catch (e) {
        if (mounted) mostrarAviso(context, e);
      }
      return;
    }
    if (_anexos.any((a) => a.pronto == null && !a.falhou)) {
      mostrarAviso(context, 'Espere os anexos terminarem de enviar.');
      return;
    }
    final prontos = [for (final a in _anexos) ?a.pronto];
    if (texto.isEmpty && prontos.isEmpty) return;
    if (texto.length > 4000) {
      mostrarAviso(context, 'A mensagem passa de 4000 caracteres.');
      return;
    }
    HapticFeedback.lightImpact();
    final reply = _respondendo?.id;
    setState(() {
      _respondendo = null;
      _anexos.clear();
    });
    _limparSugestoes();
    _bannerNovas = false;
    _naoLidasAbertura = 0;
    _texto.clear();
    unawaited(social.saveDraft(widget.canal.id, ''));
    _irParaFim();
    await feed.send(texto, attachments: prontos, replyTo: reply, usernames: _usernames);
    if (feed.error != null && mounted && feed.messages.any((m) => m.estado == EstadoEnvio.falhou)) mostrarAviso(context, feed.error!);
  }

  Future<void> _anexar(bool foto) async {
    final arquivos = await FilePicker.pickFiles(dialogTitle: foto ? 'Fotos' : 'Arquivos', type: foto ? FileType.image : FileType.any);
    for (final f in arquivos.take(10 - _anexos.length)) {
      final bytes = await f.readAsBytes();
      if (bytes.length > 20 * 1024 * 1024) {
        if (mounted) mostrarAviso(context, '${f.name} é grande demais (máximo 8 MB).');
        continue;
      }
      final a = _AnexoPendente(f.name, bytes);
      setState(() => _anexos.add(a));
      unawaited(_subir(a));
    }
  }

  Future<void> _subir(_AnexoPendente a) async {
    try {
      a.pronto = await social.uploadAttachment(widget.conversa.id, a.nome, a.bytes);
    } catch (e) {
      a.falhou = true;
      if (mounted) mostrarAviso(context, e);
    }
    if (mounted) setState(() {});
  }

  void _responder(SocialMessage m) {
    HapticFeedback.selectionClick();
    setState(() {
      _respondendo = m;
      _editando = null;
    });
    _foco.requestFocus();
  }

  void _editar(SocialMessage m) {
    setState(() {
      _editando = m;
      _respondendo = null;
    });
    _texto.text = m.text;
    _texto.selection = TextSelection.collapsed(offset: m.text.length);
    _foco.requestFocus();
  }

  // ------------------------------------------------------------ menu da mensagem
  Future<void> _menu(SocialMessage m, [Offset? posicao]) async {
    if (m.deleted || m.localId != null) {
      if (m.estado == EstadoEnvio.falhou) await _menuFalha(m);
      return;
    }
    final mine = m.senderId == _me;
    final podeApagar = mine || (_pode(Permissao.apagarMensagens) && !conversa.direta);
    final podeFixar = conversa.direta || _pode(Permissao.fixar);
    final cs = Theme.of(context).colorScheme;
    final op = await abrirMenu<String>(
      context,
      posicao: posicao,
      topo: m.locked
          ? null
          : Builder(
              builder: (ctx) => Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                  for (final (i, e) in socialRecentes.take(6).indexed)
                    Surgir(
                      ordem: i,
                      deslocamento: 6,
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(ctx, 'r:$e'),
                        child: CircleAvatar(radius: 22, backgroundColor: cs.surfaceContainerHighest, child: Text(e, style: const TextStyle(fontSize: 22))),
                      ),
                    ),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.pop(ctx, 'mais'),
                    child: CircleAvatar(radius: 22, backgroundColor: cs.surfaceContainerHighest, child: const Icon(Icons.add_reaction_outlined)),
                  ),
                ]),
              ),
            ),
      itens: [
        if (posicao != null && !m.locked) const ItemMenu('mais', 'Adicionar reação', icone: Icons.add_reaction_outlined),
        if (_podeEscrever && !m.locked) const ItemMenu('responder', 'Responder', icone: Icons.reply_rounded),
        if (mine && !m.locked && m.text.isNotEmpty) const ItemMenu('editar', 'Editar mensagem', icone: Icons.edit_outlined),
        if (m.text.isNotEmpty) const ItemMenu('copiar', 'Copiar texto', icone: Icons.copy_rounded),
        if (_podeEscrever && !m.locked && !mine && !conversa.direta) const ItemMenu('mencionar', 'Mencionar', icone: Icons.alternate_email_rounded),
        if (podeFixar && !m.locked) ItemMenu('fixar', m.pinnedAt == null ? 'Fixar mensagem' : 'Desafixar', icone: m.pinnedAt == null ? Icons.push_pin_outlined : Icons.push_pin),
        if (!mine) const ItemMenu('perfil', 'Ver perfil', icone: Icons.person_outline_rounded),
        if (podeApagar) ...[const ItemMenu.divisor(), const ItemMenu('apagar', 'Apagar mensagem', icone: Icons.delete_outline_rounded, perigo: true)],
      ],
    );
    if (!mounted || op == null) return;
    try {
      if (op.startsWith('r:')) {
        await feed.toggleReaction(m, op.substring(2));
      } else {
        switch (op) {
          case 'mais':
            final e = await escolherEmoji(context);
            if (e != null) await feed.toggleReaction(m, e);
          case 'responder':
            _responder(m);
          case 'editar':
            _editar(m);
          case 'copiar':
            await copiar(context, m.text, 'Mensagem copiada');
          case 'mencionar':
            final u = social.profile(m.senderId).username;
            if (u.isNotEmpty) {
              final t = _texto.text;
              _texto.value = TextEditingValue(text: '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@$u ', selection: TextSelection.collapsed(offset: '${t.isEmpty || t.endsWith(' ') ? t : '$t '}@$u '.length));
              _foco.requestFocus();
            }
          case 'fixar':
            await feed.pin(m, m.pinnedAt == null);
            if (mounted) mostrarAviso(context, m.pinnedAt == null ? 'Mensagem fixada' : 'Mensagem desafixada');
          case 'perfil':
            await mostrarPerfil(context, m.senderId, grupo: _info, mudou: _carregarInfo);
          case 'apagar':
            if (await confirmar(context, titulo: 'Apagar mensagem', texto: 'Apagar para todos? Isso não pode ser desfeito.', botao: 'Apagar', perigo: true)) {
              await feed.delete(m);
            }
        }
      }
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  List<String> get socialRecentes => {...Cfg.socialEmojisRecentes, '👍', '❤️', '😂', '😮', '😢', '🔥'}.toList();

  Future<void> _menuFalha(SocialMessage m) async {
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.refresh_rounded), title: const Text('Tentar enviar de novo'), onTap: () => Navigator.pop(ctx, 'retry')),
          ListTile(leading: const Icon(Icons.delete_outline_rounded), title: const Text('Descartar'), onTap: () => Navigator.pop(ctx, 'discard')),
        ]),
      ),
    );
    if (op == 'retry') await feed.retry(m, usernames: _usernames);
    if (op == 'discard') feed.discard(m);
  }

  // ------------------------------------------------------------ barras e painéis
  Future<void> _trocarCanal() async {
    final c = conversa;
    if (c.direta || c.channels.length < 2) return;
    final canal = await showModalBottomSheet<SocialChannel>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          SecaoTitulo(c.nome),
          for (final ch in c.channels.where((ch) => !ch.voz))
            ListTile(
              leading: Icon(ch.onlyAdmins ? Icons.campaign_outlined : Icons.tag_rounded),
              title: Text(ch.name, style: TextStyle(fontWeight: ch.unread > 0 ? FontWeight.w800 : FontWeight.w500)),
              subtitle: ch.topic == null ? null : Text(ch.topic!, maxLines: 1, overflow: TextOverflow.ellipsis),
              selected: ch.id == widget.canal.id,
              trailing: Contador(ch.mentions > 0 ? ch.mentions : ch.unread, mencao: ch.mentions > 0),
              onTap: () => Navigator.pop(ctx, ch),
            ),
        ]),
      ),
    );
    if (canal != null && canal.id != widget.canal.id && mounted) {
      await abrirChat(context, c, canal, trocandoCanal: true);
    }
  }

  Future<void> _fixadas() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SizedBox(
        height: MediaQuery.sizeOf(ctx).height * .7,
        child: FutureBuilder<List<SocialMessage>>(
          future: feed.pins(),
          builder: (ctx, s) {
            if (!s.hasData) return Center(child: s.hasError ? Text('${s.error}') : const CircularProgressIndicator());
            if (s.data!.isEmpty) {
              return const Vazio(icone: Icons.push_pin_outlined, titulo: 'Nenhuma mensagem fixada', texto: 'Mensagens importantes fixadas aparecem aqui.');
            }
            return ListView(children: [
              const SecaoTitulo('Mensagens fixadas'),
              for (final m in s.data!) _CartaoMensagem(m: m, resolver: _resolver, conversationId: widget.conversa.id),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _buscar() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _Busca(feed: feed, resolver: _resolver, conversationId: widget.conversa.id),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = conversa;
    final peer = c.peer;
    final largo = MediaQuery.sizeOf(context).width >= 1100;
    final membrosAoLado = largo && !c.direta && _membrosLado;
    final coluna = Column(children: [
      AnimatedSize(
        duration: const Duration(milliseconds: 200),
        child: feed.offline
            ? Container(
                width: double.infinity,
                color: corAusente,
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: const Text('Reconectando…', textAlign: TextAlign.center, style: TextStyle(color: Colors.black, fontWeight: FontWeight.w700, fontSize: 12)),
              )
            : const SizedBox(width: double.infinity),
      ),
      if (!c.hasKey && !feed.loading)
        MaterialBanner(
          leading: const Icon(Icons.key_off_rounded),
          content: const Text('Este aparelho ainda não tem a chave desta conversa. Ela chega sozinha quando outro membro abrir o app, ou entre de novo com um convite.'),
          actions: [TextButton(onPressed: () => social.refresh(), child: const Text('Verificar'))],
        ),
      Expanded(child: Stack(children: [_lista(cs), _avisoNovas(cs), _botaoFim(cs)])),
      _digitandoAgora(cs),
      _compositor(cs),
    ]);
    return Scaffold(
      endDrawer: c.direta || largo ? null : _Membros(info: _info, recarregar: _carregarInfo),
      appBar: AppBar(
        titleSpacing: 0,
        title: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: c.direta ? (peer == null ? null : () => mostrarPerfil(context, peer.userKey, grupo: _info)) : _trocarCanal,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(children: [
              if (c.direta && peer != null) ...[SocialAvatar(profile: social.profile(peer.userKey), size: 34, fundoBorda: cs.surface), const SizedBox(width: 10)],
              if (!c.direta) Icon(widget.canal.onlyAdmins ? Icons.campaign_outlined : Icons.tag_rounded, size: 22, color: cs.onSurfaceVariant),
              if (!c.direta) const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    Flexible(child: Text(c.direta ? c.nome : widget.canal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                    if (!c.direta && c.channels.length > 1) const Icon(Icons.expand_more_rounded, size: 20),
                  ]),
                  Text(
                    c.direta
                        ? (peer == null ? '' : _linhaStatus(social.profile(peer.userKey)))
                        : (widget.canal.topic ?? c.nome),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        actions: [
          IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search_rounded), onPressed: _buscar),
          IconButton(tooltip: 'Mensagens fixadas', icon: const Icon(Icons.push_pin_outlined), onPressed: _fixadas),
          if (!c.direta)
            Builder(
              builder: (ctx) => IconButton(
                tooltip: 'Membros',
                isSelected: membrosAoLado,
                icon: const Icon(Icons.people_alt_outlined),
                selectedIcon: const Icon(Icons.people_alt_rounded),
                onPressed: () {
                  if (largo) {
                    setState(() => _membrosLado = !_membrosLado);
                    unawaited(Cfg.setSocialMembrosVisiveis(_membrosLado));
                  } else {
                    Scaffold.of(ctx).openEndDrawer();
                  }
                },
              ),
            ),
          if (!c.direta)
            IconButton(
              tooltip: 'Notificações',
              icon: Icon(switch (c.notify) {
                NotificarGrupo.tudo => Icons.notifications_outlined,
                NotificarGrupo.mencoes => Icons.alternate_email_rounded,
                NotificarGrupo.nada => Icons.notifications_off_outlined,
              }),
              onPressed: () => configurarNotificacoes(context, c),
            ),
          if (!c.direta)
            IconButton(
              tooltip: 'Configurações do grupo',
              icon: const Icon(Icons.more_vert_rounded),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(builder: (_) => GrupoConfigTela(conversationId: c.id)));
                await _carregarInfo();
              },
            ),
        ],
      ),
      body: !largo || c.direta
          ? coluna
          : Row(children: [
              Expanded(child: coluna),
              AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: membrosAoLado ? 251 : 0,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.centerLeft,
                    minWidth: 251,
                    maxWidth: 251,
                    child: Row(children: [
                      const VerticalDivider(width: 1),
                      SizedBox(width: 250, child: Material(color: cs.surfaceContainerLow, child: _ListaMembros(info: _info, recarregar: _carregarInfo))),
                    ]),
                  ),
                ),
              ),
            ]),
    );
  }

  /// "N mensagens novas desde 14:32 · Pular": volta até onde parei de ler.
  Widget _avisoNovas(ColorScheme cs) {
    final mostrar = _bannerNovas && !feed.loading && _naoLidasAbertura > 0;
    final desde = _lidoAte;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !mostrar,
        child: AnimatedSlide(
          offset: mostrar ? Offset.zero : const Offset(0, -1),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: mostrar ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: Material(
              color: cs.primary,
              child: InkWell(
                onTap: _pularParaNaoLidas,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(children: [
                    Expanded(
                      child: Text(
                        '${_naoLidasAbertura > 99 ? '99+' : _naoLidasAbertura} ${_naoLidasAbertura == 1 ? 'mensagem nova' : 'mensagens novas'}'
                        '${desde == null ? '' : ' desde ${mesmoDia(desde, DateTime.now()) ? hora(desde) : quando(desde)}'}',
                        style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: cs.onPrimary, visualDensity: VisualDensity.compact),
                      onPressed: _pularParaNaoLidas,
                      icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                      label: const Text('Pular'),
                    ),
                    IconButton(
                      tooltip: 'Marcar como lido',
                      visualDensity: VisualDensity.compact,
                      color: cs.onPrimary,
                      icon: const Icon(Icons.done_all_rounded, size: 18),
                      onPressed: () => setState(() => _bannerNovas = false),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _linhaStatus(SocialProfile p) {
    if (p.customStatus != null || p.customEmoji != null) return p.statusLinha;
    return p.online ? p.presence.rotulo : visto(p.lastSeen);
  }

  Widget _botaoFim(ColorScheme cs) {
    final mencoes = feed.loading ? 0 : _qtdMencoes;
    return Positioned(
      right: 12,
      bottom: 12,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
        AnimatedScale(
          scale: mencoes > 0 ? 1 : 0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Tooltip(
              message: 'Ir para a menção a você',
              child: Material(
                color: corOcupado,
                shape: const StadiumBorder(),
                elevation: 3,
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: _pularParaMencao,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.alternate_email_rounded, size: 17, color: Colors.white),
                      const SizedBox(width: 4),
                      Text('$mencoes', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedScale(
          scale: _longeDoFim ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          child: Badge(
            isLabelVisible: _novasAbaixo > 0,
            label: Text('$_novasAbaixo'),
            child: FloatingActionButton.small(heroTag: null, onPressed: _irParaFim, child: const Icon(Icons.keyboard_double_arrow_down_rounded)),
          ),
        ),
      ]),
    );
  }

  Widget _lista(ColorScheme cs) {
    if (feed.loading) return const Center(child: CircularProgressIndicator());
    final msgs = feed.messages;
    if (msgs.isEmpty) {
      final c = conversa;
      return ListView(reverse: true, padding: const EdgeInsets.all(20), children: [
        if (feed.error != null) Text(feed.error!, textAlign: TextAlign.center, style: const TextStyle(color: corOcupado)),
        _Boas(conversa: c, canal: widget.canal),
      ]);
    }
    final itens = msgs.reversed.toList();
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      itemCount: itens.length + 1,
      itemBuilder: (context, i) {
        if (i == itens.length) {
          if (feed.hasMore) return const Padding(padding: EdgeInsets.all(16), child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))));
          return _Boas(conversa: conversa, canal: widget.canal);
        }
        final m = itens[i];
        final anterior = i + 1 < itens.length ? itens[i + 1] : null;
        final novoDia = anterior == null || !mesmoDia(anterior.createdAt, m.createdAt);
        final linhaNovas = m.id == _primeiraNaoLida?.id;
        final continua = !novoDia &&
            !linhaNovas &&
            anterior.senderId == m.senderId &&
            m.replyTo == null &&
            !anterior.deleted &&
            m.createdAt.difference(anterior.createdAt).inMinutes < 7;
        final animar = _vistasNaAbertura != null && !_vistasNaAbertura!.contains(m.id) && (m.localId != null || i < 3);
        Widget item = _Mensagem(
          key: ValueKey(m.localId ?? m.id),
          m: m,
          continua: continua,
          resposta: m.replyTo == null ? null : feed.find(m.replyTo!),
          me: _me,
          info: _info,
          destaque: _destaque == m.id,
          resolver: _resolver,
          aoTocarMencao: _abrirPerfilPorUsername,
          aoMenu: (pos) => _menu(m, pos),
          aoResponder: _podeEscrever && !m.deleted && !m.locked && m.localId == null ? () => _responder(m) : null,
          aoReagir: (e) => feed.toggleReaction(m, e),
          aoTocarAutor: () => mostrarPerfil(context, m.senderId, grupo: _info, mudou: _carregarInfo),
          aoTocarResposta: () {
            if (m.replyTo != null) unawaited(_irPara(m.replyTo!));
          },
          aoTentarDeNovo: () => _menuFalha(m),
        );
        if (animar) item = _Entrada(child: item);
        return KeyedSubtree(
          key: _chave(m.localId ?? m.id),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            if (novoDia) _Divisor(texto: dia(m.createdAt)),
            if (linhaNovas) _Divisor(key: _chaveNovas, texto: 'Novas mensagens', novas: true),
            RepaintBoundary(child: item),
          ]),
        );
      },
    );
  }

  Widget _digitandoAgora(ColorScheme cs) {
    final nomes = [for (final k in feed.typing) _info?.member(k)?.nome ?? social.profile(k).displayName];
    final texto = switch (nomes.length) {
      0 => '',
      1 => '${nomes[0]} está digitando…',
      2 => '${nomes[0]} e ${nomes[1]} estão digitando…',
      3 => '${nomes[0]}, ${nomes[1]} e ${nomes[2]} estão digitando…',
      _ => 'Várias pessoas estão digitando…',
    };
    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      child: nomes.isEmpty
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
              child: Row(children: [
                const _Pontinhos(),
                const SizedBox(width: 8),
                Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
              ]),
            ),
    );
  }

  Widget _compositor(ColorScheme cs) {
    if (!_podeEscrever) {
      return SafeArea(
        top: false,
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
          child: Text('Só administradores podem enviar mensagens em #${widget.canal.name}.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
      );
    }
    final dica = conversa.direta ? 'Mensagem para ${conversa.nome}' : 'Conversar em #${widget.canal.name}';
    final barra = _editando != null
        ? _BarraAcima(icone: Icons.edit_outlined, texto: 'Editando mensagem', aoFechar: () {
            setState(() => _editando = null);
            _texto.clear();
          })
        : _respondendo != null
            ? _BarraAcima(
                icone: Icons.reply_rounded,
                texto: 'Respondendo a ${_info?.member(_respondendo!.senderId)?.nome ?? social.profile(_respondendo!.senderId).displayName}',
                aoFechar: () => setState(() => _respondendo = null),
              )
            : null;
    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ValueListenableBuilder<int>(
            valueListenable: _sugMudou,
            builder: (context, _, _) => AnimatedSize(
              duration: const Duration(milliseconds: 160),
              curve: Curves.easeOutCubic,
              alignment: Alignment.bottomCenter,
              child: !(_sugestoes.isNotEmpty || _sugestoesCargo.isNotEmpty || _sugTodos)
                  ? const SizedBox(width: double.infinity)
                  : Container(
              constraints: const BoxConstraints(maxHeight: 260),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
              child: ListView(shrinkWrap: true, padding: EdgeInsets.zero, children: [
                if (_sugTodos) ...[
                  const SecaoTitulo('Todo mundo'),
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.groups_rounded, color: corAusente),
                    title: const Text('@todos'),
                    subtitle: const Text('Avisa todos do grupo (também funciona @all)'),
                    onTap: () => _inserirApelido('todos'),
                  ),
                ],
                if (_sugestoesCargo.isNotEmpty) const SecaoTitulo('Cargos'),
                for (final r in _sugestoesCargo)
                  ListTile(
                    dense: true,
                    leading: Icon(Icons.shield_rounded, color: r.color == null ? null : Color(r.color!)),
                    title: Text(r.name),
                    trailing: Text('@${apelidoCargo(r.name)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    onTap: () => _inserirApelido(apelidoCargo(r.name)),
                  ),
                if (_sugestoes.isNotEmpty) const SecaoTitulo('Membros'),
                for (final m in _sugestoes)
                  ListTile(
                    dense: true,
                    leading: SocialAvatar(profile: m.profile, size: 30, fundoBorda: cs.surfaceContainerLow),
                    title: Text(m.nome),
                    trailing: Text('@${m.profile.username}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                    onTap: () => _inserirMencao(m),
                  ),
              ]),
            ),
            ),
          ),
          ?barra,
          if (_anexos.isNotEmpty)
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 0), children: [
                for (final a in _anexos) _MiniaturaAnexo(a: a, aoRemover: () => setState(() => _anexos.remove(a))),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              if (_editando == null)
                IconButton(
                  tooltip: 'Anexar',
                  icon: Icon(Icons.add_circle_rounded, color: cs.onSurfaceVariant, size: 28),
                  onPressed: !conversa.hasKey
                      ? null
                      : () async {
                          final op = await showModalBottomSheet<bool>(
                            context: context,
                            showDragHandle: true,
                            builder: (ctx) => SafeArea(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                                ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Fotos'), onTap: () => Navigator.pop(ctx, true)),
                                ListTile(leading: const Icon(Icons.attach_file_rounded), title: const Text('Arquivo'), subtitle: const Text('PDF, documentos… até 8 MB'), onTap: () => Navigator.pop(ctx, false)),
                              ]),
                            ),
                          );
                          if (op != null) await _anexar(op);
                        },
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(22)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Expanded(
                      child: TextField(
                        controller: _texto,
                        focusNode: _foco,
                        enabled: conversa.hasKey,
                        minLines: 1,
                        maxLines: 6,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        decoration: InputDecoration(
                          hintText: Plataforma.desktop ? '$dica  (Enter envia, Shift+Enter pula linha)' : dica,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: const EdgeInsets.fromLTRB(16, 11, 4, 11),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Emoji',
                      icon: Icon(Icons.emoji_emotions_outlined, color: cs.onSurfaceVariant),
                      onPressed: () async {
                        final e = await escolherEmoji(context);
                        if (e == null) return;
                        final t = _texto.text;
                        final sel = _texto.selection.isValid ? _texto.selection.baseOffset : t.length;
                        final novo = t.substring(0, sel) + e + t.substring(sel);
                        _texto.value = TextEditingValue(text: novo, selection: TextSelection.collapsed(offset: sel + e.length));
                        unawaited(social.useEmoji(e));
                      },
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 4),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _texto,
                builder: (context, valor, _) => AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, a) => ScaleTransition(scale: a, child: RotationTransition(turns: Tween(begin: -.1, end: 0.0).animate(a), child: child)),
                child: valor.text.trim().isNotEmpty || _anexos.any((a) => a.pronto != null) || _editando != null
                    ? IconButton.filled(
                        key: const ValueKey('enviar'),
                        tooltip: _editando != null ? 'Salvar' : 'Enviar',
                        onPressed: _enviar,
                        icon: Icon(_editando != null ? Icons.check_rounded : Icons.send_rounded),
                      )
                    : const SizedBox(key: ValueKey('vazio'), width: 4),
              ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------ mensagem
class _Mensagem extends StatefulWidget {
  final SocialMessage m;
  final bool continua;
  final SocialMessage? resposta;
  final String me;
  final SocialGroupInfo? info;
  final bool destaque;
  final ({String nome, bool eu})? Function(String) resolver;
  final void Function(String) aoTocarMencao;
  final void Function(Offset? posicao) aoMenu;
  final VoidCallback? aoResponder;
  final void Function(String) aoReagir;
  final VoidCallback aoTocarAutor;
  final VoidCallback aoTocarResposta;
  final VoidCallback aoTentarDeNovo;

  const _Mensagem({
    super.key,
    required this.m,
    required this.continua,
    required this.resposta,
    required this.me,
    required this.info,
    required this.destaque,
    required this.resolver,
    required this.aoTocarMencao,
    required this.aoMenu,
    required this.aoResponder,
    required this.aoReagir,
    required this.aoTocarAutor,
    required this.aoTocarResposta,
    required this.aoTentarDeNovo,
  });

  @override
  State<_Mensagem> createState() => _MensagemState();
}

class _MensagemState extends State<_Mensagem> {
  double _arraste = 0;
  bool _mouse = false;

  /// Barra de ações ao passar o mouse (computador), como no Discord.
  Widget _barraAcoes(ColorScheme cs) {
    final m = widget.m;
    Widget botao(Widget icone, String dica, VoidCallback f) => Tooltip(
          message: dica,
          waitDuration: const Duration(milliseconds: 400),
          child: InkWell(borderRadius: BorderRadius.circular(6), onTap: f, child: Padding(padding: const EdgeInsets.all(6), child: icone)),
        );
    return Material(
      elevation: 3,
      color: cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (!m.locked)
            for (final e in const ['👍', '❤️', '😂']) botao(Text(e, style: const TextStyle(fontSize: 16)), 'Reagir com $e', () => widget.aoReagir(e)),
          if (widget.aoResponder != null) botao(Icon(Icons.reply_rounded, size: 18, color: cs.onSurfaceVariant), 'Responder', widget.aoResponder!),
          Builder(
            builder: (ctx) => botao(Icon(Icons.more_horiz_rounded, size: 18, color: cs.onSurfaceVariant), 'Mais', () {
              final box = ctx.findRenderObject() as RenderBox?;
              widget.aoMenu(box?.localToGlobal(box.size.bottomLeft(Offset.zero)));
            }),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final m = widget.m;
    final autor = social.profile(m.senderId);
    final membro = widget.info?.member(m.senderId);
    final nome = membro?.nome ?? autor.displayName;
    final cargo = membro?.role ?? Cargo.member;
    final corCargo = membro == null ? null : widget.info?.corDe(membro);
    final corNome = switch (cargo) {
      Cargo.owner => const Color(0xFFE0A526),
      Cargo.admin => const Color(0xFF7289DA),
      _ => corCargo == null ? cs.onSurface : Color(corCargo),
    };
    final meusCargos = widget.info?.member(widget.me)?.roleIds ?? const <String>{};
    final mencionaMe = m.senderId != widget.me &&
        (m.mentions.contains(widget.me) || m.mentions.contains('everyone') || meusCargos.any((r) => m.mentions.contains('role:$r')));
    final fundo = widget.destaque
        ? cs.primary.withValues(alpha: .22)
        : mencionaMe
            ? corAusente.withValues(alpha: _mouse ? .24 : .18)
            : _mouse
                ? cs.onSurface.withValues(alpha: .04)
                : Colors.transparent;
    final opacidade = m.estado == EstadoEnvio.enviando ? .55 : 1.0;

    final conteudo = <Widget>[];
    if (m.deleted) {
      conteudo.add(Text('Mensagem apagada', style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant)));
    } else if (m.locked) {
      conteudo.add(Row(children: [
        Icon(Icons.lock_outline_rounded, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 4),
        Flexible(child: Text('Mensagem protegida (sem a chave neste aparelho)', style: TextStyle(fontStyle: FontStyle.italic, color: cs.onSurfaceVariant))),
      ]));
    } else {
      if (m.text.isNotEmpty) {
        conteudo.add(TextoMensagem(
          m.text,
          estilo: TextStyle(fontSize: 15, height: 1.33, color: cs.onSurface),
          resolverMencao: widget.resolver,
          aoTocarMencao: widget.aoTocarMencao,
        ));
      }
      if (m.editedAt != null && m.text.isNotEmpty) {
        conteudo.add(Text('(editado)', style: TextStyle(fontSize: 10.5, color: cs.onSurfaceVariant)));
      }
      for (final a in m.attachments) {
        conteudo.add(Padding(padding: const EdgeInsets.only(top: 6), child: _Anexo(a: a, conversationId: m.conversationId)));
      }
    }
    if (m.reactions.isNotEmpty) {
      conteudo.add(Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Wrap(spacing: 5, runSpacing: 5, children: [
          for (final r in m.reactions) _Reacao(r: r, minha: r.users.contains(widget.me), aoTocar: () => widget.aoReagir(r.emoji), info: widget.info),
        ]),
      ));
    }
    if (m.estado == EstadoEnvio.falhou) {
      conteudo.add(InkWell(
        onTap: widget.aoTentarDeNovo,
        child: const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.error_outline_rounded, size: 15, color: corOcupado),
            SizedBox(width: 4),
            Text('Não enviada · toque para tentar de novo', style: TextStyle(color: corOcupado, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      ));
    }

    final corpo = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (!widget.continua)
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Flexible(
            child: GestureDetector(
              onTap: widget.aoTocarAutor,
              child: Text(nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: corNome)),
            ),
          ),
          if (cargo != Cargo.member) ...[const SizedBox(width: 5), EtiquetaCargo(cargo)],
          const SizedBox(width: 6),
          Text(quando(m.createdAt), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          if (m.pinnedAt != null) ...[const SizedBox(width: 4), Icon(Icons.push_pin, size: 12, color: cs.onSurfaceVariant)],
          if (m.estado == EstadoEnvio.enviando) ...[const SizedBox(width: 4), Icon(Icons.schedule_rounded, size: 12, color: cs.onSurfaceVariant)],
        ]),
      ...conteudo,
    ]);

    final linha = Padding(
      padding: EdgeInsets.fromLTRB(12, widget.continua ? 1 : 10, 12, 1),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (widget.resposta != null || m.replyTo != null) _Resposta(r: widget.resposta, info: widget.info, aoTocar: widget.aoTocarResposta),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 44,
            child: widget.continua
                ? null
                : GestureDetector(
                    onTap: widget.aoTocarAutor,
                    child: Padding(padding: const EdgeInsets.only(top: 2), child: SocialAvatar(profile: autor, size: 40, presenca: false)),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(child: corpo),
        ]),
      ]),
    );

    final acoes = Plataforma.desktop && _mouse && !m.deleted && m.localId == null;
    return MouseRegion(
      onEnter: (_) => setState(() => _mouse = true),
      onExit: (_) => setState(() => _mouse = false),
      child: GestureDetector(
      onLongPress: () => widget.aoMenu(null),
      onSecondaryTapUp: (d) => widget.aoMenu(d.globalPosition), // clique direito no computador
      onHorizontalDragUpdate: widget.aoResponder == null
          ? null
          : (d) {
              final novo = (_arraste + d.delta.dx).clamp(0.0, 80.0);
              if (_arraste < 56 && novo >= 56) HapticFeedback.selectionClick();
              setState(() => _arraste = novo);
            },
      onHorizontalDragEnd: widget.aoResponder == null
          ? null
          : (_) {
              if (_arraste >= 56) widget.aoResponder!();
              setState(() => _arraste = 0);
            },
      child: AnimatedContainer(
        duration: Duration(milliseconds: widget.destaque ? 200 : 600),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: fundo,
          border: mencionaMe ? const Border(left: BorderSide(color: corAusente, width: 4)) : null,
        ),
        child: Stack(clipBehavior: Clip.none, children: [
          if (_arraste > 0)
            Positioned(
              left: 10,
              top: 0,
              bottom: 0,
              child: Opacity(opacity: (_arraste / 56).clamp(0, 1), child: Icon(Icons.reply_rounded, color: cs.primary)),
            ),
          Transform.translate(offset: Offset(_arraste, 0), child: Opacity(opacity: opacidade, child: linha)),
          Positioned(
            right: 12,
            top: -2,
            child: IgnorePointer(
              ignoring: !acoes,
              child: AnimatedOpacity(
                opacity: acoes ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: AnimatedSlide(offset: acoes ? Offset.zero : const Offset(0, .2), duration: const Duration(milliseconds: 120), child: _barraAcoes(cs)),
              ),
            ),
          ),
        ]),
      ),
      ),
    );
  }
}

class _Resposta extends StatelessWidget {
  final SocialMessage? r;
  final SocialGroupInfo? info;
  final VoidCallback aoTocar;
  const _Resposta({required this.r, required this.info, required this.aoTocar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = this.r;
    final autor = r == null ? null : social.profile(r.senderId);
    final nome = r == null ? '' : info?.member(r.senderId)?.nome ?? autor!.displayName;
    final texto = r == null
        ? 'Mensagem original indisponível'
        : r.deleted
            ? 'Mensagem apagada'
            : r.locked
                ? 'Mensagem protegida'
                : r.text.isNotEmpty
                    ? r.text.replaceAll('\n', ' ')
                    : (r.attachments.isNotEmpty ? '📎 Anexo' : '');
    return GestureDetector(
      onTap: aoTocar,
      child: Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 3),
        child: Row(children: [
          Container(
            width: 26,
            height: 12,
            margin: const EdgeInsets.only(top: 8, right: 6),
            decoration: BoxDecoration(border: Border(left: BorderSide(color: cs.outline, width: 2), top: BorderSide(color: cs.outline, width: 2)), borderRadius: const BorderRadius.only(topLeft: Radius.circular(6))),
          ),
          if (autor != null) ...[SocialAvatar(profile: autor, size: 16, presenca: false), const SizedBox(width: 4)],
          if (nome.isNotEmpty) Text('$nome ', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant)),
          Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))),
        ]),
      ),
    );
  }
}

class _Reacao extends StatelessWidget {
  final SocialReaction r;
  final bool minha;
  final VoidCallback aoTocar;
  final SocialGroupInfo? info;
  const _Reacao({required this.r, required this.minha, required this.aoTocar, required this.info});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Tooltip(
      message: r.users.map((u) => info?.member(u)?.nome ?? social.profile(u).displayName).join(', '),
      triggerMode: TooltipTriggerMode.longPress,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          HapticFeedback.selectionClick();
          aoTocar();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: minha ? cs.primary.withValues(alpha: .18) : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: minha ? cs.primary : Colors.transparent, width: 1.2),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(r.emoji, style: const TextStyle(fontSize: 15)),
            const SizedBox(width: 4),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              transitionBuilder: (c, a) => SlideTransition(position: Tween(begin: const Offset(0, .5), end: Offset.zero).animate(a), child: FadeTransition(opacity: a, child: c)),
              child: Text('${r.users.length}', key: ValueKey(r.users.length), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5, color: minha ? cs.primary : cs.onSurfaceVariant)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Anexo extends StatelessWidget {
  final SocialAttachment a;
  final String conversationId;
  const _Anexo({required this.a, required this.conversationId});

  Future<void> _salvar(BuildContext context) async {
    final bytes = await social.attachment(conversationId, a.path);
    if (bytes == null) {
      if (context.mounted) mostrarAviso(context, 'Não foi possível baixar o arquivo.');
      return;
    }
    try {
      final onde = await salvarArquivo(a.name, bytes, mime: a.mime);
      if (onde != null && context.mounted) mostrarAviso(context, 'Salvo: $onde');
    } catch (e) {
      if (context.mounted) mostrarAviso(context, e);
    }
  }

  Future<void> _menuAnexo(BuildContext context, Offset? pos) async {
    final op = await abrirMenu<String>(context, posicao: pos, titulo: a.name, itens: const [
      ItemMenu('abrir', 'Abrir', icone: Icons.open_in_full_rounded),
      ItemMenu('salvar', 'Salvar como…', icone: Icons.download_rounded),
    ]);
    if (!context.mounted) return;
    if (op == 'abrir') {
      await _abrir(context);
    } else if (op == 'salvar') {
      await _salvar(context);
    }
  }

  Future<void> _abrir(BuildContext context) async {
    final bytes = await social.attachment(conversationId, a.path);
    if (bytes == null) {
      if (context.mounted) mostrarAviso(context, 'Não foi possível baixar o arquivo.');
      return;
    }
    if (a.imagem && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _VerImagem(bytes: bytes, nome: a.name)));
      return;
    }
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/social_${a.path.hashCode.abs()}_${a.name.replaceAll(RegExp(r'[^\w.\- ]'), '_')}');
    await f.writeAsBytes(bytes, flush: true);
    final erro = await abrirNoSistema(f.path, tipo: a.mime);
    if (erro != null && context.mounted) {
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path, mimeType: a.mime)]));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (a.imagem) {
      final maxW = MediaQuery.sizeOf(context).width * .68;
      final ratio = (a.width != null && a.height != null && a.height! > 0) ? a.width! / a.height! : 4 / 3;
      var w = maxW;
      var h = w / ratio;
      if (h > 320) {
        h = 320;
        w = h * ratio;
      }
      return GestureDetector(
        onTap: () => _abrir(context),
        onSecondaryTapUp: (d) => _menuAnexo(context, d.globalPosition),
        onLongPress: () => _menuAnexo(context, null),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: w,
            height: h,
            child: SocialImagem(
              path: a.path,
              conversationId: conversationId,
              largura: w,
              placeholder: (_) => Container(color: cs.surfaceContainerHigh, child: const Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5)))),
            ),
          ),
        ),
      );
    }
    final icone = switch (a.mime) {
      'application/pdf' => Icons.picture_as_pdf_rounded,
      final m when m.startsWith('audio/') => Icons.audio_file_rounded,
      final m when m.startsWith('video/') => Icons.video_file_rounded,
      final m when m.contains('zip') => Icons.folder_zip_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _abrir(context),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 320),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(10), border: Border.all(color: cs.outlineVariant)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icone, size: 34, color: cs.primary),
          const SizedBox(width: 10),
          Flexible(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: cs.primary)),
              Text(tamanho(a.size), style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ]),
          ),
          const SizedBox(width: 6),
          IconButton(
            tooltip: 'Salvar como…',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.download_rounded, color: cs.onSurfaceVariant),
            onPressed: () => _salvar(context),
          ),
        ]),
      ),
    );
  }
}

class _VerImagem extends StatelessWidget {
  final Uint8List bytes;
  final String nome;
  const _VerImagem({required this.bytes, required this.nome});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          title: Text(nome, style: const TextStyle(fontSize: 15)),
          actions: [
            IconButton(
              tooltip: 'Salvar como…',
              icon: const Icon(Icons.download_rounded),
              onPressed: () async {
                final onde = await salvarArquivo(nome, bytes, mime: 'image/png');
                if (onde != null && context.mounted) mostrarAviso(context, 'Salvo: $onde');
              },
            ),
            IconButton(
              tooltip: 'Compartilhar',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: nome, mimeType: 'image/png')], fileNameOverrides: [nome])),
            ),
          ],
        ),
        body: Center(child: InteractiveViewer(maxScale: 6, child: Image.memory(bytes))),
      );
}

class _MiniaturaAnexo extends StatelessWidget {
  final _AnexoPendente a;
  final VoidCallback aoRemover;
  const _MiniaturaAnexo({required this.a, required this.aoRemover});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Stack(clipBehavior: Clip.none, children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 80,
            height: 80,
            color: cs.surfaceContainerHighest,
            child: a.imagem
                ? Image.memory(a.bytes, fit: BoxFit.cover, cacheWidth: 200)
                : Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.insert_drive_file_rounded),
                      Text(a.nome, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 10)),
                    ]),
                  ),
          ),
        ),
        if (a.pronto == null && !a.falhou)
          const Positioned.fill(child: ColoredBox(color: Colors.black38, child: Center(child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))))),
        if (a.falhou) const Positioned.fill(child: ColoredBox(color: Colors.black45, child: Icon(Icons.error_outline_rounded, color: corOcupado))),
        Positioned(
          right: -6,
          top: -6,
          child: InkWell(
            onTap: aoRemover,
            child: CircleAvatar(radius: 11, backgroundColor: cs.inverseSurface, child: Icon(Icons.close_rounded, size: 14, color: cs.onInverseSurface)),
          ),
        ),
      ]),
    );
  }
}

class _BarraAcima extends StatelessWidget {
  final IconData icone;
  final String texto;
  final VoidCallback aoFechar;
  const _BarraAcima({required this.icone, required this.texto, required this.aoFechar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainer,
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(children: [
        Icon(icone, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(texto, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600))),
        IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.close_rounded, size: 20), onPressed: aoFechar),
      ]),
    );
  }
}

class _Divisor extends StatelessWidget {
  final String texto;
  final bool novas;
  const _Divisor({super.key, required this.texto, this.novas = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cor = novas ? corOcupado : cs.outlineVariant;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
      child: Row(children: [
        Expanded(child: Divider(color: cor, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(texto, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: novas ? corOcupado : cs.onSurfaceVariant)),
        ),
        Expanded(child: Divider(color: cor, height: 1)),
      ]),
    );
  }
}

class _Boas extends StatelessWidget {
  final SocialConversation conversa;
  final SocialChannel canal;
  const _Boas({required this.conversa, required this.canal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = conversa;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (c.direta && c.peer != null)
          SocialAvatar(profile: social.profile(c.peer!.userKey), size: 76, presenca: false)
        else
          CircleAvatar(radius: 34, backgroundColor: cs.surfaceContainerHighest, child: Icon(Icons.tag_rounded, size: 40, color: cs.onSurface)),
        const SizedBox(height: 12),
        Text(c.direta ? c.nome : 'Boas-vindas a #${canal.name}!', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          c.direta
              ? 'Este é o começo da sua conversa com ${c.nome}. As mensagens são cifradas no aparelho.'
              : 'Este é o começo do canal #${canal.name}${canal.topic == null ? '' : ' · ${canal.topic}'}.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

/// Entrada suave de mensagem nova.
class _Entrada extends StatelessWidget {
  final Widget child;
  const _Entrada({required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        builder: (context, t, c) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, 14 * (1 - t)), child: c)),
        child: child,
      );
}

class _Pontinhos extends StatefulWidget {
  const _Pontinhos();
  @override
  State<_Pontinhos> createState() => _PontinhosState();
}

class _PontinhosState extends State<_Pontinhos> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < 3; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Opacity(
              opacity: .3 + .7 * (1 - ((_c.value * 3 - i) % 3).clamp(0, 1)),
              child: Container(width: 6, height: 6, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
            ),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------ membros (gaveta)
class _Membros extends StatelessWidget {
  final SocialGroupInfo? info;
  final Future<void> Function() recarregar;
  const _Membros({required this.info, required this.recarregar});

  @override
  Widget build(BuildContext context) => Drawer(
        width: MediaQuery.sizeOf(context).width * .82,
        child: SafeArea(child: _ListaMembros(info: info, recarregar: recarregar)),
      );
}

Future<void> _menuMembro(BuildContext context, SocialMember m, SocialGroupInfo i, Future<void> Function() recarregar, Offset? pos) async {
  final eu = m.userKey == social.me?.userKey;
  final op = await abrirMenu<String>(context, posicao: pos, titulo: m.nome, itens: [
    const ItemMenu('perfil', 'Ver perfil', icone: Icons.person_outline_rounded),
    if (!eu) const ItemMenu('dm', 'Mandar mensagem', icone: Icons.chat_bubble_outline_rounded),
    if (m.profile.username.isNotEmpty) const ItemMenu('copiar', 'Copiar nome de usuário', icone: Icons.alternate_email_rounded),
  ]);
  if (op == null || !context.mounted) return;
  try {
    switch (op) {
      case 'perfil':
        await mostrarPerfil(context, m.userKey, grupo: i, mudou: recarregar);
      case 'dm':
        final id = await social.openDm(m.userKey);
        final c = social.conversation(id);
        if (c != null && c.primeiroCanal != null && context.mounted) await abrirChat(context, c, c.primeiroCanal!);
      case 'copiar':
        await copiar(context, '@${m.profile.username}', 'Nome de usuário copiado');
    }
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e);
  }
}

class _ListaMembros extends StatelessWidget {
  final SocialGroupInfo? info;
  final Future<void> Function() recarregar;
  const _ListaMembros({required this.info, required this.recarregar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i = info;
    return (i == null
            ? const Center(child: CircularProgressIndicator())
            : Builder(builder: (context) {
                final ordem = [...i.members]..sort((a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()));
                final staff = ordem.where((m) => m.role != Cargo.member).toList()..sort((a, b) => b.role.nivel.compareTo(a.role.nivel));
                final online = ordem.where((m) => m.role == Cargo.member && m.profile.online).toList();
                final offline = ordem.where((m) => m.role == Cargo.member && !m.profile.online).toList();
                Widget item(SocialMember m) {
                  final cor = i.corDe(m);
                  return Tocavel(
                    margem: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    aoTocar: () => mostrarPerfil(context, m.userKey, grupo: i, mudou: recarregar),
                    aoMenu: (pos) => _menuMembro(context, m, i, recarregar, pos),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(children: [
                        AnimatedOpacity(
                          opacity: m.profile.online ? 1 : .5,
                          duration: const Duration(milliseconds: 300),
                          child: SocialAvatar(profile: m.profile, size: 36, fundoBorda: cs.surfaceContainerLow),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Flexible(
                                child: Text(m.nome,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: cor != null ? Color(cor) : (m.profile.online ? null : cs.onSurfaceVariant),
                                    )),
                              ),
                              if (m.role != Cargo.member) ...[const SizedBox(width: 6), EtiquetaCargo(m.role)],
                            ]),
                            if (m.profile.customStatus != null || m.profile.customEmoji != null || m.profile.cohort != null)
                              Row(children: [
                                if (m.profile.cohort != null) ...[EtiquetaTurma(m.profile.cohort!), const SizedBox(width: 6)],
                                if (m.profile.customStatus != null || m.profile.customEmoji != null)
                                  Flexible(
                                    child: Text(m.profile.statusLinha,
                                        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                                  ),
                              ]),
                          ]),
                        ),
                      ]),
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: recarregar,
                  child: ListView(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(i.conversation.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                    ),
                    if (i.conversation.description != null)
                      Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(i.conversation.description!, style: TextStyle(color: cs.onSurfaceVariant))),
                    if (i.conversation.tipo == TipoConversa.grupo)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                        child: FilledButton.tonalIcon(
                          onPressed: () => convidarPessoas(context, i.conversation.id, i.conversation.title),
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: const Text('Convidar pessoas'),
                        ),
                      ),
                    if (staff.isNotEmpty) ...[SecaoTitulo('Equipe — ${staff.length}'), for (final m in staff) item(m)],
                    if (online.isNotEmpty) ...[SecaoTitulo('Online — ${online.length}'), for (final m in online) item(m)],
                    if (offline.isNotEmpty) ...[SecaoTitulo('Offline — ${offline.length}'), for (final m in offline) item(m)],
                  ]),
                );
              }));
  }
}

// ------------------------------------------------------------ busca
class _Busca extends StatefulWidget {
  final ChannelFeed feed;
  final ({String nome, bool eu})? Function(String) resolver;
  final String conversationId;
  const _Busca({required this.feed, required this.resolver, required this.conversationId});
  @override
  State<_Busca> createState() => _BuscaState();
}

class _BuscaState extends State<_Busca> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final r = widget.feed.search(_q, nome: (u) => widget.resolver(u)?.nome);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            autofocus: true,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Buscar nas mensagens carregadas'),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('A busca acontece no aparelho, porque o servidor não consegue ler as mensagens.',
              style: TextStyle(fontSize: 11.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: _q.trim().isEmpty
              ? const SizedBox.shrink()
              : r.isEmpty
                  ? const Vazio(icone: Icons.search_off_rounded, titulo: 'Nada encontrado', texto: 'Tente outra palavra.')
                  : ListView(children: [
                      SecaoTitulo('${r.length} resultado(s)'),
                      for (final m in r) _CartaoMensagem(m: m, resolver: widget.resolver, conversationId: widget.conversationId),
                    ]),
        ),
      ]),
    );
  }
}

class _CartaoMensagem extends StatelessWidget {
  final SocialMessage m;
  final ({String nome, bool eu})? Function(String) resolver;
  final String conversationId;
  const _CartaoMensagem({required this.m, required this.resolver, required this.conversationId});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final autor = social.profile(m.senderId);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SocialAvatar(profile: autor, size: 34, presenca: false),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(autor.displayName, style: const TextStyle(fontWeight: FontWeight.w700))),
              const SizedBox(width: 6),
              Text(quando(m.createdAt), style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
            ]),
            if (m.text.isNotEmpty) TextoMensagem(m.text, resolverMencao: resolver),
            for (final a in m.attachments) Padding(padding: const EdgeInsets.only(top: 6), child: _Anexo(a: a, conversationId: conversationId)),
          ]),
        ),
      ]),
    );
  }
}

