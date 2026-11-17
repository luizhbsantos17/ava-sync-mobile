import 'package:material_ui/material_ui.dart';

import '../classificar.dart';
import '../estado_app.dart';
import '../qacademico.dart';
import '../util.dart';
import 'aulas.dart';
import 'qacademico_tela.dart';

/// Qual parte da aba esta aberta (0 disciplinas, 1 boletim, 2 horario).
final segmentoAcademico = ValueNotifier<int>(0);

String _num(double? v) => v == null ? '-' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ','));
String _pct(double? v) => v == null ? '-' : '${v.toStringAsFixed(v >= 99.95 || v == v.roundToDouble() ? 0 : 1).replaceAll('.', ',')}%';

Future<void> abrirQAcademico(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QAcademicoTela()));
}

/// Cor da situacao de faltas: verde tranquilo, laranja perto do limite, vermelho passou.
Color corFaltas(Frequencia f, ColorScheme cs) {
  if (f.reprovadoPorFalta) return cs.error;
  if (f.emRisco) return const Color(0xFFFFA14A);
  return const Color(0xFF4CD39B);
}

/// Cor da nota: abaixo de 60% do maximo (10 ou 100) fica vermelha.
Color? corNota(String nota, ColorScheme cs) {
  final v = numero(nota);
  if (v == null) return null;
  final max = v > 10 ? 100 : 10;
  return v >= 0.6 * max ? const Color(0xFF4CD39B) : cs.error;
}

/// Notas de PROVA publicadas no AVA para a disciplina (o resto do AVA nao vale como nota).
List<Map<String, dynamic>> provasDoAva(Disciplina d) {
  final nd = norm(d.nome);
  final out = <Map<String, dynamic>>[];
  for (final c in app.cursos) {
    final nc = norm('${c['nome']}');
    if (!(nc.contains(nd) || nd.contains(nc))) continue;
    final quizzes = {for (final q in lista(c['provas']).map(mapa)) norm('${q['nome']}'): q};
    for (final n in lista(c['notas']).map(mapa)) {
      if (n['tipo'] == 'course' || '${n['nota']}'.isEmpty) continue;
      final nome = '${n['nome']}';
      final q = quizzes[norm(nome)];
      final ehProva = pareceProva(nome) || (q != null && categoria('quiz', q) == 'prova');
      if (ehProva) out.add(n);
    }
  }
  return out;
}

class DesempenhoAba extends StatelessWidget {
  const DesempenhoAba({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (app.academico.isEmpty) return const _Conectar();
    return ValueListenableBuilder<int>(
      valueListenable: segmentoAcademico,
      builder: (context, seg, _) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: SegmentedButton<int>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: 0, label: Text('Disciplinas'), icon: Icon(Icons.dashboard_outlined)),
              ButtonSegment(value: 1, label: Text('Boletim'), icon: Icon(Icons.table_chart_outlined)),
              ButtonSegment(value: 2, label: Text('Horário'), icon: Icon(Icons.calendar_view_week_outlined)),
            ],
            selected: {seg},
            onSelectionChanged: (s) => segmentoAcademico.value = s.first,
          ),
        ),
        if (app.academicoAviso != null)
          Material(
            color: cs.errorContainer,
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.info_outline),
              title: Text(app.academicoAviso!),
              onTap: () => abrirQAcademico(context),
            ),
          ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (c, a) => FadeTransition(
                opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.03), end: Offset.zero).animate(a), child: c)),
            child: switch (seg) {
              1 => const _Boletim(key: ValueKey(1)),
              2 => const _Horario(key: ValueKey(2)),
              _ => const _Disciplinas(key: ValueKey(0)),
            },
          ),
        ),
      ]),
    );
  }
}

class _Conectar extends StatelessWidget {
  const _Conectar();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cs.primary.withValues(alpha: 0.28), cs.primary.withValues(alpha: 0.06)]),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.school_rounded, size: 40, color: cs.primary),
          const SizedBox(height: 12),
          const Text('Notas, faltas e horário', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('Conecte o Q-Acadêmico para ver o boletim, as faltas de cada disciplina, quantas aulas ainda '
              'pode faltar e suas aulas da semana. Ele é lido pelo navegador do app, com o seu login.'),
          const SizedBox(height: 16),
          FilledButton.icon(
              onPressed: () => abrirQAcademico(context), icon: const Icon(Icons.link), label: const Text('Conectar Q-Acadêmico')),
        ]),
      ),
    ]);
  }
}

class _Rodape extends StatelessWidget {
  const _Rodape();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
      child: Row(children: [
        Icon(Icons.cloud_done_outlined, size: 15, color: cs.onSurfaceVariant),
        const SizedBox(width: 6),
        Expanded(
          child: Text('Q-Acadêmico · ${fmtRelativo(app.academicoEm)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
        ),
        TextButton.icon(onPressed: () => abrirQAcademico(context), icon: const Icon(Icons.refresh, size: 18), label: const Text('Atualizar')),
      ]),
    );
  }
}

// ---------------------------------------------------------------- disciplinas

class _Disciplinas extends StatelessWidget {
  const _Disciplinas({super.key});
  @override
  Widget build(BuildContext context) {
    final ds = [...app.academico];
    // as que estao mais perto do limite de faltas primeiro
    ds.sort((a, b) => (app.freqDe(a).restantes ?? 999).compareTo(app.freqDe(b).restantes ?? 999));
    return RefreshIndicator(
      onRefresh: app.sincronizar,
      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        const _Rodape(),
        for (final d in ds) _DisciplinaCard(d),
      ]),
    );
  }
}

class _DisciplinaCard extends StatefulWidget {
  final Disciplina d;
  const _DisciplinaCard(this.d);
  @override
  State<_DisciplinaCard> createState() => _DisciplinaCardState();
}

class _DisciplinaCardState extends State<_DisciplinaCard> {
  bool _aberto = false;
  int _simDias = 0; // simulador: faltar mais N dias

  @override
  Widget build(BuildContext context) {
    final d = widget.d;
    final cs = Theme.of(context).colorScheme;
    final cor = corDisciplina(d.nome, Theme.of(context).brightness);
    final f = app.freqDe(d);
    final cf = corFaltas(f, cs);
    final faltas = d.faltas ?? 0;
    final usado = f.limite == null || f.limite == 0 ? 0.0 : (faltas / f.limite!).clamp(0.0, 1.0);
    final dias = f.diasRestantes;
    final provasAva = provasDoAva(d);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _aberto = !_aberto),
        child: Container(
          decoration: BoxDecoration(border: Border(left: BorderSide(color: cor, width: 5))),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.nome,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, height: 1.2)),
                    if (d.professor.isNotEmpty || d.situacao.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text([d.professor, d.situacao].where((s) => s.isNotEmpty).join(' · '),
                            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                      ),
                  ]),
                ),
                const SizedBox(width: 8),
                _NotaPill(d.media.isEmpty ? '–' : d.media, rotulo: 'média', cor: corNota(d.media, cs) ?? cor),
              ]),
              const SizedBox(height: 12),
              Row(children: [
                _Metrica(
                    valor: '${_num(faltas)}${f.limite == null ? '' : '/${f.limite}'}', rotulo: 'faltas', cor: cf),
                _Metrica(valor: _pct(f.percentual), rotulo: 'presença no total', cor: cf),
                _Metrica(
                  valor: dias == null ? '-' : (dias < 0 ? 'passou' : '$dias'),
                  rotulo: dias == null
                      ? 'pode faltar'
                      : dias < 0
                          ? 'do limite'
                          : dias == 1
                              ? 'dia pode faltar'
                              : 'dias pode faltar',
                  cor: cf,
                ),
              ]),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: usado),
                  duration: const Duration(milliseconds: 650),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, _) => LinearProgressIndicator(
                      value: v, minHeight: 8, color: cf, backgroundColor: cs.outlineVariant.withValues(alpha: 0.25)),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                f.restantes == null
                    ? 'Sem carga horária no boletim para calcular o limite.'
                    : f.restantes! >= 0
                        ? 'Ainda pode ter ${f.restantes} falta(s) · cada dia de aula = ${f.aulasPorDia} falta(s)'
                            '${f.percentualDadas == null ? '' : ' · ${_pct(f.percentualDadas)} das aulas já dadas'}'
                        : 'Passou ${-f.restantes!} falta(s) do limite',
                style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant),
              ),
              if (d.etapas.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 6, runSpacing: 6, children: [for (final e in d.etapas) _EtapaChip(e)]),
              ],
              if (_aberto) ...[
                const SizedBox(height: 14),
                _Simulador(
                  d: d,
                  f: f,
                  dias: _simDias,
                  mudar: (v) => setState(() => _simDias = v),
                ),
                if (d.avaliacoes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _Titulo('Avaliações do diário', cor),
                  for (final a in d.avaliacoes) _LinhaNota(
                    titulo: '${a['descricao']}',
                    sub: [
                      if ('${a['etapa']}'.isNotEmpty) '${a['etapa']}',
                      if ('${a['data']}'.isNotEmpty) '${a['data']}',
                      if ('${a['peso']}'.isNotEmpty) 'peso ${a['peso']}',
                    ].join(' · '),
                    nota: '${a['nota']}',
                    max: '${a['max']}',
                  ),
                ],
                if (provasAva.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _Titulo('Provas com nota no AVA', cor),
                  for (final n in provasAva) _LinhaNota(titulo: '${n['nome']}', sub: 'AVA', nota: '${n['nota']}', max: ''),
                ],
                if (d.avaliacoes.isEmpty && provasAva.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text('Nenhuma avaliação lançada no diário ainda.', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ),
              ],
              Center(
                child: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: AnimatedRotation(
                    turns: _aberto ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _NotaPill extends StatelessWidget {
  final String valor, rotulo;
  final Color cor;
  const _NotaPill(this.valor, {required this.rotulo, required this.cor});
  @override
  // largura limitada: um valor estranho nunca pode espremer o nome da disciplina
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 52, maxWidth: 92),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: cor)),
            Text(rotulo, maxLines: 1, style: TextStyle(fontSize: 9.5, color: cor, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

class _Metrica extends StatelessWidget {
  final String valor, rotulo;
  final Color cor;
  const _Metrica({required this.valor, required this.rotulo, required this.cor});
  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(color: cor.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(12)),
          child: Column(children: [
            Text(valor, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: cor)),
            const SizedBox(height: 1),
            Text(rotulo, style: TextStyle(fontSize: 10.5, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      );
}

class _EtapaChip extends StatelessWidget {
  final Map<String, dynamic> e;
  const _EtapaChip(this.e);
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final nota = '${e['nota']}';
    final cor = corNota(nota, cs) ?? cs.onSurfaceVariant;
    final faltas = e['faltas'] as num?;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
          child: Text('${e['rotulo']}  ',
              maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ),
        Text(nota.isEmpty ? '–' : nota, style: TextStyle(fontWeight: FontWeight.w800, color: cor)),
        if (faltas != null && faltas > 0) Text('  · ${_num(faltas.toDouble())}F', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

class _Titulo extends StatelessWidget {
  final String t;
  final Color cor;
  const _Titulo(this.t, this.cor);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: cor)),
      );
}

class _LinhaNota extends StatelessWidget {
  final String titulo, sub, nota, max;
  const _LinhaNota({required this.titulo, required this.sub, required this.nota, required this.max});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
            if (sub.isNotEmpty) Text(sub, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
          ]),
        ),
        Text(nota.isEmpty ? '–' : nota, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: corNota(nota, cs))),
        if (max.isNotEmpty) Text(' / $max', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ]),
    );
  }
}

/// "E se eu faltar?": soma dias de falta e mostra como fica.
class _Simulador extends StatelessWidget {
  final Disciplina d;
  final Frequencia f;
  final int dias;
  final ValueChanged<int> mudar;
  const _Simulador({required this.d, required this.f, required this.dias, required this.mudar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final extra = dias * f.aulasPorDia;
    final sim = app.freqDe(Disciplina(
        nome: d.nome,
        carga: d.carga,
        aulas: d.aulas,
        faltas: (d.faltas ?? 0) + extra,
        minima: d.minima,
        frequencia: dias == 0 ? d.frequencia : null));
    final cor = corFaltas(sim, cs);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
      decoration: BoxDecoration(color: cs.surfaceContainerHighest.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.science_outlined, size: 18, color: cs.primary),
          const SizedBox(width: 6),
          const Expanded(child: Text('E se eu faltar?', style: TextStyle(fontWeight: FontWeight.w700))),
          IconButton.filledTonal(
              visualDensity: VisualDensity.compact, onPressed: dias == 0 ? null : () => mudar(dias - 1), icon: const Icon(Icons.remove)),
          SizedBox(
              width: 58,
              child: Text('$dias dia${dias == 1 ? '' : 's'}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700))),
          IconButton.filledTonal(visualDensity: VisualDensity.compact, onPressed: () => mudar(dias + 1), icon: const Icon(Icons.add)),
        ]),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            key: ValueKey(dias),
            dias == 0
                ? 'Toque em + para ver como ficam as faltas ao perder dias de aula (${f.aulasPorDia} falta(s) por dia).'
                : sim.restantes == null
                    ? '+$extra falta(s).'
                    : sim.restantes! >= 0
                        ? '+$extra falta(s) → ${_num((d.faltas ?? 0) + extra)}/${sim.limite} · presença ${_pct(sim.percentual)} · ainda sobram ${sim.restantes}'
                        : '+$extra falta(s) → passa ${-sim.restantes!} do limite. Não dá!',
            style: TextStyle(fontSize: 12.5, color: dias == 0 ? cs.onSurfaceVariant : cor, fontWeight: dias == 0 ? null : FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- boletim

class _Boletim extends StatelessWidget {
  const _Boletim({super.key});
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ds = app.academico;
    final etapas = <String>[];
    for (final d in ds) {
      for (final e in d.etapas) {
        final r = '${e['rotulo']}';
        if (!etapas.contains(r)) etapas.add(r);
      }
    }
    final cab = TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: cs.onSurfaceVariant);
    return RefreshIndicator(
      onRefresh: app.sincronizar,
      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        const _Rodape(),
        Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 42,
              dataRowMinHeight: 46,
              dataRowMaxHeight: 60,
              columnSpacing: 18,
              horizontalMargin: 14,
              headingRowColor: WidgetStatePropertyAll(cs.primary.withValues(alpha: 0.08)),
              columns: [
                DataColumn(label: Text('Disciplina', style: cab)),
                for (final e in etapas) DataColumn(label: Text(e.replaceAll(' etapa', ''), style: cab), numeric: true),
                DataColumn(label: Text('Média', style: cab), numeric: true),
                DataColumn(label: Text('Faltas', style: cab), numeric: true),
                DataColumn(label: Text('Freq.', style: cab), numeric: true),
                DataColumn(label: Text('Situação', style: cab)),
              ],
              rows: [
                for (final d in ds)
                  () {
                    final f = app.freqDe(d);
                    final cor = corDisciplina(d.nome, Theme.of(context).brightness);
                    Widget nota(String n) =>
                        Text(n.isEmpty ? '–' : n, style: TextStyle(fontWeight: FontWeight.w700, color: corNota(n, cs)));
                    return DataRow(cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Row(children: [
                          Container(width: 8, height: 8, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
                          const SizedBox(width: 8),
                          Flexible(child: Text(d.nome, maxLines: 2, overflow: TextOverflow.ellipsis)),
                        ]),
                      )),
                      for (final e in etapas)
                        DataCell(nota('${d.etapas.where((x) => x['rotulo'] == e).firstOrNull?['nota'] ?? ''}')),
                      DataCell(Text(d.media.isEmpty ? '–' : d.media,
                          style: TextStyle(fontWeight: FontWeight.w900, color: corNota(d.media, cs)))),
                      DataCell(Text('${_num(d.faltas ?? 0)}${f.limite == null ? '' : '/${f.limite}'}',
                          style: TextStyle(color: corFaltas(f, cs), fontWeight: FontWeight.w700))),
                      DataCell(Text(_pct(f.percentual))),
                      DataCell(Text(d.situacao.isEmpty ? '–' : d.situacao)),
                    ]);
                  }(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Text('Deslize a tabela para o lado para ver todas as colunas. Toque em Disciplinas para ver os detalhes.',
              style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- horario

class _Horario extends StatefulWidget {
  const _Horario({super.key});
  @override
  State<_Horario> createState() => _HorarioState();
}

class _HorarioState extends State<_Horario> {
  late int _dia = DateTime.now().weekday;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final h = app.horario;
    if (h.isEmpty) {
      return ListView(padding: const EdgeInsets.all(24), children: [
        Icon(Icons.calendar_view_week_outlined, size: 48, color: cs.onSurfaceVariant),
        const SizedBox(height: 12),
        const Text('Horário ainda não importado.', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('Atualize o Q-Acadêmico. Se continuar vazio, mande as páginas exportadas (Perfil) para ajustar o leitor.',
            textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        Center(child: FilledButton.tonal(onPressed: () => abrirQAcademico(context), child: const Text('Atualizar Q-Acadêmico'))),
      ]);
    }
    final dias = {for (final a in h) a.dia}.toList()..sort();
    if (!dias.contains(_dia)) _dia = dias.firstWhere((d) => d >= DateTime.now().weekday, orElse: () => dias.first);
    final hoje = DateTime.now().weekday;
    final aulas = aulasDoDia(h, _dia);
    final total = aulas.fold<int>(0, (s, a) => s + a.aulas);
    return ListView(padding: const EdgeInsets.only(bottom: 28), children: [
      SizedBox(
        height: 64,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(12, 10, 12, 6), children: [
          for (final d in dias)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: ChoiceChip(
                selected: d == _dia,
                onSelected: (_) => setState(() => _dia = d),
                avatar: d == hoje ? Icon(Icons.today, size: 16, color: d == _dia ? cs.onSecondaryContainer : cs.primary) : null,
                label: Text(diasSemana[d - 1].substring(0, 3)),
              ),
            ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
        child: Text('${diasSemana[_dia - 1]}${_dia == hoje ? ' (hoje)' : ''} · $total aula${total == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ),
      for (final a in aulas) AulaTile(a, quando: _dia == hoje ? momento(a) : null),
      const SizedBox(height: 14),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        child: Text('SEMANA', style: TextStyle(fontSize: 11, letterSpacing: 0.8, fontWeight: FontWeight.w800, color: cs.primary)),
      ),
      _Semana(h, dias, destacar: _dia, tocar: (d) => setState(() => _dia = d)),
    ]);
  }
}

/// Visao compacta da semana: uma coluna por dia, blocos coloridos por disciplina.
class _Semana extends StatelessWidget {
  final List<Aula> h;
  final List<int> dias;
  final int destacar;
  final ValueChanged<int> tocar;
  const _Semana(this.h, this.dias, {required this.destacar, required this.tocar});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final b = Theme.of(context).brightness;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final d in dias)
          Expanded(
            child: GestureDetector(
              onTap: () => tocar(d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: d == destacar ? cs.primary.withValues(alpha: 0.10) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(children: [
                  Text(diasSemana[d - 1].substring(0, 3),
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: d == destacar ? cs.primary : cs.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  for (final a in aulasDoDia(h, d))
                    Container(
                      width: double.infinity,
                      height: 14.0 * a.aulas + 4,
                      margin: const EdgeInsets.only(bottom: 3),
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
                      decoration: BoxDecoration(
                          color: corDisciplina(a.disciplina, b).withValues(alpha: 0.85), borderRadius: BorderRadius.circular(6)),
                      child: Text(a.disciplina,
                          maxLines: a.aulas, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 9, height: 1.15, color: cs.surface, fontWeight: FontWeight.w700)),
                    ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}
