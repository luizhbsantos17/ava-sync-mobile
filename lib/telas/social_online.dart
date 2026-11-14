import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../social/backend.dart';
import '../social/models.dart';
import '../social/repository.dart';
import '../social/supabase_crypto.dart';

class SocialOnlineTela extends StatefulWidget {
  final SocialRepository repository;
  const SocialOnlineTela({super.key, required this.repository});

  @override
  State<SocialOnlineTela> createState() => _SocialOnlineTelaState();
}

class _SocialOnlineTelaState extends State<SocialOnlineTela> {
  late Future<List<SocialConversation>> _conversas;
  bool _carregandoIdentidade = true;
  String? _erroIdentidade;

  @override
  void initState() {
    super.initState();
    _recarregar();
    _carregarIdentidade();
  }

  void _recarregar() => _conversas = widget.repository.conversations();

  Future<void> _carregarIdentidade() async {
    try {
      await widget.repository.identity();
      if (mounted) setState(() => _carregandoIdentidade = false);
    } catch (e) {
      if (mounted) setState(() { _erroIdentidade = '$e'; _carregandoIdentidade = false; });
    }
  }

  Future<void> _abrirGrupo({SocialCourse? materia}) async {
    final nome = TextEditingController();
    nome.text = materia?.name ?? '';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(materia == null ? 'Criar grupo privado' : 'Criar grupo da matéria'),
        content: TextField(controller: nome, autofocus: true, maxLength: 64, decoration: const InputDecoration(labelText: 'Nome do grupo')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
        ],
      ),
    );
    if (ok != true || nome.text.trim().isEmpty || !mounted) {
      nome.dispose();
      return;
    }
    try {
      final invite = materia == null
          ? await widget.repository.createGroup(nome.text.trim())
          : await widget.repository.createCourseGroup(title: nome.text.trim(), course: materia);
      final code = SupabaseSocialCrypto.makeInvite(
        conversationId: invite.conversationId,
        token: invite.token,
        conversationKey: invite.conversationKey,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(materia == null ? 'Grupo pronto' : 'Grupo da matéria pronto'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(materia == null
                ? 'Compartilhe este convite apenas com quem deve entrar. Ele permite entrar no grupo e ler as mensagens.'
                : 'O AVA confirmou seu papel nesta matéria e adicionou ${invite.membersCount ?? 0} pessoa(s) inscrita(s). Compartilhe este convite com a turma para entregar a chave de leitura; sem ele, as mensagens continuam cifradas e não podem ser abertas.'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 130),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Theme.of(ctx).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(child: SelectableText(code, style: const TextStyle(fontSize: 11))),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar')),
            FilledButton.icon(
              onPressed: () => SharePlus.instance.share(ShareParams(text: 'Convite privado do AVA Sync para ${nome.text.trim()}\n\n$code')),
              icon: const Icon(Icons.share_outlined),
              label: const Text('Compartilhar'),
            ),
          ],
        ),
      );
      if (mounted) setState(_recarregar);
    } catch (e) {
      _erro('$e');
    } finally {
      nome.dispose();
    }
  }

  Future<void> _entrarGrupo() async {
    final code = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entrar em grupo'),
        content: TextField(
          controller: code,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(labelText: 'Código de convite', alignLabelWithHint: true),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entrar')),
        ],
      ),
    );
    if (ok == true && code.text.trim().isNotEmpty) {
      try {
        await widget.repository.joinGroup(code.text);
        if (mounted) setState(_recarregar);
      } catch (e) {
        _erro('$e');
      }
    }
    code.dispose();
  }

  void _erro(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _escolherMateria() async {
    try {
      final materias = await widget.repository.teacherCourses();
      if (!mounted) return;
      if (materias.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O AVA não confirmou permissões de professor em nenhuma matéria.'),
        ));
        return;
      }
      final materia = await showModalBottomSheet<SocialCourse>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Escolha a matéria')),
            for (final c in materias)
              ListTile(title: Text(c.name), leading: const Icon(Icons.school_outlined), onTap: () => Navigator.pop(ctx, c)),
          ],
        )),
      );
      if (materia != null && mounted) await _abrirGrupo(materia: materia);
    } catch (e) {
      _erro('$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.repository.currentUser;
    if (SocialBackend.initializationError != null) return SocialFalhaTela(texto: SocialBackend.initializationError!);
    if (_carregandoIdentidade) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_erroIdentidade != null) return SocialFalhaTela(texto: _erroIdentidade!, tentar: _carregarIdentidade);
    if (user == null) return const SocialFalhaTela(texto: 'Conecte-se ao AVA e sincronize as matérias antes de abrir o Social.');
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(tooltip: 'Voltar ao Acadêmico', icon: const Icon(Icons.school_outlined), onPressed: () => Navigator.of(context).pop()),
        title: const Text('Grupos e chats'),
        actions: [
          IconButton(tooltip: 'Criar grupo de matéria (verificação pelo AVA)', onPressed: _escolherMateria, icon: const Icon(Icons.school_outlined)),
          IconButton(tooltip: 'Atualizar conversas', onPressed: () => setState(_recarregar), icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(children: [
            Expanded(child: Text('Seus grupos', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800))),
            IconButton(onPressed: _entrarGrupo, tooltip: 'Usar convite', icon: const Icon(Icons.input_rounded)),
          ]),
        ),
        Expanded(
          child: FutureBuilder<List<SocialConversation>>(
            future: _conversas,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) return SocialFalhaTela(texto: '${snapshot.error}', tentar: () => setState(_recarregar));
              final items = snapshot.data ?? const <SocialConversation>[];
              if (items.isEmpty) {
                return Center(child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.groups_2_outlined, size: 44, color: cs.primary),
                    const SizedBox(height: 12),
                    const Text('Você ainda não está em grupos', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text('Crie um grupo ou entre usando um convite privado.', textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
                  ]),
                ));
              }
              return RefreshIndicator(
                onRefresh: () async => setState(_recarregar),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 3),
                  itemBuilder: (context, index) {
                    final c = items[index];
                    return Card(margin: EdgeInsets.zero, child: ListTile(
                      leading: CircleAvatar(backgroundColor: cs.primaryContainer, foregroundColor: cs.onPrimaryContainer, child: const Icon(Icons.groups_2_rounded)),
                      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text(c.lastMessage, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: c.isCourseGroup
                          ? const Chip(visualDensity: VisualDensity.compact, label: Text('MATÉRIA'))
                          : const Icon(Icons.chevron_right_rounded),
                      onTap: () async {
                        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SocialChatTela(repository: widget.repository, conversation: c)));
                        if (mounted) setState(_recarregar);
                      },
                    ));
                  },
                ),
              );
            },
          ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirGrupo,
        icon: const Icon(Icons.group_add_rounded),
        label: const Text('Criar grupo'),
      ),
    );
  }
}

class _SocialChatTela extends StatefulWidget {
  final SocialRepository repository;
  final SocialConversation conversation;
  const _SocialChatTela({required this.repository, required this.conversation});
  @override
  State<_SocialChatTela> createState() => _SocialChatTelaState();
}

class _SocialChatTelaState extends State<_SocialChatTela> {
  final _texto = TextEditingController();
  bool _enviando = false;

  @override
  void dispose() { _texto.dispose(); super.dispose(); }

  Future<void> _enviar() async {
    final value = _texto.text.trim();
    if (value.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await widget.repository.sendMessage(widget.conversation.id, value);
      _texto.clear();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: Column(children: [
        Expanded(child: StreamBuilder<List<SocialMessage>>(
          stream: widget.repository.messages(widget.conversation.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Não foi possível abrir as mensagens protegidas. ${snapshot.error}', textAlign: TextAlign.center)));
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final userId = widget.repository.currentUser?.id;
            final messages = snapshot.data!;
            if (messages.isEmpty) return const Center(child: Text('Comece a conversa.'));
            return ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final m = messages[index];
                final mine = m.senderId == userId;
                return Align(alignment: mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .8),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.fromLTRB(13, 9, 11, 6),
                  decoration: BoxDecoration(
                    color: mine ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.only(topLeft: const Radius.circular(17), topRight: const Radius.circular(17), bottomLeft: Radius.circular(mine ? 17 : 5), bottomRight: Radius.circular(mine ? 5 : 17)),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!mine) Text(m.senderName, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 11)),
                    Text(m.text),
                    Align(alignment: Alignment.bottomRight, child: Text(TimeOfDay.fromDateTime(m.createdAt).format(context), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))),
                  ]),
                ));
              },
            );
          },
        )),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 7, 12, 10), child: Row(children: [
          Expanded(child: TextField(controller: _texto, minLines: 1, maxLines: 5, textCapitalization: TextCapitalization.sentences, decoration: const InputDecoration(hintText: 'Mensagem'))),
          const SizedBox(width: 8),
          IconButton.filled(onPressed: _enviando ? null : _enviar, tooltip: 'Enviar mensagem', icon: _enviando ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward_rounded)),
        ]))),
      ]),
    );
  }
}

class SocialFalhaTela extends StatelessWidget {
  final String texto;
  final VoidCallback? tentar;
  const SocialFalhaTela({super.key, required this.texto, this.tentar});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(leading: IconButton(tooltip: 'Voltar ao Acadêmico', icon: const Icon(Icons.school_outlined), onPressed: () => Navigator.of(context).pop()), title: const Text('Conexões')),
        body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded, size: 46),
          const SizedBox(height: 14),
          const Text('Não foi possível conectar ao servidor Social.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Text(texto, textAlign: TextAlign.center),
          if (tentar != null) ...[const SizedBox(height: 14), FilledButton(onPressed: tentar, child: const Text('Tentar novamente'))],
        ]))),
      );
}
