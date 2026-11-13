import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../envio.dart';
import '../estado_app.dart';
import '../moodle.dart';
import '../util.dart';
import 'comum.dart';

/// Entrega de tarefa. Regras: a pessoa escolhe os arquivos, digita ENVIAR, e so
/// ela marca "finalizar" e a declaracao de autoria. Nada disso e automatico.
class EnvioTela extends StatefulWidget {
  final Map<String, dynamic> tarefa;
  const EnvioTela({super.key, required this.tarefa});
  @override
  State<EnvioTela> createState() => _EnvioTelaState();
}

class _EnvioTelaState extends State<EnvioTela> {
  final _arquivos = <({String nome, Uint8List bytes})>[];
  final _texto = TextEditingController();
  final _conf = TextEditingController();
  bool _finalizar = false;
  bool _aceito = false;
  bool _enviando = false;
  SituacaoEntrega? _atual;
  String? _erroAtual;
  String? _resultado;

  Map<String, dynamic> get t => widget.tarefa;
  bool get _exigeDeclaracao => t['declaracao'] == true;
  bool get _usaRascunho => t['rascunhos'] == true;

  @override
  void initState() {
    super.initState();
    _conf.addListener(() => setState(() {}));
    _lerSituacao();
  }

  Future<Moodle> _moodle() async {
    final tok = await Cfg.token();
    if (tok == null) throw MoodleErro('Faça login de novo.', sessao: true);
    return Moodle(Cfg.site, tok);
  }

  Future<void> _lerSituacao() async {
    try {
      final s = await Envio.situacao(await _moodle(), t['id'], app.snap['userid']);
      if (mounted) setState(() => _atual = s);
    } catch (e) {
      if (mounted) setState(() => _erroAtual = '$e');
    }
  }

  Future<void> _escolher() async {
    final res = await FilePicker.pickFiles(dialogTitle: 'Arquivos para entregar');
    for (final f in res) {
      _arquivos.add((nome: f.name, bytes: await f.readAsBytes()));
    }
    setState(() {});
  }

  Future<void> _enviar() async {
    final p = PedidoEnvio(
      tarefaId: t['id'],
      arquivos: List.of(_arquivos),
      texto: _texto.text,
      // sem rascunho, salvar ja e entregar: nao chama "enviar para avaliacao"
      finalizar: _usaRascunho && _finalizar,
      aceitouDeclaracao: _aceito,
      exigeDeclaracao: _exigeDeclaracao,
      confirmacao: _conf.text,
    );
    final prob = p.problema() ??
        (!_usaRascunho && _exigeDeclaracao && !_aceito ? 'Marque a declaração de autoria para entregar.' : null);
    if (prob != null) {
      aviso(context, prob);
      return;
    }
    setState(() {
      _enviando = true;
      _resultado = null;
    });
    try {
      final s = await Envio.executar(await _moodle(), p, app.snap['userid']);
      setState(() {
        _atual = s;
        _resultado = 'Situação no AVA agora: ${s.texto}'
            '${s.arquivos.isEmpty ? '' : '\nArquivos: ${s.arquivos.join(', ')}'}';
        _conf.clear();
      });
      app.sincronizar();
    } catch (e) {
      setState(() => _resultado = 'Não enviado: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final vaiFinalizar = _finalizar || !_usaRascunho;
    final pronto = _conf.text.trim() == 'ENVIAR' &&
        (_arquivos.isNotEmpty || _texto.text.trim().isNotEmpty) &&
        !(vaiFinalizar && _exigeDeclaracao && !_aceito);
    return Scaffold(
      appBar: AppBar(title: const Text('Enviar atividade')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('${t['nome']}', style: tt.titleMedium),
        Text('${t['curso']}', style: TextStyle(color: Theme.of(context).hintColor)),
        const SizedBox(height: 4),
        Text('Entrega: ${fmtData(t['entrega'])} (${fmtRelativo(t['entrega'])})'),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: _atual == null
                ? Text(_erroAtual == null ? 'Consultando a situação no AVA...' : 'Não consegui consultar: $_erroAtual')
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Situação no AVA: ${_atual!.texto}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(_atual!.arquivos.isEmpty ? 'Nenhum arquivo enviado ainda.' : 'Já enviados: ${_atual!.arquivos.join(', ')}'),
                    if (_atual!.arquivos.isNotEmpty)
                      Text('Os arquivos novos SUBSTITUEM os atuais.', style: TextStyle(color: cs.error)),
                  ]),
          ),
        ),
        const SizedBox(height: 16),
        Text('Arquivos', style: tt.titleSmall),
        for (var i = 0; i < _arquivos.length; i++)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.insert_drive_file_outlined),
            title: Text(_arquivos[i].nome),
            subtitle: Text(fmtTamanho(_arquivos[i].bytes.length)),
            trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _arquivos.removeAt(i))),
          ),
        OutlinedButton.icon(onPressed: _enviando ? null : _escolher, icon: const Icon(Icons.attach_file), label: const Text('Escolher arquivos')),
        const SizedBox(height: 16),
        TextField(
          controller: _texto,
          minLines: 2,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
              labelText: 'Texto online (opcional)',
              helperText: 'Só se a tarefa aceitar texto digitado.',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        if (_usaRascunho)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _finalizar,
            onChanged: _enviando ? null : (v) => setState(() => _finalizar = v),
            title: const Text('Enviar para avaliação (finalizar)'),
            subtitle: const Text('Desligado: fica como rascunho e você ainda pode mudar. Ligado: depois de finalizar, normalmente não dá para alterar.'),
          )
        else
          Card(
            color: cs.tertiaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Esta tarefa não usa rascunho: salvar já conta como entrega.'),
            ),
          ),
        if (vaiFinalizar && _exigeDeclaracao)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _aceito,
            onChanged: _enviando ? null : (v) => setState(() => _aceito = v ?? false),
            title: const Text('Declaração de autoria'),
            subtitle: Text('${t['textoDeclaracao']}'.trim().isEmpty
                ? 'Declaro que este trabalho é meu, exceto onde reconheci o uso do trabalho de outras pessoas.'
                : '${t['textoDeclaracao']}'),
          ),
        const SizedBox(height: 12),
        TextField(
          controller: _conf,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Digite ENVIAR para confirmar', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: pronto && !_enviando ? _enviar : null,
          icon: _enviando
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: Text(vaiFinalizar ? 'Enviar e finalizar' : 'Salvar como rascunho'),
        ),
        if (_resultado != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Card(
              color: _resultado!.startsWith('Não') ? cs.errorContainer : cs.secondaryContainer,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(_resultado!)),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: () => abrirLink(context, t['link']), icon: const Icon(Icons.open_in_new), label: const Text('Conferir no AVA')),
      ]),
    );
  }
}
