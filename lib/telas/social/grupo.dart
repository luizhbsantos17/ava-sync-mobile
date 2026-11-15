import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../../social/models.dart';
import 'perfil.dart';
import 'widgets.dart';

// ------------------------------------------------------------ criar / entrar
Future<String?> criarGrupo(BuildContext context) async {
  final nome = TextEditingController();
  final desc = TextEditingController();
  Uint8List? icone;
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(ctx).bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Crie seu grupo', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Um lugar para você e seus amigos conversarem, com canais separados por assunto.',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () async {
              final b = await escolherImagem();
              if (b != null) set(() => icone = b);
            },
            child: CircleAvatar(
              radius: 40,
              backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
              backgroundImage: icone == null ? null : MemoryImage(icone!),
              child: icone == null ? const Icon(Icons.add_a_photo_outlined, size: 28) : null,
            ),
          ),
          const SizedBox(height: 16),
          TextField(controller: nome, autofocus: true, maxLength: 64, decoration: const InputDecoration(labelText: 'Nome do grupo')),
          TextField(controller: desc, maxLength: 300, minLines: 1, maxLines: 3, decoration: const InputDecoration(labelText: 'Descrição (opcional)')),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar grupo'))),
        ]),
      ),
    ),
  );
  String? id;
  if (ok == true && nome.text.trim().isNotEmpty) {
    try {
      id = await social.createGroup(title: nome.text.trim(), description: desc.text.trim().isEmpty ? null : desc.text.trim(), icon: icone);
    } catch (e) {
      if (context.mounted) mostrarAviso(context, e);
    }
  }
  nome.dispose();
  desc.dispose();
  return id;
}

Future<void> entrarComConvite(BuildContext context) async {
  final codigo = await pedirTexto(context, titulo: 'Entrar em um grupo', rotulo: 'Convite', max: 2000, linhas: 4, botao: 'Entrar', dica: 'Cole o convite que começa com AVASYNC1.');
  if (codigo == null || codigo.trim().isEmpty) return;
  try {
    final nome = await social.joinGroup(codigo);
    if (context.mounted) mostrarAviso(context, 'Você entrou em $nome');
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e);
  }
}

Future<void> criarGrupoDeMateria(BuildContext context) async {
  final carregando = showDialog<void>(context: context, barrierDismissible: false, builder: (_) => const Center(child: CircularProgressIndicator()));
  List<SocialCourse> materias;
  try {
    materias = await social.teacherCourses();
  } catch (e) {
    if (context.mounted) {
      Navigator.pop(context);
      mostrarAviso(context, e);
    }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context);
  await carregando;
  if (!context.mounted) return;
  if (materias.isEmpty) {
    mostrarAviso(context, 'O AVA não confirmou você como professor em nenhuma matéria.');
    return;
  }
  final m = await showModalBottomSheet<SocialCourse>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const SecaoTitulo('Escolha a matéria'),
        for (final c in materias) ListTile(leading: const Icon(Icons.school_outlined), title: Text(c.name), onTap: () => Navigator.pop(ctx, c)),
      ]),
    ),
  );
  if (m == null || !context.mounted) return;
  final nome = await pedirTexto(context, titulo: 'Grupo da matéria', inicial: m.name, rotulo: 'Nome do grupo', botao: 'Criar',
      dica: 'Todos os inscritos na matéria entram. Cria os canais #avisos (só admins escrevem), #geral e #dúvidas.');
  if (nome == null || nome.trim().isEmpty || !context.mounted) return;
  try {
    final r = await social.createCourseGroup(course: m, title: nome.trim());
    if (context.mounted) mostrarAviso(context, 'Grupo criado com ${r.members} pessoa(s) da matéria.');
  } catch (e) {
    if (context.mounted) mostrarAviso(context, e);
  }
}

// ------------------------------------------------------------ convidar
Future<void> convidarPessoas(BuildContext context, String conversationId, String titulo) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _Convidar(conversationId: conversationId, titulo: titulo),
  );
}

class _Convidar extends StatefulWidget {
  final String conversationId;
  final String titulo;
  const _Convidar({required this.conversationId, required this.titulo});
  @override
  State<_Convidar> createState() => _ConvidarState();
}

class _ConvidarState extends State<_Convidar> {
  List<SocialFriend>? _amigos;
  Set<String> _membros = {};
  final Set<String> _convidados = {};
  String? _codigo;
  int? _horas = 24 * 7;
  bool _gerando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await social.friends();
      final info = await social.groupInfo(widget.conversationId);
      if (mounted) {
        setState(() {
          _amigos = r.friends.where((f) => f.status == 'friends').toList();
          _membros = {for (final m in info.members) m.userKey};
        });
      }
    } catch (e) {
      if (mounted) setState(() => _amigos = const []);
    }
  }

  Future<void> _gerar() async {
    setState(() => _gerando = true);
    try {
      final c = await social.createInvite(widget.conversationId, horas: _horas);
      if (mounted) setState(() => _codigo = c);
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amigos = _amigos;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: ListView(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('Convidar para ${widget.titulo}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        const SecaoTitulo('Link de convite'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Quem tiver o convite entra no grupo e consegue ler as mensagens. Mande só para quem deve entrar.',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            const SizedBox(height: 10),
            Wrap(spacing: 6, children: [
              for (final o in const [(1, '1 hora'), (24, '1 dia'), (24 * 7, '7 dias'), (null, 'Nunca expira')])
                ChoiceChip(label: Text(o.$2), selected: _horas == o.$1, onSelected: (_) => setState(() {
                      _horas = o.$1;
                      _codigo = null;
                    })),
            ]),
            const SizedBox(height: 10),
            if (_codigo == null)
              FilledButton.icon(
                onPressed: _gerando ? null : _gerar,
                icon: _gerando ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.link_rounded),
                label: const Text('Gerar convite'),
              )
            else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                child: Text(_codigo!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: OutlinedButton.icon(onPressed: () => copiar(context, _codigo!, 'Convite copiado'), icon: const Icon(Icons.copy_rounded), label: const Text('Copiar'))),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => SharePlus.instance.share(ShareParams(text: 'Entre no grupo "${widget.titulo}" no AVA Sync (Social → Entrar com convite):\n\n${_codigo!}')),
                    icon: const Icon(Icons.share_rounded),
                    label: const Text('Enviar'),
                  ),
                ),
              ]),
            ],
          ]),
        ),
        const SecaoTitulo('Amigos'),
        if (amigos == null)
          const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
        else if (amigos.isEmpty)
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text('Adicione amigos na aba Amigos para convidá-los direto.', style: TextStyle(color: cs.onSurfaceVariant)))
        else
          for (final f in amigos)
            ListTile(
              leading: SocialAvatar(profile: f.profile, size: 38),
              title: Text(f.profile.displayName),
              subtitle: Text('@${f.profile.username}'),
              trailing: _membros.contains(f.profile.userKey)
                  ? const Text('No grupo')
                  : _convidados.contains(f.profile.userKey)
                      ? const Icon(Icons.check_circle_rounded, color: corOnline)
                      : OutlinedButton(
                          onPressed: () async {
                            try {
                              await social.groupAction('add_member', {'conversationId': widget.conversationId, 'userKey': f.profile.userKey}, reload: false);
                              setState(() => _convidados.add(f.profile.userKey));
                            } catch (e) {
                              if (context.mounted) mostrarAviso(context, e);
                            }
                          },
                          child: const Text('Adicionar'),
                        ),
            ),
        const SizedBox(height: 24),
      ]),
    );
  }
}

// ------------------------------------------------------------ configurações
class GrupoConfigTela extends StatefulWidget {
  final String conversationId;
  const GrupoConfigTela({super.key, required this.conversationId});
  @override
  State<GrupoConfigTela> createState() => _GrupoConfigTelaState();
}

class _GrupoConfigTelaState extends State<GrupoConfigTela> {
  SocialGroupInfo? _i;
  String? _erro;
  bool _ocupado = false;

  String get _id => widget.conversationId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final i = await social.groupInfo(_id);
      if (mounted) setState(() => _i = i);
    } catch (e) {
      if (mounted) setState(() => _erro = '$e');
    }
  }

  Future<void> _fazer(Future<void> Function() f) async {
    setState(() => _ocupado = true);
    try {
      await f();
      await _carregar();
    } catch (e) {
      if (mounted) mostrarAviso(context, e);
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  Future<void> _canal({SocialChannel? canal}) async {
    final nome = TextEditingController(text: canal?.name ?? '');
    final topico = TextEditingController(text: canal?.topic ?? '');
    var soAdmins = canal?.onlyAdmins ?? false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(canal == null ? 'Criar canal' : 'Editar canal'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nome, autofocus: true, maxLength: 32, decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.tag_rounded))),
            TextField(controller: topico, maxLength: 200, decoration: const InputDecoration(labelText: 'Tópico (opcional)')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Canal de avisos'),
              subtitle: const Text('Só administradores escrevem'),
              value: soAdmins,
              onChanged: (v) => set(() => soAdmins = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(canal == null ? 'Criar' : 'Salvar')),
          ],
        ),
      ),
    );
    if (ok == true && nome.text.trim().isNotEmpty) {
      await _fazer(() => canal == null
          ? social.groupAction('create_channel', {'conversationId': _id, 'name': nome.text, 'topic': topico.text, 'onlyAdmins': soAdmins})
          : social.groupAction('update_channel', {'channelId': canal.id, 'name': nome.text, 'topic': topico.text, 'onlyAdmins': soAdmins}));
    }
    nome.dispose();
    topico.dispose();
  }

  Future<void> _mover(int de, int para) async {
    final canais = [..._i!.channels];
    final c = canais.removeAt(de);
    canais.insert(para, c);
    await _fazer(() => social.groupAction('reorder_channels', {'conversationId': _id, 'channelIds': [for (final x in canais) x.id]}));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final i = _i;
    if (i == null) {
      return Scaffold(appBar: AppBar(), body: Center(child: _erro == null ? const CircularProgressIndicator() : Text(_erro!)));
    }
    final c = i.conversation;
    final admin = i.myRole.gerencia;
    final dono = i.myRole == Cargo.owner;
    final online = i.members.where((m) => m.profile.online).length;
    return Scaffold(
      appBar: AppBar(title: const Text('Configurações do grupo'), bottom: _ocupado ? const PreferredSize(preferredSize: Size.fromHeight(3), child: LinearProgressIndicator(minHeight: 3)) : null),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(children: [
          const SizedBox(height: 12),
          Center(
            child: GestureDetector(
              onTap: !admin
                  ? null
                  : () async {
                      final op = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        builder: (ctx) => SafeArea(
                          child: Column(mainAxisSize: MainAxisSize.min, children: [
                            ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Escolher imagem'), onTap: () => Navigator.pop(ctx, 'trocar')),
                            if (c.iconPath != null) ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remover imagem'), onTap: () => Navigator.pop(ctx, 'remover')),
                          ]),
                        ),
                      );
                      if (op == 'remover') await _fazer(() => social.setGroupIcon(_id, null));
                      if (op == 'trocar') {
                        final b = await escolherImagem();
                        if (b != null) await _fazer(() => social.setGroupIcon(_id, b));
                      }
                    },
              child: Stack(children: [
                IconeGrupo(conversa: c, size: 88, selecionado: true),
                if (admin) Positioned(right: 0, bottom: 0, child: CircleAvatar(radius: 14, backgroundColor: cs.primary, child: Icon(Icons.edit, size: 15, color: cs.onPrimary))),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Text(c.title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const SizedBox.square(dimension: 9, child: PontoPresenca(Presenca.online)),
            Text(' $online online   ', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox.square(dimension: 9, child: PontoPresenca(Presenca.offline)),
            Text(' ${i.members.length} membros', style: TextStyle(color: cs.onSurfaceVariant)),
          ]),
          if (c.tipo == TipoConversa.materia && c.courseName != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Center(child: Chip(avatar: const Icon(Icons.school_outlined, size: 16), label: Text(c.courseName!)))),
          if (c.description != null)
            Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 0), child: Text(c.description!, textAlign: TextAlign.center)),
          if (c.tipo == TipoConversa.grupo)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: FilledButton.icon(onPressed: () => convidarPessoas(context, _id, c.title), icon: const Icon(Icons.person_add_alt_1_rounded), label: const Text('Convidar pessoas')),
            ),
          const SecaoTitulo('Você'),
          SwitchListTile(
            secondary: Icon(i.muted ? Icons.notifications_off_outlined : Icons.notifications_outlined),
            title: const Text('Silenciar grupo'),
            subtitle: const Text('Sem notificações nem contador'),
            value: i.muted,
            onChanged: (v) => _fazer(() => social.setMuted(_id, v)),
          ),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Apelido neste grupo'),
            subtitle: Text(i.nickname ?? 'Usa o seu nome de exibição'),
            onTap: () async {
              final v = await pedirTexto(context, titulo: 'Apelido no grupo', inicial: i.nickname ?? '', max: 32, dica: 'Deixe vazio para usar seu nome de exibição.');
              if (v != null) await _fazer(() => social.groupAction('set_member_prefs', {'conversationId': _id, 'nickname': v.trim()}));
            },
          ),
          if (admin) ...[
            const SecaoTitulo('Visão geral'),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('Nome do grupo'),
              subtitle: Text(c.title),
              onTap: () async {
                final v = await pedirTexto(context, titulo: 'Nome do grupo', inicial: c.title);
                if (v != null && v.trim().isNotEmpty) await _fazer(() => social.groupAction('update_group', {'conversationId': _id, 'title': v}));
              },
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('Descrição'),
              subtitle: Text(c.description ?? 'Sem descrição', maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () async {
                final v = await pedirTexto(context, titulo: 'Descrição', inicial: c.description ?? '', max: 300, linhas: 4);
                if (v != null) await _fazer(() => social.groupAction('update_group', {'conversationId': _id, 'description': v}));
              },
            ),
          ],
          SecaoTitulo('Canais · ${i.channels.length}', acao: admin ? IconButton(tooltip: 'Criar canal', icon: const Icon(Icons.add_rounded), onPressed: _canal) : null),
          for (var k = 0; k < i.channels.length; k++)
            ListTile(
              leading: Icon(i.channels[k].onlyAdmins ? Icons.campaign_outlined : Icons.tag_rounded),
              title: Text(i.channels[k].name),
              subtitle: i.channels[k].topic == null ? null : Text(i.channels[k].topic!, maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: !admin
                  ? null
                  : PopupMenuButton<String>(
                      onSelected: (op) async {
                        switch (op) {
                          case 'editar':
                            await _canal(canal: i.channels[k]);
                          case 'subir':
                            await _mover(k, k - 1);
                          case 'descer':
                            await _mover(k, k + 1);
                          case 'apagar':
                            if (await confirmar(context, titulo: 'Apagar #${i.channels[k].name}', texto: 'Todas as mensagens deste canal serão apagadas para todos.', botao: 'Apagar', perigo: true)) {
                              await _fazer(() => social.groupAction('delete_channel', {'channelId': i.channels[k].id}));
                            }
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(value: 'editar', child: Text('Editar')),
                        if (k > 0) const PopupMenuItem(value: 'subir', child: Text('Mover para cima')),
                        if (k < i.channels.length - 1) const PopupMenuItem(value: 'descer', child: Text('Mover para baixo')),
                        if (i.channels.length > 1) const PopupMenuItem(value: 'apagar', child: Text('Apagar', style: TextStyle(color: corOcupado))),
                      ],
                    ),
            ),
          SecaoTitulo('Membros · ${i.members.length}'),
          for (final m in ([...i.members]..sort((a, b) => b.role.nivel != a.role.nivel ? b.role.nivel.compareTo(a.role.nivel) : a.nome.toLowerCase().compareTo(b.nome.toLowerCase()))))
            ListTile(
              leading: SocialAvatar(profile: m.profile, size: 38),
              title: Row(children: [Flexible(child: Text(m.nome, maxLines: 1, overflow: TextOverflow.ellipsis)), const SizedBox(width: 6), EtiquetaCargo(m.role)]),
              subtitle: Text('@${m.profile.username}', maxLines: 1),
              onTap: () => mostrarPerfil(context, m.userKey, grupo: i, mudou: _carregar),
            ),
          if (admin) ...[
            const SecaoTitulo('Moderação'),
            ListTile(
              leading: const Icon(Icons.link_off_rounded),
              title: const Text('Revogar todos os convites'),
              subtitle: Text(i.activeInvites == 0 ? 'Nenhum convite ativo' : '${i.activeInvites} convite(s) ativo(s)'),
              onTap: () async {
                if (await confirmar(context, titulo: 'Revogar convites', texto: 'Todos os convites deste grupo param de funcionar. Quem já entrou continua.', botao: 'Revogar', perigo: true)) {
                  await _fazer(() => social.groupAction('revoke_invites', {'conversationId': _id}));
                }
              },
            ),
            ExpansionTile(
              leading: const Icon(Icons.gavel_rounded),
              title: Text('Banidos · ${i.bans.length}'),
              children: [
                if (i.bans.isEmpty) const ListTile(title: Text('Ninguém banido')),
                for (final b in i.bans)
                  ListTile(
                    leading: SocialAvatar(profile: b.profile, size: 34, presenca: false),
                    title: Text(b.profile.displayName),
                    trailing: TextButton(onPressed: () => _fazer(() => social.groupAction('unban', {'conversationId': _id, 'userKey': b.userKey})), child: const Text('Desbanir')),
                  ),
              ],
            ),
          ],
          const SecaoTitulo('Sair'),
          ListTile(
            leading: const Icon(Icons.logout_rounded, color: corOcupado),
            title: const Text('Sair do grupo', style: TextStyle(color: corOcupado)),
            subtitle: dono ? const Text('A posse passa para um admin ou para o membro mais antigo') : null,
            onTap: () async {
              final nav = Navigator.of(context);
              if (await confirmar(context, titulo: 'Sair de ${c.title}?', texto: 'Para voltar, você vai precisar de um convite novo.', botao: 'Sair', perigo: true)) {
                try {
                  await social.leaveGroup(_id);
                  nav.popUntil((r) => r.isFirst || r.settings.name == 'social');
                } catch (e) {
                  if (mounted) mostrarAviso(this.context, e);
                }
              }
            },
          ),
          if (dono)
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: corOcupado),
              title: const Text('Apagar grupo', style: TextStyle(color: corOcupado)),
              subtitle: const Text('Apaga canais e mensagens para todos'),
              onTap: () async {
                final nav = Navigator.of(context);
                if (await confirmar(context, titulo: 'Apagar ${c.title}?', texto: 'O grupo, os canais e todas as mensagens serão apagados para todos. Isso não pode ser desfeito.', botao: 'Apagar', perigo: true)) {
                  try {
                    await social.deleteGroup(_id);
                    nav.popUntil((r) => r.isFirst || r.settings.name == 'social');
                  } catch (e) {
                    if (mounted) mostrarAviso(this.context, e);
                  }
                }
              },
            ),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}
