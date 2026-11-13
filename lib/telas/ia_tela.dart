import 'dart:io';

import 'package:flutter/services.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:material_ui/material_ui.dart';
import 'package:share_plus/share_plus.dart';

import '../armazenamento.dart';

import '../config.dart';
import '../estado_app.dart';
import '../ia.dart';
import '../util.dart';
import 'comum.dart';

String mdParaHtml(String texto) => md.markdownToHtml(texto, extensionSet: md.ExtensionSet.gitHubFlavored);

/// Conteudo das IAs para um item (materia, atividade ou prova).
/// Mostra o da IA ativa; os das outras ficam a um toque, e nada e apagado ao trocar.
class IaTela extends StatefulWidget {
  final dynamic cursoId;
  final String chave; // materia | tarefa_12 | quiz_3 | evento_9
  final String kind; // materia | atividade | prova
  final String nome;
  final String? tipo;
  final Map<String, dynamic>? item;
  const IaTela(
      {super.key, required this.cursoId, required this.chave, required this.kind, required this.nome, this.tipo, this.item});

  @override
  State<IaTela> createState() => _IaTelaState();
}

class _IaTelaState extends State<IaTela> {
  Map<String, Guia> _guias = {};
  String? _vendo;
  bool _gerando = false;
  String _progresso = '';
  String? _ultimaOrigem;

  Map<String, dynamic>? get _curso => app.cursoPorId(widget.cursoId);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final c = _curso;
    if (c == null) return;
    final g = await guiasDeTodas(c, widget.chave);
    setState(() {
      _guias = g;
      final ativa = Cfg.iaAtiva;
      _vendo = g.containsKey(ativa) ? ativa : (g.keys.firstOrNull ?? ativa);
    });
  }

  Future<void> _gerar() async {
    final slot = Cfg.iaAtiva;
    final c = _curso;
    if (c == null || slot == 'nenhum') return;
    setState(() {
      _gerando = true;
      _progresso = 'Preparando...';
    });
    try {
      await gerarGuia(
        curso: c,
        slot: slot,
        chave: widget.chave,
        kind: widget.kind,
        nome: widget.nome,
        item: widget.item,
        tipo: widget.tipo,
        progresso: (p) => mounted ? setState(() => _progresso = p) : null,
      );
      await _carregar();
      setState(() => _vendo = slot);
    } catch (e) {
      if (mounted) aviso(context, 'Não gerou: $e');
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  Future<Pedido?> _montar(String origem) async {
    final c = _curso;
    if (c == null) return null;
    return montarPedido(
        curso: c, origem: origem, kind: widget.kind, nome: widget.nome, item: widget.item, tipo: widget.tipo, pdfs: true);
  }

  /// Monta o pedido e manda para um app de chat (Claude, ChatGPT, Gemini...).
  Future<void> _fazerNoApp() async {
    final origem = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Fazer num app de chat', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('O AVA Sync monta o pedido com o material da matéria. Você manda no app, '
                'copia a resposta e cola aqui em "Colar resposta". Usa a sua assinatura (ex.: Claude Pro), sem API.'),
          ),
          for (final e in iaApps.entries)
            ListTile(leading: const Icon(Icons.chat_outlined), title: Text(e.value), onTap: () => Navigator.pop(ctx, e.key)),
        ]),
      ),
    );
    if (origem == null) return;
    setState(() {
      _gerando = true;
      _progresso = 'Montando o pedido com o material...';
    });
    try {
      final ped = await _montar(origem);
      if (ped == null) return;
      final dir = Directory('${(await Store.base()).path}/_pedidos');
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      final arq = File('${dir.path}/pedido_${widget.chave}.md');
      await arq.writeAsString(ped.completo);
      final pdfs = <XFile>[];
      for (final a in ped.pdfs) {
        final f = File('${dir.path}/${a.nome}');
        await f.writeAsBytes(a.bytes);
        pdfs.add(XFile(f.path, mimeType: 'application/pdf'));
      }
      _ultimaOrigem = origem;
      if (!mounted) return;
      final como = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Pedido pronto'),
          content: Text('Pedido com ${(ped.completo.length / 1000).toStringAsFixed(0)} mil caracteres'
              '${pdfs.isEmpty ? '' : ' e ${pdfs.length} PDF(s)'}.\n\n'
              '• Compartilhar: escolha o app (ex.: Claude) e envie. Vai como arquivo pedido.md + PDFs.\n'
              '• Copiar: cola o texto direto na conversa (sem os PDFs).\n\n'
              'Depois copie a resposta e volte aqui em "Colar resposta".'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, 'copiar'), child: const Text('Copiar texto')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'compartilhar'), child: const Text('Compartilhar')),
          ],
        ),
      );
      if (como == 'copiar') {
        await Clipboard.setData(ClipboardData(text: ped.completo));
        if (mounted) aviso(context, 'Pedido copiado. Cole na conversa do app.');
      } else if (como == 'compartilhar') {
        await SharePlus.instance.share(ShareParams(
          text: 'Leia o arquivo pedido_${widget.chave}.md${pdfs.isEmpty ? '' : ' e os PDFs anexados'} e siga as instruções dele.',
          files: [XFile(arq.path, mimeType: 'text/markdown'), ...pdfs],
        ));
      }
    } catch (e) {
      if (mounted) aviso(context, 'Não deu para montar o pedido: $e');
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  /// Cola a resposta de um app de chat e salva como conteudo daquela origem.
  Future<void> _colar() async {
    var origem = _ultimaOrigem ?? 'app_claude';
    final ctrl = TextEditingController();
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Colar resposta'),
          content: SizedBox(
            width: 500,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: origem,
                decoration: const InputDecoration(labelText: 'Quem gerou'),
                items: [for (final e in iaApps.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => origem = v ?? origem),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: TextField(
                  controller: ctrl,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(hintText: 'Cole aqui a resposta inteira', border: OutlineInputBorder()),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () async {
                    final d = await Clipboard.getData(Clipboard.kTextPlain);
                    if (d?.text != null) set(() => ctrl.text = d!.text!);
                  },
                  icon: const Icon(Icons.content_paste),
                  label: const Text('Colar da área de transferência'),
                ),
              ),
              if (_guias.containsKey(origem))
                const Text('Já existe conteúdo desta origem: ele será substituído.', style: TextStyle(fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    final texto = ctrl.text.trim();
    if (r != true || texto.isEmpty || _curso == null) return;
    await salvarGuia(_curso!, origem, widget.chave, texto);
    _ultimaOrigem = origem;
    await _carregar();
    setState(() => _vendo = origem);
  }

  @override
  Widget build(BuildContext context) {
    final ativa = Cfg.iaAtiva;
    final semIa = ativa == 'nenhum' || Cfg.iaModelo(ativa).isEmpty;
    final g = _guias[_vendo];
    final titulo = switch (widget.kind) {
      'materia' => 'Guia da matéria',
      'prova' => 'Preparação para a prova',
      _ => 'Guia da atividade',
    };
    return Scaffold(
      appBar: AppBar(title: Text('$titulo\n${widget.nome}', maxLines: 2, style: const TextStyle(fontSize: 17))),
      floatingActionButton: semIa || _gerando
          ? null
          : FloatingActionButton.extended(
              onPressed: _gerar,
              icon: const Icon(Icons.auto_awesome),
              label: Text(_guias.containsKey(ativa) ? 'Gerar de novo (${nomeSlot(ativa).split(' ').first})' : 'Gerar com ${nomeSlot(ativa).split(' ').first}'),
            ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
        if (semIa)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Nenhuma IA por API ativa (configure em Ajustes > Guias por IA). '
                  'Sem API, use "Fazer num app de chat": funciona com a sua assinatura do Claude, ChatGPT ou Gemini.'),
            ),
          ),
        Wrap(spacing: 8, runSpacing: 4, children: [
          OutlinedButton.icon(
              onPressed: _gerando ? null : _fazerNoApp, icon: const Icon(Icons.chat_outlined), label: const Text('Fazer num app de chat')),
          OutlinedButton.icon(onPressed: _gerando ? null : _colar, icon: const Icon(Icons.content_paste), label: const Text('Colar resposta')),
        ]),
        const SizedBox(height: 8),
        if (_guias.isNotEmpty)
          Wrap(spacing: 8, children: [
            for (final s in todasOrigens.where(_guias.containsKey))
              ChoiceChip(
                label: Text('${nomeSlot(s).split(' ').first}${s == ativa ? ' (ativa)' : ''}'),
                selected: _vendo == s,
                onSelected: (_) => setState(() => _vendo = s),
              ),
          ]),
        if (_gerando)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(children: [const LinearProgressIndicator(), const SizedBox(height: 12), Text(_progresso)]),
          ),
        if (g == null && !_gerando)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Vazio(
                Icons.auto_awesome_outlined,
                semIa
                    ? 'Nada gerado ainda.'
                    : 'Toque em "Gerar" para ${nomeSlot(ativa).split(' ').first} montar este conteúdo com base em tudo da matéria'
                        '${widget.kind == 'materia' ? '' : ' e no guia geral, se já existir'}.'),
          ),
        if (g != null) ...[
          const SizedBox(height: 8),
          Text(
            'Feito por ${nomeSlot(g.slot)}${g.modelo.isEmpty ? '' : ' · ${g.modelo}'} · ${fmtData(g.em)}'
            '${g.arquivos > 0 ? ' · leu ${g.arquivos} PDF(s)' : ''}',
            style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
          ),
          if (g.slot != ativa && !semIa)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Este é o conteúdo de outra IA. Ao gerar com ${nomeSlot(ativa).split(' ').first}, ele continua salvo '
                  'e é usado como referência.', style: const TextStyle(fontSize: 12)),
            ),
          const Divider(height: 24),
          HtmlView(mdParaHtml(g.texto)),
          const SizedBox(height: 12),
          Text('Conteúdo gerado por IA: pode conter erros. Confira com o material do professor.',
              style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12)),
        ],
      ]),
    );
  }
}

/// Botao/linha que leva para o conteudo da IA, mostrando quais IAs ja geraram.
class IaAtalho extends StatelessWidget {
  final Map<String, dynamic> curso;
  final String chave;
  final String kind;
  final String nome;
  final String? tipo;
  final Map<String, dynamic>? item;
  const IaAtalho({super.key, required this.curso, required this.chave, required this.kind, required this.nome, this.tipo, this.item});

  @override
  Widget build(BuildContext context) {
    final titulo = switch (kind) {
      'materia' => 'Guia da matéria (IA)',
      'prova' => 'Preparação para a prova (IA)',
      _ => 'Guia da atividade (IA)',
    };
    return FutureBuilder<Map<String, Guia>>(
      future: guiasDeTodas(curso, chave),
      builder: (context, s) {
        final g = s.data ?? {};
        final ativa = Cfg.iaAtiva;
        return Card(
          child: ListTile(
            leading: Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
            title: Text(titulo),
            subtitle: Text(g.isEmpty
                ? 'Ainda não gerado'
                : 'Gerado por: ${g.keys.map((k) => nomeSlot(k).split(' ').first + (k == ativa ? ' (ativa)' : '')).join(', ')}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => IaTela(cursoId: curso['id'], chave: chave, kind: kind, nome: nome, tipo: tipo, item: item))),
          ),
        );
      },
    );
  }
}
