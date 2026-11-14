import 'package:material_ui/material_ui.dart';

import '../social/backend.dart';
import 'social_online.dart';

/// Area social independente da navegacao academica. Sem configuracao de servidor
/// mostra uma amostra local; com Supabase configurado usa o repositorio remoto.
class SocialTela extends StatefulWidget {
  const SocialTela({super.key});

  @override
  State<SocialTela> createState() => _SocialTelaState();
}

class _SocialTelaState extends State<SocialTela> {
  int _secao = 0;
  final List<_Conversa> _conversas = [
    _Conversa(
      nome: 'Trabalho de Redes',
      ultima: 'Fechou, vou revisar a parte 2 hoje',
      hora: '14:32',
      membros: 4,
      grupo: true,
      mensagens: [
        _Mensagem('Ana', 'Pessoal, subi o rascunho do trabalho.', '14:18', recebida: true),
        _Mensagem('Você', 'Fechou, vou revisar a parte 2 hoje', '14:32'),
      ],
    ),
    _Conversa(
      nome: 'Marina Costa',
      ultima: 'te mando o material depois da aula',
      hora: 'Ontem',
      mensagens: [_Mensagem('Marina', 'te mando o material depois da aula', 'Ontem', recebida: true)],
    ),
    _Conversa(
      nome: 'Projeto Integrador',
      ultima: 'Rafael: reunião amanhã às 10?',
      hora: 'Ontem',
      membros: 5,
      grupo: true,
      mensagens: [_Mensagem('Rafael', 'reunião amanhã às 10?', 'Ontem', recebida: true)],
    ),
  ];

  Future<void> _criarGrupo() async {
    final nome = TextEditingController();
    final descricao = TextEditingController();
    final criar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Criar grupo'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nome, autofocus: true, maxLength: 48, decoration: const InputDecoration(labelText: 'Nome do grupo')),
          const SizedBox(height: 8),
          TextField(controller: descricao, maxLength: 120, decoration: const InputDecoration(labelText: 'Sobre o grupo (opcional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Criar')),
        ],
      ),
    );
    if (criar == true && nome.text.trim().isNotEmpty && mounted) {
      setState(() {
        _conversas.insert(0, _Conversa(
          nome: nome.text.trim(),
          ultima: 'Grupo criado · convide seus amigos',
          hora: 'Agora',
          membros: 1,
          grupo: true,
          mensagens: [
            _Mensagem('Sistema', descricao.text.trim().isEmpty ? 'Grupo criado.' : descricao.text.trim(), 'Agora', recebida: true),
          ],
        ));
        _secao = 1;
      });
    }
    nome.dispose();
    descricao.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repository = SocialBackend.repository;
    if (repository != null) return SocialOnlineTela(repository: repository);
    if (SocialBackend.configurationStarted || SocialBackend.initializationError != null) {
      return SocialFalhaTela(texto: SocialBackend.initializationError ?? 'Configure a URL e a chave pública do projeto Supabase.');
    }
    final cs = Theme.of(context).colorScheme;
    final filtradas = _conversas.where((c) => _secao == 0 || c.grupo).toList();
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 52,
        leading: IconButton(
          tooltip: 'Voltar ao Acadêmico',
          icon: const Icon(Icons.school_outlined),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text('Conexões'),
        actions: [
          IconButton(tooltip: 'Criar grupo', onPressed: _criarGrupo, icon: const Icon(Icons.group_add_outlined)),
          IconButton(tooltip: 'Nova conversa', onPressed: _novaConversa, icon: const Icon(Icons.edit_outlined)),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.tertiaryContainer.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline_rounded, size: 18, color: cs.onTertiaryContainer),
            const SizedBox(width: 9),
            Expanded(child: Text(
              'Prévia local. Configure o Supabase para criar sua conta e sincronizar grupos; esta amostra não envia nem salva mensagens.',
              style: TextStyle(fontSize: 12, height: 1.35, color: cs.onTertiaryContainer),
            )),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text('Seu espaço', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5))),
            IconButton(onPressed: () {}, tooltip: 'Buscar conversas', icon: const Icon(Icons.search_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Conversas'), icon: Icon(Icons.chat_bubble_outline_rounded)),
              ButtonSegment(value: 1, label: Text('Grupos'), icon: Icon(Icons.groups_2_outlined)),
            ],
            selected: {_secao},
            onSelectionChanged: (s) => setState(() => _secao = s.first),
          ),
        ),
        Expanded(
          child: filtradas.isEmpty
              ? const Center(child: Text('Nenhum grupo por aqui ainda.'))
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                  itemCount: filtradas.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 2),
                  itemBuilder: (context, i) {
                    final c = filtradas[i];
                    return Card(
                      margin: EdgeInsets.zero,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                        leading: _AvatarSocial(nome: c.nome, grupo: c.grupo),
                        title: Row(children: [
                          Expanded(child: Text(c.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                          Text(c.hora, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                        ]),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Row(children: [
                            Expanded(child: Text(c.ultima, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            if (c.grupo) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.people_alt_outlined, size: 14, color: cs.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Text('${c.membros}', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                            ],
                          ]),
                        ),
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => _ChatTela(conversa: c, aoEnviar: (m) => setState(() {
                            c.mensagens.add(m);
                            c.ultima = m.texto;
                            c.hora = m.hora;
                          })),
                        )),
                      ),
                    );
                  },
                ),
        ),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _secao == 1 ? _criarGrupo : _novaConversa,
        icon: Icon(_secao == 1 ? Icons.group_add_rounded : Icons.add_comment_rounded),
        label: Text(_secao == 1 ? 'Criar grupo' : 'Nova conversa'),
      ),
    );
  }

  Future<void> _novaConversa() async {
    final nome = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova conversa'),
        content: TextField(controller: nome, autofocus: true, decoration: const InputDecoration(labelText: 'Nome da pessoa')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar')),
        ],
      ),
    );
    if (ok == true && nome.text.trim().isNotEmpty && mounted) {
      final c = _Conversa(nome: nome.text.trim(), ultima: 'Conversa iniciada', hora: 'Agora', mensagens: []);
      setState(() => _conversas.insert(0, c));
      final navigator = Navigator.of(context);
      await navigator.push(MaterialPageRoute(builder: (_) => _ChatTela(conversa: c, aoEnviar: (m) => setState(() {
        c.mensagens.add(m);
        c.ultima = m.texto;
        c.hora = m.hora;
      }))));
    }
    nome.dispose();
  }
}

class _Conversa {
  final String nome;
  String ultima;
  String hora;
  final int membros;
  final bool grupo;
  final List<_Mensagem> mensagens;

  _Conversa({required this.nome, required this.ultima, required this.hora, this.membros = 2, this.grupo = false, required this.mensagens});
}

class _Mensagem {
  final String autor;
  final String texto;
  final String hora;
  final bool recebida;
  _Mensagem(this.autor, this.texto, this.hora, {this.recebida = false});
}

class _AvatarSocial extends StatelessWidget {
  final String nome;
  final bool grupo;
  const _AvatarSocial({required this.nome, required this.grupo});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final iniciais = nome.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).take(2).map((s) => s[0].toUpperCase()).join();
    return CircleAvatar(
      radius: 25,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      child: grupo ? const Icon(Icons.groups_2_rounded) : Text(iniciais, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}

class _ChatTela extends StatefulWidget {
  final _Conversa conversa;
  final ValueChanged<_Mensagem> aoEnviar;
  const _ChatTela({required this.conversa, required this.aoEnviar});

  @override
  State<_ChatTela> createState() => _ChatTelaState();
}

class _ChatTelaState extends State<_ChatTela> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();

  void _enviar() {
    final texto = _texto.text.trim();
    if (texto.isEmpty) return;
    final agora = TimeOfDay.now().format(context);
    widget.aoEnviar(_Mensagem('Você', texto, agora));
    setState(() {});
    _texto.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          _AvatarSocial(nome: widget.conversa.nome, grupo: widget.conversa.grupo),
          const SizedBox(width: 11),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.conversa.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            Text(widget.conversa.grupo ? '${widget.conversa.membros} participantes' : 'Conversa privada', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ])),
        ]),
        actions: [IconButton(tooltip: 'Opções da conversa', onPressed: () {}, icon: const Icon(Icons.more_vert))],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
            itemCount: widget.conversa.mensagens.length,
            itemBuilder: (context, i) {
              final m = widget.conversa.mensagens[i];
              final minha = !m.recebida;
              return Align(
                alignment: minha ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * .78),
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.fromLTRB(13, 9, 11, 7),
                  decoration: BoxDecoration(
                    color: minha ? cs.primaryContainer : cs.surfaceContainerHigh,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(17), topRight: const Radius.circular(17),
                      bottomLeft: Radius.circular(minha ? 17 : 5), bottomRight: Radius.circular(minha ? 5 : 17),
                    ),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (widget.conversa.grupo && !minha) ...[
                      Text(m.autor, style: TextStyle(color: cs.primary, fontSize: 11, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                    ],
                    Text(m.texto),
                    Align(alignment: Alignment.bottomRight, child: Text(m.hora, style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant))),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(tooltip: 'Anexar arquivo', onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Anexos entram quando o servidor estiver conectado.'))), icon: const Icon(Icons.add_circle_outline_rounded)),
              Expanded(child: TextField(
                controller: _texto,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Mensagem', contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                onSubmitted: (_) => _enviar(),
              )),
              const SizedBox(width: 8),
              IconButton.filled(tooltip: 'Enviar', onPressed: _enviar, icon: const Icon(Icons.arrow_upward_rounded)),
            ]),
          ),
        ),
      ]),
    );
  }
}
