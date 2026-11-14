import 'package:material_ui/material_ui.dart';

import '../estado_app.dart';
import '../qacademico.dart';

/// Cor fixa e bonita para cada disciplina (mesma cor em todas as telas).
Color corDisciplina(String nome, Brightness b) {
  var h = 0;
  for (final c in norm(nome).codeUnits) {
    h = (h * 31 + c) & 0x7fffffff;
  }
  const matizes = [262.0, 200.0, 152.0, 28.0, 330.0, 46.0, 176.0, 4.0, 226.0, 290.0, 96.0, 12.0];
  final hue = matizes[h % matizes.length];
  return b == Brightness.dark
      ? HSLColor.fromAHSL(1, hue, 0.70, 0.72).toColor()
      : HSLColor.fromAHSL(1, hue, 0.55, 0.45).toColor();
}

int _agoraMin() {
  final n = DateTime.now();
  return n.hour * 60 + n.minute;
}

/// Situacao de uma aula de hoje: passou, agora ou depois.
enum MomentoAula { passou, agora, depois }

MomentoAula momento(Aula a, {int? minutos}) {
  final m = minutos ?? _agoraMin();
  if (m >= a.minutosFim) return MomentoAula.passou;
  if (m >= a.minutosInicio) return MomentoAula.agora;
  return MomentoAula.depois;
}

/// Bloco de uma aula (linha do tempo): horario, disciplina com a cor dela, sala e
/// quantas faltas custa faltar.
class AulaTile extends StatelessWidget {
  final Aula aula;
  final MomentoAula? quando;
  const AulaTile(this.aula, {super.key, this.quando});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cor = corDisciplina(aula.disciplina, Theme.of(context).brightness);
    final agora = quando == MomentoAula.agora;
    final passou = quando == MomentoAula.passou;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: passou ? 0.5 : 1,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: agora ? 0.20 : 0.10),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cor.withValues(alpha: agora ? 0.8 : 0.25), width: agora ? 1.6 : 1),
        ),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(
              width: 5,
              decoration: BoxDecoration(color: cor, borderRadius: const BorderRadius.horizontal(left: Radius.circular(16))),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(aula.inicio, style: TextStyle(fontWeight: FontWeight.w800, color: cor)),
                Text(aula.fim, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ]),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Row(children: [
                    Expanded(
                      child: Text(aula.disciplina,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                    if (agora)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(20)),
                        child: Text('AGORA',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: cs.surface, letterSpacing: 0.6)),
                      ),
                  ]),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (aula.detalhe.isNotEmpty) aula.detalhe,
                      '${aula.aulas} aula${aula.aulas == 1 ? '' : 's'} · faltar = ${aula.aulas} falta${aula.aulas == 1 ? '' : 's'}',
                    ].join(' · '),
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Aulas de hoje" para o topo da tela de prazos. Sem horario importado, nao aparece.
class AulasHoje extends StatelessWidget {
  final VoidCallback? verSemana;
  const AulasHoje({super.key, this.verSemana});

  @override
  Widget build(BuildContext context) {
    if (app.horario.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final hoje = DateTime.now().weekday;
    final aulas = aulasDoDia(app.horario, hoje);
    final restantes = aulas.where((a) => momento(a) != MomentoAula.passou).toList();
    // sem aula hoje (ou ja acabou): mostra o proximo dia com aula
    var titulo = 'Aulas de hoje';
    var lista = aulas;
    if (restantes.isEmpty) {
      for (var i = 1; i <= 7; i++) {
        final d = (hoje - 1 + i) % 7 + 1;
        final l = aulasDoDia(app.horario, d);
        if (l.isNotEmpty) {
          titulo = i == 1 ? 'Amanhã' : 'Próximas aulas · ${diasSemana[d - 1]}';
          lista = l;
          break;
        }
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 2),
        child: Row(children: [
          Icon(Icons.schedule_rounded, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
          if (verSemana != null) TextButton(onPressed: verSemana, child: const Text('Semana')),
        ]),
      ),
      if (lista.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('Sem aulas no horário.', style: TextStyle(color: cs.onSurfaceVariant)),
        )
      else
        for (final a in lista) AulaTile(a, quando: identical(lista, aulas) ? momento(a) : null),
    ]);
  }
}
