import 'package:material_ui/material_ui.dart';

import '../estado_app.dart';
import '../util.dart';
import 'ajustes.dart';
import 'busca.dart';
import 'comum.dart';
import 'curso.dart';
import 'tarefa.dart';
import '../classificar.dart';
import '../config.dart';

class InicioTela extends StatefulWidget {
  const InicioTela({super.key});
  @override
  State<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends State<InicioTela> {
  int _aba = 0;
  static const _titulos = ['Prazos', 'Matérias', 'Novidades', 'Ajustes'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final ult = app.snap['gerado_em'];
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_titulos[_aba]),
              Text(
                app.sincronizando
                    ? app.progresso
                    : ult == null
                        ? 'Ainda não sincronizado'
                        : 'Atualizado ${fmtRelativo(ult)}',
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'Buscar',
                icon: const Icon(Icons.search),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BuscaTela())),
              ),
              app.sincronizando
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : IconButton(tooltip: 'Sincronizar agora', icon: const Icon(Icons.sync), onPressed: app.sincronizar),
            ],
            bottom: app.erro == null
                ? null
                : PreferredSize(
                    preferredSize: const Size.fromHeight(36),
                    child: Container(
                      width: double.infinity,
                      color: Theme.of(context).colorScheme.errorContainer,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(app.erro!, maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                  ),
          ),
          body: switch (_aba) {
            0 => const PrazosAba(),
            1 => const MateriasAba(),
            2 => const NovidadesAba(),
            _ => const AjustesAba(),
          },
          bottomNavigationBar: NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) => setState(() => _aba = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Prazos'),
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Matérias'),
              NavigationDestination(
                  icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Novidades'),
              NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Ajustes'),
            ],
          ),
        );
      },
    );
  }
}

Widget _atualizavel(Widget filho) => RefreshIndicator(onRefresh: app.sincronizar, child: filho);

class PrazosAba extends StatelessWidget {
  const PrazosAba({super.key});

  @override
  Widget build(BuildContext context) {
    final itens = app.prazos();
    if (itens.isEmpty) {
      return _atualizavel(ListView(children: [
        const SizedBox(height: 120),
        Vazio(Icons.celebration_outlined,
            app.snap.isEmpty ? 'Puxe para baixo para sincronizar.' : 'Nenhum prazo pela frente.'),
      ]));
    }
    final grupos = <String, List<Map<String, dynamic>>>{};
    for (final it in itens) {
      final diff = (it['ts'] as int) - agoraSeg();
      final g = diff < 0
          ? 'Venceu'
          : diff < 86400
              ? 'Próximas 24 horas'
              : diff < 7 * 86400
                  ? 'Próximos 7 dias'
                  : 'Mais adiante';
      grupos.putIfAbsent(g, () => []).add(it);
    }
    return _atualizavel(ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (Cfg.verTodas)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Mostrando todas as matérias (inclusive de semestres anteriores).', style: TextStyle(fontSize: 12)),
          ),
        for (final g in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(g.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          for (final it in g.value)
            Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4), child: ItemLinha(it, mostrarCurso: true)),
        ],
      ],
    ));
  }
}

class MateriasAba extends StatelessWidget {
  const MateriasAba({super.key});

  Future<void> _menu(BuildContext context, Map<String, dynamic> c) async {
    final atual = app.ehAtual(c);
    final manual = Cfg.atualManual.containsKey('${c['id']}');
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(title: Text('${c['nome']}'), subtitle: Text(atual ? 'Semestre atual' : 'Semestre anterior')),
          ListTile(
              leading: const Icon(Icons.school_outlined),
              title: const Text('É do semestre atual'),
              onTap: () => Navigator.pop(ctx, 'sim')),
          ListTile(
              leading: const Icon(Icons.history), title: const Text('É de semestre anterior'), onTap: () => Navigator.pop(ctx, 'nao')),
          if (manual)
            ListTile(leading: const Icon(Icons.auto_mode), title: const Text('Voltar ao automático'), onTap: () => Navigator.pop(ctx, 'auto')),
        ]),
      ),
    );
    if (r == null) return;
    await app.marcarAtual(c['id'], r == 'auto' ? null : r == 'sim');
  }

  @override
  Widget build(BuildContext context) {
    final cursos = app.cursos;
    final escondidas = app.todosCursos.length - app.todosCursos.where(app.ehAtual).length;
    final cab = Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(children: [
        Expanded(
          child: SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Semestre atual')),
              ButtonSegment(value: true, label: Text('Todas')),
            ],
            selected: {Cfg.verTodas},
            onSelectionChanged: (_) => app.alternarVerTodas(),
          ),
        ),
      ]),
    );
    if (cursos.isEmpty) {
      return _atualizavel(ListView(children: [
        cab,
        const SizedBox(height: 100),
        const Vazio(Icons.menu_book, 'Nenhuma matéria aqui. Puxe para sincronizar ou veja "Todas".'),
      ]));
    }
    return _atualizavel(ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        cab,
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
          child: Text(
              '${!Cfg.verTodas && escondidas > 0 ? '$escondidas matéria(s) de semestres anteriores escondida(s). ' : ''}'
              'Toque e segure numa matéria para corrigir o semestre.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
        ),
        for (final c in cursos)
          Builder(builder: (context) {
            final pend = lista(c['tarefas'])
                .map(mapa)
                .where((t) => t['situacao'] != 'submitted' && ((t['entrega'] as num?)?.toInt() ?? 0) > agoraSeg())
                .length;
            final provas = itensDoCurso(c).provas.where((e) => (e['ts'] as int) > agoraSeg()).length;
            final atual = app.ehAtual(c);
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(child: Text('${c['nome']}'.trim().isEmpty ? '?' : '${c['nome']}'.trim()[0])),
                title: Text('${c['nome']}'),
                subtitle: Text('${atual ? '' : 'semestre anterior · '}$pend tarefa(s) pendente(s) · $provas prova(s) pela frente'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CursoTela(cursoId: c['id']))),
                onLongPress: () => _menu(context, c),
              ),
            );
          }),
      ],
    ));
  }
}

class NovidadesAba extends StatelessWidget {
  const NovidadesAba({super.key});

  @override
  Widget build(BuildContext context) {
    final hist = lista(app.estado['historico']).map(mapa).toList();
    if (hist.isEmpty) {
      return _atualizavel(ListView(children: const [SizedBox(height: 120), Vazio(Icons.notifications_none, 'Nenhuma novidade ainda.')]));
    }
    final porDia = <String, List<Map<String, dynamic>>>{};
    for (final h in hist) {
      porDia.putIfAbsent(fmtData(h['ts'], hora: false), () => []).add(h);
    }
    IconData icone(String? t) => switch (t) {
          'tarefa' => Icons.assignment_outlined,
          'prova' => Icons.quiz_outlined,
          'aviso' => Icons.campaign_outlined,
          'material' => Icons.attach_file,
          _ => Icons.info_outline,
        };
    return _atualizavel(ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final d in porDia.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(d.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
          for (final h in d.value)
            ListTile(
              dense: true,
              leading: Icon(icone(h['tipo'])),
              title: Text('${h['texto']}'),
              subtitle: '${h['curso'] ?? ''}'.isEmpty ? null : Text('${h['curso']}'),
              onTap: h['tarefaId'] == null
                  ? null
                  : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => TarefaTela(tarefaId: h['tarefaId']))),
            ),
        ],
      ],
    ));
  }
}
