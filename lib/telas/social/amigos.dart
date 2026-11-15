import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../social/models.dart';
import 'chat.dart';
import 'perfil.dart';
import 'widgets.dart';

class AmigosAba extends StatefulWidget {
  const AmigosAba({super.key});
  @override
  State<AmigosAba> createState() => _AmigosAbaState();
}

class _AmigosAbaState extends State<AmigosAba> {
  List<SocialFriend>? _amigos;
  List<SocialProfile> _bloqueados = const [];
  String? _erro;
  int _filtro = 0;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await social.friends();
      if (mounted) {
        setState(() {
          _amigos = r.friends;
          _bloqueados = r.blocked;
          _erro = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<void> _fazer(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
    await _carregar();
  }

  Future<void> _mensagem(SocialProfile p) async {
    try {
      final id = await social.openDm(p.userKey);
      final c = social.conversation(id);
      if (c != null && c.primeiroCanal != null && mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ChatTela(conversa: c, canal: c.primeiroCanal!)));
      }
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  Future<void> _adicionar() async {
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => const _AdicionarAmigo());
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final todos = _amigos;
    final pedidos = todos?.where((f) => f.status != 'friends').toList() ?? const [];
    final amigos = todos?.where((f) => f.status == 'friends').toList() ?? const [];
    final online = amigos.where((f) => f.profile.online).toList();
    final lista = switch (_filtro) { 0 => online, 1 => amigos, _ => const <SocialFriend>[] };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Amigos', style: TextStyle(fontWeight: FontWeight.w800)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.tonalIcon(onPressed: _adicionar, icon: const Icon(Icons.person_add_alt_1_rounded, size: 18), label: const Text('Adicionar')),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(children: [
              for (final (i, t) in const [(0, 'Online'), (1, 'Todos'), (2, 'Pendentes'), (3, 'Bloqueados')])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(i == 2 && pedidos.isNotEmpty ? '$t · ${pedidos.length}' : t),
                    selected: _filtro == i,
                    onSelected: (_) => setState(() => _filtro = i),
                  ),
                ),
            ]),
          ),
        ),
      ),
      body: _erro != null && todos == null
          ? Vazio(icone: Icons.cloud_off_rounded, titulo: 'Não foi possível carregar', texto: _erro!, acao: FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')))
          : todos == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: _filtro == 2
                      ? _pendentes(pedidos, cs)
                      : _filtro == 3
                          ? _bloq(cs)
                          : lista.isEmpty
                              ? ListView(children: [
                                  SizedBox(
                                    height: 420,
                                    child: Vazio(
                                      icone: Icons.people_alt_outlined,
                                      titulo: _filtro == 0 && amigos.isNotEmpty ? 'Ninguém online agora' : 'Nenhum amigo ainda',
                                      texto: _filtro == 0 && amigos.isNotEmpty ? 'Seus amigos aparecem aqui quando abrirem o app.' : 'Adicione pelo nome de usuário ou pelo perfil de alguém de um grupo.',
                                      acao: amigos.isEmpty ? FilledButton.icon(onPressed: _adicionar, icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Adicionar amigo')) : null,
                                    ),
                                  ),
                                ])
                              : ListView(children: [
                                  SecaoTitulo('${_filtro == 0 ? 'Online' : 'Todos os amigos'} — ${lista.length}'),
                                  for (final f in lista) _item(f, cs),
                                ]),
                ),
    );
  }

  Widget _item(SocialFriend f, ColorScheme cs) {
    final p = f.profile;
    return ListTile(
      leading: SocialAvatar(profile: p, size: 42),
      title: Text(p.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(p.online || p.customStatus != null ? p.statusLinha : visto(p.lastSeen), maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () async {
        await mostrarPerfil(context, p.userKey, mudou: _carregar);
        await _carregar();
      },
      trailing: IconButton.filledTonal(tooltip: 'Mensagem', icon: const Icon(Icons.chat_bubble_rounded, size: 20), onPressed: () => _mensagem(p)),
    );
  }

  Widget _pendentes(List<SocialFriend> pedidos, ColorScheme cs) {
    if (pedidos.isEmpty) {
      return ListView(children: const [SizedBox(height: 420, child: Vazio(icone: Icons.mark_email_read_outlined, titulo: 'Nenhum pedido pendente', texto: 'Pedidos de amizade enviados e recebidos aparecem aqui.'))]);
    }
    final recebidos = pedidos.where((f) => f.status == 'incoming').toList();
    final enviados = pedidos.where((f) => f.status == 'outgoing').toList();
    return ListView(children: [
      if (recebidos.isNotEmpty) ...[
        SecaoTitulo('Recebidos — ${recebidos.length}'),
        for (final f in recebidos)
          ListTile(
            leading: SocialAvatar(profile: f.profile, size: 42),
            title: Text(f.profile.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('@${f.profile.username}'),
            onTap: () => mostrarPerfil(context, f.profile.userKey, mudou: _carregar),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton.filled(
                tooltip: 'Aceitar',
                style: IconButton.styleFrom(backgroundColor: corOnline, foregroundColor: Colors.white),
                icon: const Icon(Icons.check_rounded),
                onPressed: () => _fazer(() => social.friendRespond(f.profile.userKey, true)),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(tooltip: 'Recusar', icon: const Icon(Icons.close_rounded), onPressed: () => _fazer(() => social.friendRespond(f.profile.userKey, false))),
            ]),
          ),
      ],
      if (enviados.isNotEmpty) ...[
        SecaoTitulo('Enviados — ${enviados.length}'),
        for (final f in enviados)
          ListTile(
            leading: SocialAvatar(profile: f.profile, size: 42),
            title: Text(f.profile.displayName),
            subtitle: const Text('Aguardando resposta'),
            trailing: IconButton(tooltip: 'Cancelar pedido', icon: const Icon(Icons.close_rounded), onPressed: () => _fazer(() => social.friendRemove(f.profile.userKey))),
          ),
      ],
    ]);
  }

  Widget _bloq(ColorScheme cs) {
    if (_bloqueados.isEmpty) {
      return ListView(children: const [SizedBox(height: 420, child: Vazio(icone: Icons.block_rounded, titulo: 'Ninguém bloqueado', texto: 'Quem você bloquear não consegue te mandar mensagem direta nem pedido de amizade.'))]);
    }
    return ListView(children: [
      SecaoTitulo('Bloqueados — ${_bloqueados.length}'),
      for (final p in _bloqueados)
        ListTile(
          leading: SocialAvatar(profile: p, size: 42, presenca: false),
          title: Text(p.displayName),
          subtitle: Text('@${p.username}'),
          trailing: TextButton(onPressed: () => _fazer(() => social.unblock(p.userKey)), child: const Text('Desbloquear')),
        ),
    ]);
  }
}

class _AdicionarAmigo extends StatefulWidget {
  const _AdicionarAmigo();
  @override
  State<_AdicionarAmigo> createState() => _AdicionarAmigoState();
}

class _AdicionarAmigoState extends State<_AdicionarAmigo> {
  final _c = TextEditingController();
  Timer? _espera;
  List<SocialProfile> _resultados = const [];
  bool _buscando = false;
  final Map<String, String> _enviados = {};

  @override
  void dispose() {
    _espera?.cancel();
    _c.dispose();
    super.dispose();
  }

  void _mudou(String v) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () async {
      if (v.trim().replaceAll('@', '').length < 3) {
        setState(() => _resultados = const []);
        return;
      }
      setState(() => _buscando = true);
      try {
        final r = await social.searchUsers(v.trim());
        if (mounted && _c.text == v) setState(() => _resultados = r);
      } catch (_) {
      } finally {
        if (mounted) setState(() => _buscando = false);
      }
    });
  }

  Future<void> _pedir(SocialProfile p) async {
    try {
      final s = await social.friendRequest(userKey: p.userKey);
      setState(() => _enviados[p.userKey] = s);
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        const Text('Adicionar amigo', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Text('Procure pelo nome ou pelo @usuário. Ele aparece na aba Você de cada pessoa.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _c,
            autofocus: true,
            onChanged: _mudou,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Nome ou @usuário',
              suffixIcon: _buscando ? const Padding(padding: EdgeInsets.all(12), child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))) : null,
            ),
          ),
        ),
        Expanded(
          child: ListView(children: [
            for (final p in _resultados)
              ListTile(
                leading: SocialAvatar(profile: p, size: 40),
                title: Text(p.displayName),
                subtitle: Text('@${p.username}'),
                onTap: () => mostrarPerfil(context, p.userKey),
                trailing: switch (_enviados[p.userKey]) {
                  'friends' => const Chip(label: Text('Amigos')),
                  'outgoing' => const Chip(label: Text('Enviado')),
                  _ => FilledButton(onPressed: () => _pedir(p), child: const Text('Adicionar')),
                },
              ),
            if (_c.text.trim().length >= 3 && _resultados.isEmpty && !_buscando)
              const Padding(padding: EdgeInsets.all(24), child: Text('Ninguém encontrado. A pessoa precisa ter aberto o Social pelo menos uma vez.', textAlign: TextAlign.center)),
          ]),
        ),
      ]),
    );
  }
}
