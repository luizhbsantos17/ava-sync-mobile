import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../qacademico.dart';

/// Avaliação docente obrigatória do Q-Acadêmico, respondida pelo app.
///
/// A pessoa escolhe a nota de cada disciplina (e um comentário, se quiser); só depois de
/// confirmar o app abre cada formulário no navegador do Q-Acadêmico, marca a opção com
/// essa nota em todas as perguntas e envia. Nada é enviado sem a pessoa decidir.
class QuestionariosTela extends StatefulWidget {
  final List<QuestionarioQA> questionarios;
  final Future<int> Function(List<RespostaQuestionario>, void Function(int feitos, int total)) responder;
  const QuestionariosTela({super.key, required this.questionarios, required this.responder});

  @override
  State<QuestionariosTela> createState() => _QuestionariosTelaState();
}

class _QuestionariosTelaState extends State<QuestionariosTela> {
  late final List<int?> _notas = List.filled(widget.questionarios.length, null);
  late final List<TextEditingController> _comentarios =
      List.generate(widget.questionarios.length, (_) => TextEditingController());
  bool _enviando = false;
  String? _progresso;
  String? _erro;

  @override
  void dispose() {
    for (final c in _comentarios) {
      c.dispose();
    }
    super.dispose();
  }

  void _todas(int n) => setState(() {
        for (var i = 0; i < _notas.length; i++) {
          _notas[i] = n;
        }
      });

  Future<void> _enviar() async {
    final n = widget.questionarios.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Enviar $n avaliação(ões)?'),
        content: const Text('O app vai responder os questionários no Q-Acadêmico em seu nome, com as notas '
            'escolhidas. Depois de enviado não dá para mudar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
      _progresso = 'Abrindo o primeiro questionário...';
    });
    final respostas = [
      for (var i = 0; i < n; i++)
        RespostaQuestionario(widget.questionarios[i], _notas[i]!, comentario: _comentarios[i].text),
    ];
    try {
      final feitos = await widget.responder(respostas, (f, t) {
        if (mounted) setState(() => _progresso = f < t ? 'Respondendo ${f + 1} de $t: ${widget.questionarios[f].disciplina}' : 'Pronto!');
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feitos avaliação(ões) enviada(s). Lendo notas e faltas...')));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _enviando = false;
          _progresso = null;
          _erro = '$e'.replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final qs = widget.questionarios;
    final prontos = _notas.every((n) => n != null);
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Avaliação docente')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              'O Q-Acadêmico só libera notas e faltas depois que você responde a avaliação de cada '
              'disciplina. Escolha uma nota de 0 a 10 para cada professor: o app marca essa nota em todas '
              'as perguntas do questionário e envia.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 14),
            Text('A mesma nota para todas', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            _Notas(valor: prontos && _notas.toSet().length == 1 ? _notas.first : null, aoEscolher: _enviando ? null : _todas),
            const SizedBox(height: 16),
            for (var i = 0; i < qs.length; i++)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(qs[i].disciplina.isEmpty ? qs[i].titulo : qs[i].disciplina,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    if (qs[i].professor.isNotEmpty)
                      Text(qs[i].professor, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    const SizedBox(height: 8),
                    _Notas(valor: _notas[i], aoEscolher: _enviando ? null : (n) => setState(() => _notas[i] = n)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _comentarios[i],
                      enabled: !_enviando,
                      maxLength: 200,
                      decoration: const InputDecoration(
                          isDense: true, labelText: 'Comentário (opcional)', hintText: 'Observações, sugestões e críticas'),
                    ),
                  ]),
                ),
              ),
            if (_erro != null)
              Card(
                color: cs.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_erro!, style: TextStyle(color: cs.onErrorContainer)),
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: _enviando
                ? Row(children: [
                    const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                    const SizedBox(width: 14),
                    Expanded(child: Text(_progresso ?? 'Enviando...')),
                  ])
                : FilledButton.icon(
                    onPressed: prontos ? () => unawaited(_enviar()) : null,
                    icon: const Icon(Icons.send_rounded),
                    label: Text(prontos ? 'Enviar ${qs.length} avaliação(ões)' : 'Escolha a nota de cada disciplina'),
                  ),
          ),
        ),
      ),
    );
  }
}

/// Notas de 0 a 10 em botões.
class _Notas extends StatelessWidget {
  final int? valor;
  final ValueChanged<int>? aoEscolher;
  const _Notas({required this.valor, required this.aoEscolher});

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var n = 10; n >= 0; n--)
        ChoiceChip(
          label: Text('$n'),
          selected: valor == n,
          showCheckmark: false,
          onSelected: aoEscolher == null ? null : (_) => aoEscolher!(n),
        ),
    ]);
  }
}
