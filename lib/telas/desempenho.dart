import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../estado_app.dart';
import '../qacademico.dart';
import '../util.dart';
import 'qacademico_tela.dart';

/// Resumo geral: frequencia ponderada pela carga e media das medias numericas.
({double? frequencia, double? media, int emRisco}) resumoAcademico(List<Disciplina> ds, {double minima = 75}) {
  var peso = 0.0, soma = 0.0, somaMedia = 0.0, nMedia = 0, risco = 0;
  for (final d in ds) {
    final f = frequencia(d, minima: minima);
    if (f.percentual != null) {
      final p = (d.carga ?? 0) > 0 ? d.carga! : 1.0;
      peso += p;
      soma += f.percentual! * p;
    }
    if (f.emRisco) risco++;
    final m = numero(d.media);
    if (m != null) {
      somaMedia += m;
      nMedia++;
    }
  }
  return (frequencia: peso == 0 ? null : soma / peso, media: nMedia == 0 ? null : somaMedia / nMedia, emRisco: risco);
}

String _pct(double? v) => v == null ? '-' : '${v.toStringAsFixed(v >= 99.95 ? 0 : 1).replaceAll('.', ',')}%';
String _num(double? v) => v == null ? '-' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1).replaceAll('.', ','));

Future<void> abrirQAcademico(BuildContext context) async {
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QAcademicoTela()));
}

class DesempenhoAba extends StatelessWidget {
  const DesempenhoAba({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ds = app.academico;
    final minima = Cfg.frequenciaMinima.toDouble();
    final r = resumoAcademico(ds, minima: minima);
    final cursos = app.cursos.where((c) => lista(c['notas']).isNotEmpty).toList();
    return RefreshIndicator(
      onRefresh: app.sincronizar,
      child: ListView(padding: const EdgeInsets.only(bottom: 28), children: [
        if (app.academicoAviso != null)
          Card(
            color: cs.errorContainer,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(app.academicoAviso!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => abrirQAcademico(context),
            ),
          ),
        if (ds.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.school_outlined, color: cs.primary),
                  const SizedBox(width: 10),
                  const Expanded(child: Text('Notas e faltas do Q-Acadêmico', style: TextStyle(fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 8),
                const Text('Conecte o Q-Acadêmico para ver média por disciplina, frequência, faltas e quantas '
                    'ainda pode ter. Ele é lido pelo navegador do app, com o seu login.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                    onPressed: () => abrirQAcademico(context),
                    icon: const Icon(Icons.link),
                    label: const Text('Conectar Q-Acadêmico')),
              ]),
            ),
          )
        else ...[
          _Resumo(frequencia: r.frequencia, media: r.media, emRisco: r.emRisco, total: ds.length),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(children: [
              Expanded(
                child: Text('Q-Acadêmico · atualizado ${fmtRelativo(app.academicoEm)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              ),
              TextButton.icon(
                  onPressed: () => abrirQAcademico(context), icon: const Icon(Icons.refresh, size: 18), label: const Text('Atualizar')),
            ]),
          ),
          for (final d in ds) _DisciplinaCard(d, minima: minima),
        ],
        if (cursos.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
            child: Text('Notas no AVA', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
          ),
          for (final c in cursos) _NotasAva(c),
        ],
      ]),
    );
  }
}

class _Resumo extends StatelessWidget {
  final double? frequencia, media;
  final int emRisco, total;
  const _Resumo({required this.frequencia, required this.media, required this.emRisco, required this.total});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bloco(String valor, String rotulo, {Color? cor}) => Expanded(
          child: Column(children: [
            Text(valor, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: cor ?? cs.onSurface)),
            const SizedBox(height: 2),
            Text(rotulo, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(children: [
          bloco(_pct(frequencia), 'frequência geral'),
          bloco(_num(media), 'média das médias'),
          bloco('$emRisco', emRisco == 1 ? 'disciplina perto do limite de faltas' : 'disciplinas perto do limite de faltas',
              cor: emRisco > 0 ? cs.error : null),
        ]),
      ),
    );
  }
}

class _DisciplinaCard extends StatelessWidget {
  final Disciplina d;
  final double minima;
  const _DisciplinaCard(this.d, {required this.minima});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final f = frequencia(d, minima: minima);
    final pres = f.percentual;
    final corFreq = pres == null
        ? cs.outline
        : pres < minima
            ? cs.error
            : f.emRisco
                ? Colors.orange
                : Colors.green;
    final faltasTxt = [
      'Faltas: ${_num(d.faltas ?? 0)}${f.limite == null ? '' : ' de ${f.limite}'}',
      if (f.restantes != null) f.restantes! >= 0 ? 'pode faltar mais ${f.restantes}' : 'passou ${-f.restantes!} do limite',
    ].join(' · ');
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showModalBottomSheet<void>(
            context: context, isScrollControlled: true, showDragHandle: true, builder: (_) => _Detalhe(d, f)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w700))),
              if (d.media.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
                  child: Text(d.media, style: TextStyle(fontWeight: FontWeight.w800, color: cs.primary)),
                ),
            ]),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                  value: pres == null ? 0 : pres / 100, minHeight: 7, color: corFreq, backgroundColor: cs.outlineVariant.withValues(alpha: 0.3)),
            ),
            const SizedBox(height: 6),
            Row(children: [
              Text('Presença ${_pct(pres)}', style: TextStyle(color: corFreq, fontWeight: FontWeight.w600, fontSize: 12)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(faltasTxt,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant), textAlign: TextAlign.end, overflow: TextOverflow.ellipsis)),
            ]),
            if (d.etapas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in d.etapas)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text('${e['rotulo']}: ${'${e['nota']}'.isEmpty ? '-' : e['nota']}'),
                  ),
              ]),
            ],
            if (d.situacao.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(d.situacao, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _Detalhe extends StatelessWidget {
  final Disciplina d;
  final Frequencia f;
  const _Detalhe(this.d, this.f);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget linha(String a, String b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(a, style: TextStyle(color: cs.onSurfaceVariant))),
            Text(b, style: const TextStyle(fontWeight: FontWeight.w600)),
          ]),
        );
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, sc) => ListView(controller: sc, padding: const EdgeInsets.fromLTRB(20, 0, 20, 24), children: [
        Text(d.nome, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        linha('Média', d.media.isEmpty ? '-' : d.media),
        if (d.situacao.isNotEmpty) linha('Situação', d.situacao),
        linha('Carga horária', _num(d.carga)),
        linha('Faltas', _num(d.faltas ?? 0)),
        linha('Presença', _pct(f.percentual)),
        linha('Faltas (%)', _pct(f.faltasPercentual)),
        if (f.limite != null) linha('Limite de faltas (${Cfg.frequenciaMinima}% de presença)', '${f.limite}'),
        if (f.restantes != null) linha('Ainda pode faltar', f.restantes! >= 0 ? '${f.restantes}' : 'passou do limite'),
        if (d.etapas.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Etapas', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          for (final e in d.etapas)
            linha('${e['rotulo']}', ['${e['nota']}'.isEmpty ? '-' : '${e['nota']}', if (e['faltas'] != null) '${_num((e['faltas'] as num).toDouble())} falta(s)'].join(' · ')),
        ],
        if (d.avaliacoes.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Avaliações', style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700)),
          for (final a in d.avaliacoes)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text('${a['descricao']}'),
              subtitle: Text([
                if ('${a['etapa']}'.isNotEmpty) '${a['etapa']}',
                if ('${a['data']}'.isNotEmpty) '${a['data']}',
                if ('${a['peso']}'.isNotEmpty) 'peso ${a['peso']}',
              ].join(' · ')),
              trailing: Text(
                  ['${a['nota']}'.isEmpty ? '-' : '${a['nota']}', if ('${a['max']}'.isNotEmpty) '/ ${a['max']}'].join(' '),
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
  }
}

class _NotasAva extends StatelessWidget {
  final Map<String, dynamic> curso;
  const _NotasAva(this.curso);

  @override
  Widget build(BuildContext context) {
    final notas = lista(curso['notas']).map(mapa).toList();
    final total = notas.where((n) => n['tipo'] == 'course').firstOrNull;
    final itens = notas.where((n) => n['tipo'] != 'course').toList();
    final lancadas = itens.where((n) => '${n['nota']}'.isNotEmpty).length;
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        title: Text('${curso['nome']}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('$lancadas de ${itens.length} nota(s) lançada(s)'
            '${total != null && '${total['nota']}'.isNotEmpty ? ' · total ${total['nota']}' : ''}'),
        children: [
          for (final n in itens)
            ListTile(
              dense: true,
              title: Text('${n['nome']}'),
              subtitle: '${n['feedback']}'.isEmpty ? null : Text('${n['feedback']}', maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: Text(
                '${n['nota']}'.isEmpty ? '-' : '${n['nota']}${'${n['pct']}'.isEmpty ? '' : '  (${n['pct']})'}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}
