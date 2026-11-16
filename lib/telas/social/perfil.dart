import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../../config.dart';
import '../../fundo.dart';
import '../../social/models.dart';
import 'chat.dart';
import 'widgets.dart';

Future<Uint8List?> escolherImagem() async {
  final r = await FilePicker.pickFiles(dialogTitle: 'Escolha uma imagem', type: FileType.image);
  if (r.isEmpty) return null;
  return r.first.readAsBytes();
}

/// Cartão de perfil (como o popout do Discord). Com [grupo], mostra o cargo e as
/// ações de moderação permitidas para quem está vendo.
Future<void> mostrarPerfil(BuildContext context, String userKey, {SocialGroupInfo? grupo, VoidCallback? mudou}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _PerfilSheet(userKey: userKey, grupo: grupo, mudou: mudou),
  );
}

class _PerfilSheet extends StatefulWidget {
  final String userKey;
  final SocialGroupInfo? grupo;
  final VoidCallback? mudou;
  const _PerfilSheet({required this.userKey, this.grupo, this.mudou});

  @override
  State<_PerfilSheet> createState() => _PerfilSheetState();
}

class _PerfilSheetState extends State<_PerfilSheet> {
  SocialProfileView? _v;
  String? _erro;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final v = await social.profileView(widget.userKey);
      if (mounted) setState(() => _v = v);
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<void> _fazer(Future<void> Function() f, {bool fechar = false}) async {
    setState(() => _ocupado = true);
    try {
      await f();
      widget.mudou?.call();
      if (fechar && mounted) {
        Navigator.pop(context);
        return;
      }
      await _carregar();
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _mensagem() async {
    final nav = Navigator.of(context);
    setState(() => _ocupado = true);
    try {
      final id = await social.openDm(widget.userKey);
      final c = social.conversation(id);
      nav.pop();
      if (c != null && c.primeiroCanal != null) {
        await nav.push(MaterialPageRoute(builder: (_) => ChatTela(conversa: c, canal: c.primeiroCanal!)));
      }
    } catch (e) {
      if (mounted) {
        mostrarAviso(context, e);
        setState(() => _ocupado = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final v = _v;
    if (v == null) {
      return SizedBox(
        height: 260,
        child: Center(child: _erro == null ? const CircularProgressIndicator() : Padding(padding: const EdgeInsets.all(24), child: Text(_erro!))),
      );
    }
    final p = v.profile;
    final eu = p.userKey == social.me?.userKey;
    final grupo = widget.grupo;
    final membro = grupo?.member(p.userKey);
    final meuCargo = grupo?.myRole ?? Cargo.member;
    // moderação por permissão e hierarquia (dono > admin > cargo mais alto), como no servidor
    final acimaDele = grupo != null && membro != null && grupo.myRank > grupo.rankDe(membro);
    final podeModerar = grupo != null &&
        membro != null &&
        !eu &&
        acimaDele &&
        !grupo.conversation.direta &&
        (meuCargo == Cargo.owner ||
            grupo.pode(Permissao.expulsar) ||
            grupo.pode(Permissao.banir) ||
            (grupo.pode(Permissao.gerenciarCargos) && grupo.roles.isNotEmpty));
    final cargos = grupo != null && membro != null ? grupo.cargosDe(membro) : const <SocialRole>[];
    final banner = Color(p.bannerColor ?? corDe(p.userKey).toARGB32());

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .72,
      minChildSize: .4,
      maxChildSize: .95,
      builder: (context, scroll) => ListView(
        controller: scroll,
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            height: 150,
            child: Stack(clipBehavior: Clip.none, children: [
              FundoSocial(path: p.bannerPath, cor: banner, altura: 104, raio: const BorderRadius.vertical(top: Radius.circular(20))),
              Positioned(
                left: 16,
                top: 56,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: cs.surfaceContainerLow, shape: BoxShape.circle),
                  child: SocialAvatar(profile: p, size: 84, fundoBorda: cs.surfaceContainerLow),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: _menu(v, eu),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(membro?.nome ?? p.displayName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800))),
                if (membro != null) ...[const SizedBox(width: 8), EtiquetaCargo(membro.role)],
              ]),
              Text(p.username.isEmpty ? '' : '@${p.username}', style: TextStyle(color: cs.onSurfaceVariant)),
              if (cargos.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final c in cargos) EtiquetaCargoPersonalizado(c)]),
              ],
              const SizedBox(height: 8),
              Row(children: [
                SizedBox.square(dimension: 10, child: PontoPresenca(p.presence)),
                const SizedBox(width: 6),
                Flexible(child: Text(p.online ? p.statusLinha : (p.customStatus != null ? p.statusLinha : visto(p.lastSeen)), style: TextStyle(color: cs.onSurfaceVariant))),
              ]),
              const SizedBox(height: 14),
              if (!eu && !v.blockedMe)
                Row(children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _ocupado || v.blockedByMe ? null : _mensagem,
                      icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                      label: const Text('Mensagem'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _botaoAmizade(v)),
                ]),
              if (v.blockedByMe)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Você bloqueou esta pessoa.', style: TextStyle(color: corOcupado, fontWeight: FontWeight.w600)),
                ),
            ]),
          ),
          _Cartao(children: [
            if (p.bio != null) ...[
              const _Rotulo('Sobre mim'),
              TextoMensagem(p.bio!),
              const SizedBox(height: 14),
            ],
            if (membro?.joinedAt != null) ...[
              const _Rotulo('No grupo desde'),
              Text(dia(membro!.joinedAt!)),
              const SizedBox(height: 14),
            ],
            if (v.friendsSince != null) ...[
              const _Rotulo('Amigos desde'),
              Text(dia(v.friendsSince!)),
              const SizedBox(height: 14),
            ],
            if (p.createdAt != null) ...[
              const _Rotulo('No Social desde'),
              Text(dia(p.createdAt!)),
            ],
          ]),
          if (v.mutualGroups.isNotEmpty && !eu)
            _Cartao(children: [
              _Rotulo('Grupos em comum · ${v.mutualGroups.length}'),
              for (final g in v.mutualGroups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    IconeGrupo(
                      conversa: SocialConversation(id: g.id, title: g.title, iconPath: g.iconPath, createdAt: DateTime.now(), sortAt: DateTime.now()),
                      size: 30,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
            ]),
          if (podeModerar) _moderacao(grupo, membro, meuCargo),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _botaoAmizade(SocialProfileView v) {
    final p = v.profile;
    return switch (v.friendship) {
      'friends' => OutlinedButton.icon(onPressed: null, icon: const Icon(Icons.how_to_reg_rounded, size: 18), label: const Text('Amigos')),
      'outgoing' => OutlinedButton.icon(
          onPressed: _ocupado ? null : () => _fazer(() => social.friendRemove(p.userKey)),
          icon: const Icon(Icons.schedule_rounded, size: 18),
          label: const Text('Pendente'),
        ),
      'incoming' => FilledButton.tonalIcon(
          onPressed: _ocupado ? null : () => _fazer(() => social.friendRespond(p.userKey, true)),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Aceitar'),
        ),
      _ => FilledButton.tonalIcon(
          onPressed: _ocupado || v.blockedByMe ? null : () => _fazer(() => social.friendRequest(userKey: p.userKey)),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Adicionar'),
        ),
    };
  }

  Widget _menu(SocialProfileView v, bool eu) {
    final p = v.profile;
    return Material(
      color: Colors.black26,
      shape: const CircleBorder(),
      child: PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white),
        onSelected: (op) async {
          switch (op) {
            case 'copiar':
              await copiar(context, '@${p.username}', 'Nome de usuário copiado');
            case 'remover':
              if (await confirmar(context, titulo: 'Remover amizade', texto: 'Remover ${p.displayName} dos seus amigos?', botao: 'Remover', perigo: true)) {
                await _fazer(() => social.friendRemove(p.userKey));
              }
            case 'bloquear':
              if (await confirmar(context,
                  titulo: 'Bloquear ${p.displayName}?',
                  texto: 'Vocês deixam de ser amigos, ela não consegue mandar mensagem direta nem pedido de amizade para você.',
                  botao: 'Bloquear',
                  perigo: true)) {
                await _fazer(() => social.block(p.userKey));
              }
            case 'desbloquear':
              await _fazer(() => social.unblock(p.userKey));
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'copiar', child: Text('Copiar nome de usuário')),
          if (!eu && v.friendship == 'friends') const PopupMenuItem(value: 'remover', child: Text('Remover amizade')),
          if (!eu && !v.blockedByMe) const PopupMenuItem(value: 'bloquear', child: Text('Bloquear', style: TextStyle(color: corOcupado))),
          if (!eu && v.blockedByMe) const PopupMenuItem(value: 'desbloquear', child: Text('Desbloquear')),
        ],
      ),
    );
  }

  Widget _moderacao(SocialGroupInfo grupo, SocialMember membro, Cargo meuCargo) {
    final id = grupo.conversation.id;
    final nome = membro.nome;
    return _Cartao(children: [
      const _Rotulo('Moderação'),
      if (meuCargo == Cargo.owner)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(membro.role == Cargo.admin ? Icons.remove_moderator_outlined : Icons.add_moderator_outlined),
          title: Text(membro.role == Cargo.admin ? 'Remover de admin' : 'Tornar admin'),
          subtitle: membro.role == Cargo.admin ? null : const Text('Pode editar o grupo, canais, fixar e remover membros'),
          onTap: _ocupado
              ? null
              : () => _fazer(() => social.groupAction('set_role', {'conversationId': id, 'userKey': membro.userKey, 'role': membro.role == Cargo.admin ? 'member' : 'admin'}),
                  fechar: true),
        ),
      if (meuCargo == Cargo.owner)
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.workspace_premium_outlined),
          title: const Text('Transferir posse do grupo'),
          onTap: _ocupado
              ? null
              : () async {
                  if (await confirmar(context, titulo: 'Transferir posse', texto: '$nome passa a ser dono do grupo e você vira admin.', botao: 'Transferir')) {
                    await _fazer(() => social.groupAction('transfer_owner', {'conversationId': id, 'userKey': membro.userKey}), fechar: true);
                  }
                },
        ),
      if (grupo.pode(Permissao.gerenciarCargos) && grupo.roles.any((r) => r.position < grupo.myRank)) ...[
        const SizedBox(height: 6),
        Text('Cargos', style: TextStyle(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final r in grupo.roles.where((r) => r.position < grupo.myRank))
            FilterChip(
              avatar: CircleAvatar(backgroundColor: r.color == null ? Colors.grey : Color(r.color!), radius: 6),
              label: Text(r.name),
              selected: membro.roleIds.contains(r.id),
              onSelected: _ocupado
                  ? null
                  : (v) {
                      final novos = {...membro.roleIds};
                      v ? novos.add(r.id) : novos.remove(r.id);
                      _fazer(() => social.groupAction('set_member_roles', {'conversationId': id, 'userKey': membro.userKey, 'roleIds': novos.toList()}),
                          fechar: true);
                    },
            ),
        ]),
        const SizedBox(height: 6),
      ],
      if (grupo.pode(Permissao.expulsar))
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_remove_outlined, color: corAusente),
        title: Text('Remover $nome'),
        subtitle: const Text('Pode voltar com um convite'),
        onTap: _ocupado
            ? null
            : () async {
                if (await confirmar(context, titulo: 'Remover do grupo', texto: 'Remover $nome do grupo?', botao: 'Remover', perigo: true)) {
                  await _fazer(() => social.groupAction('kick', {'conversationId': id, 'userKey': membro.userKey}), fechar: true);
                }
              },
      ),
      if (grupo.pode(Permissao.banir))
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.gavel_rounded, color: corOcupado),
        title: Text('Banir $nome', style: const TextStyle(color: corOcupado)),
        subtitle: const Text('Remove e impede de voltar, mesmo com convite'),
        onTap: _ocupado
            ? null
            : () async {
                if (await confirmar(context, titulo: 'Banir do grupo', texto: '$nome sai do grupo e não consegue mais entrar até ser desbanido.', botao: 'Banir', perigo: true)) {
                  await _fazer(() => social.groupAction('kick', {'conversationId': id, 'userKey': membro.userKey, 'ban': true}), fechar: true);
                }
              },
      ),
    ]);
  }
}

class _Cartao extends StatelessWidget {
  final List<Widget> children;
  const _Cartao({required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 14, 12, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}

class _Rotulo extends StatelessWidget {
  final String texto;
  const _Rotulo(this.texto);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(texto.toUpperCase(),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, letterSpacing: .5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

// ------------------------------------------------------------ status
Future<void> escolherStatus(BuildContext context) async {
  final me = social.me;
  if (me == null) return;
  final atual = me.status ?? Presenca.online;
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.edit_note_rounded),
          title: Text(me.customStatus == null && me.customEmoji == null ? 'Definir status personalizado' : 'Editar status personalizado'),
          subtitle: me.customStatus == null && me.customEmoji == null ? null : Text(me.statusLinha),
          onTap: () {
            Navigator.pop(ctx);
            statusPersonalizado(context);
          },
        ),
        const Divider(),
        for (final p in [Presenca.online, Presenca.busy, Presenca.away, Presenca.invisible])
          ListTile(
            leading: SizedBox.square(dimension: 14, child: PontoPresenca(p == Presenca.invisible ? Presenca.offline : p)),
            title: Text(p.rotulo),
            subtitle: Text(switch (p) {
              Presenca.busy => 'Você não recebe notificações do Social',
              Presenca.invisible => 'Você aparece offline, mas usa tudo normalmente',
              Presenca.away => 'Aparece como ausente para os outros',
              _ => 'Aparece online quando o app está aberto',
            }),
            trailing: atual == p ? const Icon(Icons.check_rounded) : null,
            onTap: () async {
              Navigator.pop(ctx);
              try {
                await social.updateProfile({'status': p.name});
                if (p == Presenca.busy && Cfg.socialNotificacoes) await Cfg.setSocialNotificacoes(false);
                if (p != Presenca.busy && atual == Presenca.busy && !Cfg.socialNotificacoes) await Cfg.setSocialNotificacoes(true);
                await agendar();
              } catch (e) {
                if (context.mounted) mostrarAviso(context, e);
              }
            },
          ),
      ]),
    ),
  );
}

const _emojisStatus = ['😀', '📚', '💻', '🎧', '😴', '🍕', '🎮', '🏃', '☕', '🔥', '🤒', '✈️', '📝', '🧠', '🎉', '❤️'];

Future<void> statusPersonalizado(BuildContext context) async {
  final me = social.me;
  if (me == null) return;
  final texto = TextEditingController(text: me.customStatus ?? '');
  var emoji = me.customEmoji;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        title: const Text('Status personalizado'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: texto,
            autofocus: true,
            maxLength: 64,
            decoration: InputDecoration(
              hintText: 'Estudando para a prova…',
              prefixIcon: Padding(padding: const EdgeInsets.all(12), child: Text(emoji ?? '🙂', style: const TextStyle(fontSize: 20))),
            ),
          ),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final e in _emojisStatus)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => set(() => emoji = emoji == e ? null : e),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: emoji == e ? Theme.of(ctx).colorScheme.primaryContainer : null,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ]),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              texto.clear();
              emoji = null;
              Navigator.pop(ctx, true);
            },
            child: const Text('Limpar'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    ),
  );
  if (ok == true) {
    try {
      await social.updateProfile({'customStatus': texto.text.trim(), 'customEmoji': emoji ?? ''});
    } catch (e) {
      if (context.mounted) mostrarAviso(context, e);
    }
  }
  texto.dispose();
}

// ------------------------------------------------------------ aba "Você"
class VoceAba extends StatefulWidget {
  const VoceAba({super.key});
  @override
  State<VoceAba> createState() => _VoceAbaState();
}

class _VoceAbaState extends State<VoceAba> {
  bool _salvando = false;

  Future<void> _salvar(Future<void> Function() f) async {
    setState(() => _salvando = true);
    try {
      await f();
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _trocarFoto() async {
    final me = social.me!;
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Escolher foto'), onTap: () => Navigator.pop(ctx, 'trocar')),
          if (me.avatarPath != null)
            ListTile(leading: const Icon(Icons.delete_outline, color: corOcupado), title: const Text('Remover foto'), onTap: () => Navigator.pop(ctx, 'remover')),
        ]),
      ),
    );
    if (op == 'remover') await _salvar(() => social.setAvatar(null));
    if (op == 'trocar') {
      final bytes = await escolherImagem();
      if (bytes != null) await _salvar(() => social.setAvatar(bytes));
    }
  }

  Future<void> _editar(String titulo, String campo, String atual, {int max = 48, int linhas = 1, String? dica}) async {
    final v = await pedirTexto(context, titulo: titulo, inicial: atual, max: max, linhas: linhas, dica: dica);
    if (v == null) return;
    await _salvar(() => social.updateProfile({campo: v.trim()}));
  }

  /// Fundo do perfil: cor ou foto (#4, #5).
  Future<void> _fundo() async {
    final me = social.me!;
    final op = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Escolher cor'), onTap: () => Navigator.pop(ctx, 'cor')),
          ListTile(leading: const Icon(Icons.image_outlined), title: const Text('Usar uma foto'), onTap: () => Navigator.pop(ctx, 'foto')),
          if (me.bannerPath != null)
            ListTile(leading: const Icon(Icons.hide_image_outlined, color: corOcupado), title: const Text('Tirar a foto'), onTap: () => Navigator.pop(ctx, 'tirar')),
        ]),
      ),
    );
    if (op == 'cor') await _cor();
    if (op == 'tirar') await _salvar(() => social.setBanner(null));
    if (op == 'foto') {
      final b = await escolherImagem();
      if (b != null) await _salvar(() => social.setBanner(b));
    }
  }

  Future<void> _cor() async {
    final cor = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cor do perfil'),
        content: Wrap(spacing: 10, runSpacing: 10, children: [
          for (final c in coresBanner)
            InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.pop(ctx, c),
              child: CircleAvatar(radius: 22, backgroundColor: Color(c), child: social.me?.bannerColor == c ? const Icon(Icons.check, color: Colors.white) : null),
            ),
        ]),
      ),
    );
    if (cor != null) await _salvar(() => social.updateProfile({'bannerColor': cor}));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: social,
      builder: (context, _) {
        final me = social.me;
        if (me == null) return const Center(child: CircularProgressIndicator());
        final banner = Color(me.bannerColor ?? corDe(me.userKey).toARGB32());
        return ListView(padding: EdgeInsets.zero, children: [
          SizedBox(
            height: 170,
            child: Stack(clipBehavior: Clip.none, children: [
              InkWell(
                onTap: _fundo,
                child: FundoSocial(
                  path: me.bannerPath,
                  cor: banner,
                  altura: 116,
                  child: const Align(
                      alignment: Alignment.topRight,
                      child: Padding(padding: EdgeInsets.all(10), child: Icon(Icons.wallpaper_rounded, color: Colors.white70))),
                ),
              ),
              Positioned(
                left: 16,
                top: 64,
                child: GestureDetector(
                  onTap: _trocarFoto,
                  child: Stack(children: [
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(color: cs.surface, shape: BoxShape.circle),
                      child: SocialAvatar(profile: me, size: 92),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: CircleAvatar(radius: 14, backgroundColor: cs.primary, child: Icon(Icons.edit, size: 15, color: cs.onPrimary)),
                    ),
                  ]),
                ),
              ),
              if (_salvando) const Positioned(right: 16, top: 128, child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(me.displayName, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
              Text('@${me.username}', style: TextStyle(color: cs.onSurfaceVariant)),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => escolherStatus(context),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
                  child: Row(children: [
                    SizedBox.square(dimension: 14, child: PontoPresenca(me.status == Presenca.invisible ? Presenca.offline : (me.status ?? Presenca.online))),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        me.customStatus != null || me.customEmoji != null ? me.statusLinha : (me.status ?? Presenca.online).rotulo,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
              ),
            ]),
          ),
          const SecaoTitulo('Perfil'),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Nome de exibição'),
            subtitle: Text(me.displayName),
            onTap: () => _editar('Nome de exibição', 'displayName', me.displayName, dica: 'É como as pessoas veem você no Social. Não muda o seu nome no AVA.'),
          ),
          ListTile(
            leading: const Icon(Icons.alternate_email_rounded),
            title: const Text('Nome de usuário'),
            subtitle: Text('@${me.username}'),
            onTap: () => _editar('Nome de usuário', 'username', me.username, max: 24, dica: 'Letras minúsculas, números, _ ou ponto. Seus amigos usam para te adicionar.'),
            trailing: IconButton(icon: const Icon(Icons.copy_rounded, size: 20), onPressed: () => copiar(context, '@${me.username}')),
          ),
          ListTile(
            leading: const Icon(Icons.notes_rounded),
            title: const Text('Sobre mim'),
            subtitle: Text(me.bio ?? 'Conte um pouco sobre você', maxLines: 3, overflow: TextOverflow.ellipsis),
            onTap: () => _editar('Sobre mim', 'bio', me.bio ?? '', max: 190, linhas: 5),
          ),
          ListTile(leading: const Icon(Icons.palette_outlined), title: const Text('Cor do perfil'), trailing: CircleAvatar(radius: 12, backgroundColor: banner), onTap: _cor),
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: const Text('Ver meu perfil'),
            subtitle: const Text('Como os outros veem'),
            onTap: () => mostrarPerfil(context, me.userKey),
          ),
          const SecaoTitulo('Notificações'),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Mensagens do Social'),
            subtitle: const Text('Avisa novas mensagens mesmo com o app fechado (a cada ~15 min)'),
            value: Cfg.socialNotificacoes,
            onChanged: (v) async {
              await Cfg.setSocialNotificacoes(v);
              if (v) await Notif.pedirPermissao();
              await agendar();
              setState(() {});
            },
          ),
          const SecaoTitulo('Privacidade'),
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Mensagens cifradas no aparelho'),
            subtitle: const Text('O servidor guarda só texto embaralhado. Professores não veem grupos nem conversas de que não participam.'),
          ),
          const SizedBox(height: 32),
        ]);
      },
    );
  }
}
