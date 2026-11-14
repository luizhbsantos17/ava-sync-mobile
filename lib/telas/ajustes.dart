import 'package:material_ui/material_ui.dart';

import '../armazenamento.dart';
import '../atualizacao.dart';
import '../calendario.dart';
import '../compromissos.dart';
import '../config.dart';
import '../estado_app.dart';
import '../fundo.dart';
import '../ia.dart';
import '../util.dart';
import 'atualizar.dart';

class AjustesAba extends StatefulWidget {
  const AjustesAba({super.key});
  @override
  State<AjustesAba> createState() => _AjustesAbaState();
}

class _AjustesAbaState extends State<AjustesAba> {
  int? _espaco;
  bool _verificandoAtualizacao = false;

  @override
  void initState() {
    super.initState();
    Store.tamanho().then((v) => mounted ? setState(() => _espaco = v) : null);
  }

  Future<void> _mudar(Future<void> Function() f, {bool reagendar = false}) async {
    await f();
    if (reagendar) await agendar();
    setState(() {});
  }

  Future<void> _verificarAtualizacao() async {
    if (_verificandoAtualizacao) return;
    setState(() => _verificandoAtualizacao = true);
    try {
      final info = await Atualizacao.verificar();
      if (!mounted) return;
      if (info.disponivel) {
        await oferecerAtualizacao(context, info);
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.check_circle_outline_rounded),
            title: const Text('Você já está na versão mais recente'),
            content: Text('Build instalado: ${info.buildInstalado}.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.cloud_off_outlined),
          title: const Text('Não foi possível verificar'),
          content: Text('$e'.replaceFirst('Exception: ', '')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
        ),
      );
    } finally {
      if (mounted) setState(() => _verificandoAtualizacao = false);
    }
  }

  Future<void> _reagendarLembretes() async {
    final lista = compromissos(app.snap, Cfg.atualManual);
    await Notif.agendarLembretes(Cfg.lembretePrazo ? lembretes(lista, agoraSeg()) : const []);
  }

  void _aviso(String t) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  /// Escolhe a agenda (Google primeiro). Devolve false se nao deu.
  Future<bool> _escolherAgenda() async {
    if (!await Calendario.pedirPermissao()) {
      _aviso('Sem permissão para a agenda. Libere em Configurações > Apps > AVA Sync > Permissões.');
      return false;
    }
    final agendas = await Calendario.agendas();
    if (!mounted) return false;
    if (agendas.isEmpty) {
      _aviso('Nenhuma agenda editável no celular. Adicione sua conta Google em Configurações > Contas.');
      return false;
    }
    final escolha = await showDialog<AgendaInfo>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Em qual agenda colocar os prazos?'),
        children: [
          for (final a in agendas)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(a.google ? Icons.event_available : Icons.event_note),
                title: Text(a.nome),
                subtitle: a.conta.isEmpty ? null : Text(a.google ? '${a.conta} · Google Agenda' : a.conta),
                selected: a.id == Cfg.calendarioId,
              ),
            ),
        ],
      ),
    );
    if (escolha == null) return false;
    if (Cfg.calendarioId.isNotEmpty && Cfg.calendarioId != escolha.id) await Calendario.limpar();
    await Cfg.setCalendarioId(escolha.id);
    await Cfg.setCalendarioNome(escolha.rotulo);
    return true;
  }

  Future<void> _sincronizarAgenda() async {
    try {
      final n = await Calendario.sincronizar(compromissos(app.snap, Cfg.atualManual));
      _aviso(n == 0 ? 'Agenda já estava em dia.' : 'Agenda atualizada ($n evento(s)).');
    } catch (e) {
      _aviso('Não consegui atualizar a agenda: $e');
    }
  }

  Future<void> _ligarAgenda(bool v) async {
    if (v) {
      if (Cfg.calendarioId.isEmpty && !await _escolherAgenda()) return;
      await Cfg.setCalendario(true);
      if (mounted) setState(() {});
      await _sincronizarAgenda();
    } else {
      final apagar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desligar a agenda?'),
          content: const Text('Quer apagar da agenda os próximos eventos que o AVA Sync criou?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Manter eventos')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
          ],
        ),
      );
      if (apagar == null) return;
      if (apagar) await Calendario.limpar();
      await Cfg.setCalendario(false);
      if (mounted) setState(() {});
    }
  }

  Future<String?> _editarTexto(String titulo, String atual, {String? ajuda, bool senha = false}) {
    final c = TextEditingController(text: atual);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
            controller: c,
            obscureText: senha,
            autofocus: true,
            decoration: InputDecoration(helperText: ajuda, helperMaxLines: 4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
  }

  Future<void> _lista(String titulo, List<String> atual, Future<void> Function(List<String>) salvar, String ajuda) async {
    final v = await _editarTexto(titulo, atual.join(', '), ajuda: ajuda);
    if (v == null) return;
    await salvar(v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList());
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cab = Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary);
    Widget secao(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 4), child: Text(t, style: cab));
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      secao('Conta'),
      ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(Cfg.usuarioNome.isEmpty ? 'Conectado' : Cfg.usuarioNome),
        subtitle: Text(Cfg.site),
      ),
      ListTile(
        leading: const Icon(Icons.logout),
        title: const Text('Sair'),
        subtitle: const Text('Apaga a chave de acesso deste celular'),
        onTap: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sair?'),
              content: const Text('A chave de acesso será apagada. Os arquivos baixados continuam no celular. '
                  'Para revogar a chave no servidor: AVA > Preferências > Chaves de segurança.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair')),
              ],
            ),
          );
          if (ok == true) await app.sair();
        },
      ),
      secao('Matérias'),
      ListTile(
        leading: const Icon(Icons.filter_alt_off_outlined),
        title: const Text('Ignorar matérias'),
        subtitle: Text(Cfg.ignorarCursos.isEmpty ? 'nenhuma' : Cfg.ignorarCursos.join(', ')),
        onTap: () => _lista('Ignorar matérias', Cfg.ignorarCursos, Cfg.setIgnorarCursos,
            'Trechos de nome separados por vírgula. Ex.: Biblioteca Virtual, 2025/2'),
      ),
      ListTile(
        leading: const Icon(Icons.filter_alt_outlined),
        title: const Text('Somente estas matérias'),
        subtitle: Text(Cfg.somenteCursos.isEmpty ? 'todas em andamento' : Cfg.somenteCursos.join(', ')),
        onTap: () => _lista('Somente estas matérias', Cfg.somenteCursos, Cfg.setSomenteCursos,
            'Deixe vazio para todas. Trechos de nome separados por vírgula.'),
      ),
      secao('Sincronização'),
      SwitchListTile(
        secondary: const Icon(Icons.sync),
        title: const Text('Sincronizar automaticamente'),
        subtitle: Text('A cada ${Cfg.intervaloHoras} h, em segundo plano'),
        value: Cfg.autoSync,
        onChanged: (v) => _mudar(() => Cfg.setAutoSync(v), reagendar: true),
      ),
      ListTile(
        leading: const Icon(Icons.timer_outlined),
        title: const Text('Intervalo'),
        trailing: DropdownButton<int>(
          value: Cfg.intervaloHoras,
          items: const [
            DropdownMenuItem(value: 6, child: Text('6 h')),
            DropdownMenuItem(value: 12, child: Text('12 h')),
            DropdownMenuItem(value: 24, child: Text('24 h')),
          ],
          onChanged: (v) => _mudar(() => Cfg.setIntervaloHoras(v ?? 12), reagendar: true),
        ),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.wifi),
        title: const Text('Em segundo plano, só no Wi-Fi'),
        value: Cfg.soWifi,
        onChanged: (v) => _mudar(() => Cfg.setSoWifi(v), reagendar: true),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Notificar novidades'),
        value: Cfg.notificacoes,
        onChanged: (v) => _mudar(() async {
          await Cfg.setNotificacoes(v);
          if (v) await Notif.pedirPermissao();
        }),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.alarm),
        title: const Text('Lembrar prazos'),
        subtitle: const Text('3 dias, 1 dia e 3 horas antes de entregas pendentes, questionários e provas'),
        value: Cfg.lembretePrazo,
        onChanged: (v) => _mudar(() async {
          await Cfg.setLembretePrazo(v);
          if (v) await Notif.pedirPermissao();
          await _reagendarLembretes();
        }),
      ),
      secao('Agenda do celular (Google Agenda)'),
      SwitchListTile(
        secondary: const Icon(Icons.calendar_month_outlined),
        title: const Text('Colocar prazos e provas na agenda'),
        subtitle: const Text('Cria e atualiza os eventos sozinho a cada sincronização. '
            'Numa agenda da conta Google, aparece também no Google Agenda.'),
        value: Cfg.calendario,
        onChanged: _ligarAgenda,
      ),
      if (Cfg.calendario) ...[
        ListTile(
          leading: const Icon(Icons.event_note_outlined),
          title: const Text('Agenda'),
          subtitle: Text(Cfg.calendarioNome.isEmpty ? 'Escolher' : Cfg.calendarioNome),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            if (await _escolherAgenda()) {
              if (mounted) setState(() {});
              await _sincronizarAgenda();
            }
          },
        ),
        SwitchListTile(
          secondary: const Icon(Icons.school_outlined),
          title: const Text('Só provas'),
          subtitle: const Text('Sem entregas de tarefas e questionários comuns'),
          value: Cfg.calendarioSoProvas,
          onChanged: (v) async {
            await Cfg.setCalendarioSoProvas(v);
            if (mounted) setState(() {});
            await _sincronizarAgenda();
          },
        ),
        ListTile(
          leading: const Icon(Icons.sync_alt),
          title: const Text('Atualizar agenda agora'),
          onTap: _sincronizarAgenda,
        ),
      ],
      secao('Arquivos'),
      SwitchListTile(
        secondary: const Icon(Icons.download_outlined),
        title: const Text('Baixar materiais automaticamente'),
        subtitle: const Text('Desligado: baixa só quando você abrir'),
        value: Cfg.baixarArquivos,
        onChanged: (v) => _mudar(() => Cfg.setBaixarArquivos(v)),
      ),
      SwitchListTile(
        secondary: const Icon(Icons.link),
        title: const Text('Baixar arquivos de links'),
        subtitle: const Text('PDFs e slides em links públicos. Vídeos e sites com login ficam só como link.'),
        value: Cfg.baixarLinks,
        onChanged: (v) => _mudar(() => Cfg.setBaixarLinks(v)),
      ),
      ListTile(
        leading: const Icon(Icons.straighten),
        title: const Text('Tamanho máximo por arquivo'),
        trailing: DropdownButton<int>(
          value: [20, 50, 100, 200, 500].contains(Cfg.maxMb) ? Cfg.maxMb : 100,
          items: [for (final v in [20, 50, 100, 200, 500]) DropdownMenuItem(value: v, child: Text('$v MB'))],
          onChanged: (v) => _mudar(() => Cfg.setMaxMb(v ?? 100)),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.sd_storage_outlined),
        title: const Text('Espaço usado'),
        subtitle: Text(_espaco == null ? 'calculando...' : fmtTamanho(_espaco!)),
        trailing: TextButton(
          child: const Text('Limpar'),
          onPressed: () async {
            final ok = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Apagar arquivos baixados?'),
                content: const Text('PDFs, livros e imagens serão apagados deste celular. Eles voltam na próxima sincronização.'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
                ],
              ),
            );
            if (ok != true) return;
            await Store.limparArquivos();
            final v = await Store.tamanho();
            if (mounted) setState(() => _espaco = v);
          },
        ),
      ),
      secao('Guias por IA (opcional)'),
      ListTile(
        leading: const Icon(Icons.auto_awesome_outlined),
        title: const Text('IA ativa'),
        subtitle: const Text('Trocar não apaga nada: o conteúdo de cada IA fica salvo separado.'),
        trailing: DropdownButton<String>(
          value: Cfg.iaAtiva,
          items: [
            const DropdownMenuItem(value: 'nenhum', child: Text('Nenhuma')),
            for (final s in iaSlots.keys) DropdownMenuItem(value: s, child: Text(nomeSlot(s).split(' ').first)),
          ],
          onChanged: (v) => _mudar(() => Cfg.setIaAtiva(v ?? 'nenhum')),
        ),
      ),
      for (final s in iaSlots.keys) _IaSlot(slot: s, aoMudar: () => setState(() {})),
      SwitchListTile(
        secondary: const Icon(Icons.picture_as_pdf_outlined),
        title: const Text('Enviar os PDFs da matéria'),
        subtitle: const Text('Gemini, ChatGPT e Claude leem os PDFs junto (até 12 MB por pedido). Gasta mais da sua cota.'),
        value: Cfg.iaEnviarPdfs,
        onChanged: (v) => _mudar(() => Cfg.setIaEnviarPdfs(v)),
      ),
      ListTile(
        leading: const Icon(Icons.text_snippet_outlined),
        title: const Text('Texto máximo por pedido'),
        subtitle: const Text('Quanto do conteúdo da matéria vai junto'),
        trailing: DropdownButton<int>(
          value: [60000, 120000, 250000, 500000].contains(Cfg.iaMaxContexto) ? Cfg.iaMaxContexto : 120000,
          items: const [
            DropdownMenuItem(value: 60000, child: Text('pequeno')),
            DropdownMenuItem(value: 120000, child: Text('médio')),
            DropdownMenuItem(value: 250000, child: Text('grande')),
            DropdownMenuItem(value: 500000, child: Text('enorme')),
          ],
          onChanged: (v) => _mudar(() => Cfg.setIaMaxContexto(v ?? 120000)),
        ),
      ),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text(
            'O material da matéria (textos, avisos, enunciados e, se ligado, os PDFs) é enviado ao provedor escolhido '
            'quando você toca em "Gerar". O token do AVA nunca é enviado.',
            style: TextStyle(fontSize: 12)),
      ),
      secao('Aplicativo'),
      ListTile(
        leading: const Icon(Icons.system_update_alt_rounded),
        title: Text(_verificandoAtualizacao ? 'Verificando atualizações...' : 'Verificar atualizações'),
        subtitle: Text(Atualizacao.buildInstalado == 0
            ? 'Build de desenvolvimento · buscar uma versão no GitHub'
            : 'Build instalado: ${Atualizacao.buildInstalado} · buscar uma versão no GitHub'),
        trailing: _verificandoAtualizacao
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.chevron_right),
        onTap: _verificandoAtualizacao ? null : _verificarAtualizacao,
      ),
      SwitchListTile(
        secondary: const Icon(Icons.update),
        title: const Text('Procurar atualizações sozinho'),
        subtitle: const Text('Ao abrir o app e em segundo plano; avisa quando sair versão nova'),
        value: Cfg.verificarAtualizacoes,
        onChanged: (v) => _mudar(() => Cfg.setVerificarAtualizacoes(v), reagendar: true),
      ),
      secao('Sobre'),
      ListTile(
        leading: const Icon(Icons.info_outline),
        title: Text('AVA Sync · versão 0.6.0 (build ${Atualizacao.buildInstalado})'),
        subtitle: const Text('Código aberto (MIT). Use só com a sua própria conta e respeite as regras da sua instituição.'),
      ),
    ]);
  }
}


/// Configuracao de um provedor de IA: modelo, chave, URL (se precisar) e teste.
class _IaSlot extends StatefulWidget {
  final String slot;
  final VoidCallback aoMudar;
  const _IaSlot({required this.slot, required this.aoMudar});
  @override
  State<_IaSlot> createState() => _IaSlotState();
}

class _IaSlotState extends State<_IaSlot> {
  bool _temChave = false;
  bool _ocupado = false;
  String? _resultado;

  String get s => widget.slot;

  static const _ondeChave = {
    'gemini': 'Chave grátis em aistudio.google.com (menu "Get API key"). O plano gratuito permite modelos "Flash".',
    'openai': 'Chave em platform.openai.com (API keys). A API é paga à parte do ChatGPT Plus.',
    'anthropic': 'Chave em console.anthropic.com (API keys). A API é paga à parte do Claude Pro.',
    'compat': 'OpenRouter (openrouter.ai, tem modelos grátis), Groq (console.groq.com) ou Ollama no seu PC.',
  };

  @override
  void initState() {
    super.initState();
    Cfg.iaChave(s).then((v) => mounted ? setState(() => _temChave = (v ?? '').isNotEmpty) : null);
  }

  Future<String?> _texto(String titulo, String atual, {bool senha = false, String? ajuda}) {
    final c = TextEditingController(text: atual);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: TextField(
            controller: c, obscureText: senha, autofocus: true, decoration: InputDecoration(helperText: ajuda, helperMaxLines: 4)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Salvar')),
        ],
      ),
    );
  }

  Future<void> _escolherModelo() async {
    setState(() => _ocupado = true);
    List<String> modelos = [];
    String? erro;
    try {
      modelos = await listarModelos(s);
    } catch (e) {
      erro = '$e';
    }
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (modelos.isEmpty) {
      final v = await _texto('Modelo', Cfg.iaModelo(s),
          ajuda: '${erro == null ? '' : 'Não consegui listar ($erro). '}Digite o nome do modelo. Sugestão: ${iaSlots[s]!.dica}');
      if (v != null) await Cfg.setIaModelo(s, v);
    } else {
      final v = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (_, sc) => ListView(controller: sc, children: [
            const ListTile(title: Text('Modelos da sua conta', style: TextStyle(fontWeight: FontWeight.bold))),
            for (final m in modelos)
              ListTile(title: Text(m), selected: m == Cfg.iaModelo(s), onTap: () => Navigator.pop(ctx, m)),
          ]),
        ),
      );
      if (v != null) await Cfg.setIaModelo(s, v);
    }
    setState(() {});
    widget.aoMudar();
  }

  Future<void> _testar() async {
    setState(() {
      _ocupado = true;
      _resultado = null;
    });
    try {
      final r = await testar(s);
      _resultado = 'OK: ${r.trim()}';
    } catch (e) {
      _resultado = 'Falhou: $e';
    }
    if (mounted) setState(() => _ocupado = false);
  }

  @override
  Widget build(BuildContext context) {
    final ativa = Cfg.iaAtiva == s;
    return ExpansionTile(
      leading: Icon(ativa ? Icons.radio_button_checked : Icons.radio_button_off,
          color: ativa ? Theme.of(context).colorScheme.primary : null),
      title: Text(nomeSlot(s)),
      subtitle: Text(Cfg.iaModelo(s).isEmpty ? 'não configurado' : '${Cfg.iaModelo(s)}${_temChave ? '' : ' · sem chave'}'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Text(_ondeChave[s]!, style: const TextStyle(fontSize: 12)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_outlined),
          title: Text(_temChave ? 'Chave salva (criptografada)' : 'Colocar chave da API'),
          onTap: () async {
            final v = await _texto('Chave da API', '', senha: true, ajuda: 'Deixe vazio e salve para apagar.');
            if (v == null) return;
            await Cfg.setIaChave(s, v);
            setState(() => _temChave = v.trim().isNotEmpty);
          },
        ),
        if (s == 'compat')
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.dns_outlined),
            title: const Text('URL base'),
            subtitle: Text(Cfg.iaBaseUrl(s).isEmpty ? 'https://openrouter.ai/api/v1' : Cfg.iaBaseUrl(s)),
            onTap: () async {
              final v = await _texto('URL base', Cfg.iaBaseUrl(s),
                  ajuda: 'OpenRouter: https://openrouter.ai/api/v1\nGroq: https://api.groq.com/openai/v1\n'
                      'Ollama no PC (mesma rede): http://IP-DO-PC:11434/v1');
              if (v != null) {
                await Cfg.setIaBaseUrl(s, v);
                setState(() {});
              }
            },
          ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.memory),
          title: const Text('Modelo'),
          subtitle: Text(Cfg.iaModelo(s).isEmpty ? 'toque para escolher (lista da sua conta)' : Cfg.iaModelo(s)),
          onTap: _ocupado ? null : _escolherModelo,
        ),
        Row(children: [
          OutlinedButton.icon(
              onPressed: _ocupado || Cfg.iaModelo(s).isEmpty ? null : _testar,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Testar')),
          const SizedBox(width: 8),
          if (!ativa)
            TextButton(
                onPressed: () async {
                  await Cfg.setIaAtiva(s);
                  widget.aoMudar();
                },
                child: const Text('Usar esta')),
          if (_ocupado) const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ]),
        if (_resultado != null)
          Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(_resultado!, style: const TextStyle(fontSize: 13))),
        const SizedBox(height: 8),
      ],
    );
  }
}
