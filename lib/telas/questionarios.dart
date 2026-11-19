import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../qacademico.dart';

/// Avaliação docente obrigatória do Q-Acadêmico, respondida pelo app.
///
/// A pessoa escolhe uma nota padrão (0 a 10) e um comentário padrão, e, se quiser, muda a
/// nota ou o comentário de alguma disciplina. Só depois de confirmar o app abre cada
/// formulário no navegador do Q-Acadêmico, marca a opção com a nota em todas as perguntas
/// e envia, um atrás do outro. Nada é enviado sem a pessoa decidir.
class QuestionariosTela extends StatefulWidget {
  final List<QuestionarioQA> questionarios;
  final Future<int> Function(List<RespostaQuestionario>, void Function(int feitos, int total)) responder;
  const QuestionariosTela({super.key, required this.questionarios, required this.responder});

  @override
  State<QuestionariosTela> createState() => _QuestionariosTelaState();
}

class _QuestionariosTelaState extends State<QuestionariosTela> {
  // padrão (lembrado do semestre passado)
  int? _nota = Cfg.qaNotaPadrao;
  late final _comentario = TextEditingController(text: Cfg.qaComentarioPadrao);

  // ajustes por disciplina: null / vazio = usa o padrão
  late final List<int?> _notas = List.filled(widget.questionarios.length, null);
  late final List<TextEditingController> _comentarios =
      List.generate(widget.questionarios.length, (_) => TextEditingController());

  bool _enviando = false;
  String? _progresso;
  String? _erro;

  @override
  void dispose() {
    _comentario.dispose();
    for (final c in _comentarios) {
      c.dispose();
    }
    super.dispose();
  }

  int? _notaDe(int i) => _notas[i] ?? _nota;
  String _comentarioDe(int i) => _comentarios[i].text.trim().isEmpty ? _comentario.text.trim() : _comentarios[i].text.trim();
  bool get _prontos => List.generate(_notas.length, _notaDe).every((n) => n != null);

  Future<void> _enviar() async {
    final n = widget.questionarios.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Responder $n avaliação(ões)?'),
        content: const Text('O app vai responder os questionários no Q-Acadêmico em seu nome, com as notas e '
            'comentários escolhidos. Depois de enviado não dá para mudar.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Responder todas')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    // lembra o padrão para o próximo semestre
    if (_nota != null) await Cfg.setQaNotaPadrao(_nota!);
    await Cfg.setQaComentarioPadrao(_comentario.text.trim());
    if (!mounted) return;
    setState(() {
      _enviando = true;
      _erro = null;
      _progresso = 'Abrindo o primeiro questionário...';
    });
    final respostas = [
      for (var i = 0; i < n; i++)
        RespostaQuestionario(widget.questionarios[i], _notaDe(i)!, comentario: _comentarioDe(i)),
    ];
    try {
      final feitos = await widget.responder(respostas, (f, t) {
        if (mounted) {
          setState(() => _progresso = f < t ? 'Respondendo ${f + 1} de $t: ${widget.questionarios[f].disciplina}' : 'Pronto!');
        }
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
    final ajustadas = [for (var i = 0; i < qs.length; i++) if (_notas[i] != null || _comentarios[i].text.trim().isNotEmpty) i].length;
    return PopScope(
      canPop: !_enviando,
      child: Scaffold(
        appBar: AppBar(title: const Text('Avaliação docente')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Text(
              'O Q-Acadêmico só libera notas e faltas depois que você responde a avaliação de '
              '${qs.length} disciplina(s). Escolha a nota e o comentário: o app responde todas sozinho.',
              style: TextStyle(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Nota padrão', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  _Notas(valor: _nota, aoEscolher: _enviando ? null : (n) => setState(() => _nota = n)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _comentario,
                    enabled: !_enviando,
                    maxLength: 200,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Comentário padrão (opcional)',
                      hintText: 'Vai em todas as avaliações',
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 4),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                title: Text('Ajustar por disciplina${ajustadas > 0 ? ' ($ajustadas)' : ''}'),
                subtitle: const Text('Opcional: nota ou comentário diferente para algum professor'),
                children: [
                  for (var i = 0; i < qs.length; i++) _ajuste(i, cs),
                ],
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
                    onPressed: _prontos ? () => unawaited(_enviar()) : null,
                    icon: const Icon(Icons.bolt_rounded),
                    label: Text(_prontos ? 'Responder todas (${qs.length})' : 'Escolha a nota padrão'),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _ajuste(int i, ColorScheme cs) {
    final q = widget.questionarios[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(q.disciplina.isEmpty ? q.titulo : q.disciplina, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                if (q.professor.isNotEmpty) Text(q.professor, style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
              ]),
            ),
            if (_notas[i] != null)
              TextButton(
                onPressed: _enviando ? null : () => setState(() => _notas[i] = null),
                child: const Text('Usar padrão'),
              ),
          ]),
          const SizedBox(height: 8),
          _Notas(valor: _notaDe(i), destacar: _notas[i] != null, aoEscolher: _enviando ? null : (n) => setState(() => _notas[i] = n)),
          const SizedBox(height: 8),
          TextField(
            controller: _comentarios[i],
            enabled: !_enviando,
            maxLength: 200,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              isDense: true,
              labelText: 'Comentário desta disciplina',
              hintText: _comentario.text.trim().isEmpty ? 'Em branco' : 'Em branco = o padrão',
            ),
          ),
        ]),
      ),
    );
  }
}

/// Notas de 0 a 10 em botões. [destacar]: nota própria da disciplina (não a padrão).
class _Notas extends StatelessWidget {
  final int? valor;
  final bool destacar;
  final ValueChanged<int>? aoEscolher;
  const _Notas({required this.valor, required this.aoEscolher, this.destacar = true});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Wrap(spacing: 6, runSpacing: 6, children: [
      for (var n = 10; n >= 0; n--)
        ChoiceChip(
          label: Text('$n'),
          selected: valor == n,
          showCheckmark: false,
          selectedColor: destacar ? null : cs.secondaryContainer,
          onSelected: aoEscolher == null ? null : (_) => aoEscolher!(n),
        ),
    ]);
  }
}
