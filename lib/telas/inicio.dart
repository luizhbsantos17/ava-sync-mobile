import 'package:material_ui/material_ui.dart';

import '../estado_app.dart';
import '../util.dart';
import 'aulas.dart';
import 'desempenho.dart';
import 'perfil.dart';
import 'qacademico_tela.dart';
import 'busca.dart';
import 'comum.dart';
import 'curso.dart';
import 'tarefa.dart';
import '../classificar.dart';
import '../config.dart';
import 'social.dart';

class InicioTela extends StatefulWidget {
  const InicioTela({super.key});
  @override
  State<InicioTela> createState() => _InicioTelaState();
}

class _InicioTelaState extends State<InicioTela> {
  int _aba = 0;
  static const _titulos = ['Prazos', 'Matérias', 'Acadêmico', 'Novidades', 'Perfil'];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) {
        final ult = app.snap['gerado_em'];
        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              GestureDetector(onTap: () => setState(() => _aba = 4), child: const Avatar(tamanho: 38)),
              const SizedBox(width: 11),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_titulos[_aba], style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3)),
                  Text(
                    app.sincronizando
                        ? app.progresso
                        : ult == null
                            ? 'Ainda não sincronizado'
                            : 'Atualizado ${fmtRelativo(ult)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ]),
              ),
            ]),
            actions: [
              IconButton(
                tooltip: 'Abrir espaço Social',
                icon: const Icon(Icons.forum_outlined),
                onPressed: () => Navigator.of(context).push(SocialTela.rota()),
              ),
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
          // Sem "const": as abas leem o estado do app (materias, "Semestre atual/Todas",
          // dados da sincronizacao). Um widget const nunca e reconstruido, entao a troca so
          // aparecia depois de sair e voltar para a aba.
          body: Stack(fit: StackFit.expand, children: [
            Positioned.fill(
              child: switch (_aba) {
                0 => PrazosAba(
                    abrirMaterias: () => setState(() => _aba = 1),
                    abrirSemana: () {
                      segmentoAcademico.value = 2;
                      setState(() => _aba = 2);
                    }),
                1 => MateriasAba(),
                2 => DesempenhoAba(),
                3 => NovidadesAba(),
                _ => PerfilAba(),
              },
            ),
            const ColetorOculto(), // Q-Academico junto com a sincronizacao
          ]),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) => setState(() => _aba = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.event_note_outlined), selectedIcon: Icon(Icons.event_note), label: 'Prazos'),
              NavigationDestination(icon: Icon(Icons.menu_book_outlined), selectedIcon: Icon(Icons.menu_book), label: 'Matérias'),
              NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Acadêmico'),
              NavigationDestination(
                  icon: Icon(Icons.notifications_none), selectedIcon: Icon(Icons.notifications), label: 'Novidades'),
              NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
            ],
          ),
        );
      },
    );
  }
}

Widget _atualizavel(Widget filho) => RefreshIndicator(onRefresh: app.sincronizar, child: filho);

class PrazosAba extends StatelessWidget {
  final VoidCallback? abrirMaterias;
  final VoidCallback? abrirSemana;
  const PrazosAba({super.key, this.abrirMaterias, this.abrirSemana});

  Widget _boasVindas(BuildContext context, int semana) {
    final primeiroNome = Cfg.usuarioNome.trim().split(RegExp(r'\s+')).firstOrNull;
    final saudacao = primeiroNome == null || primeiroNome.isEmpty ? 'Seu semestre em foco' : 'Olá, $primeiroNome';
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [
          Color.lerp(Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.primary, 0.30)!,
          Color.lerp(Theme.of(context).colorScheme.surface, Theme.of(context).colorScheme.primary, 0.10)!,
        ]),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
        boxShadow: [BoxShadow(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.14), blurRadius: 28, offset: const Offset(0, 12))],
      ),
      child: Stack(children: [
        Positioned(right: -10, top: -12, child: Icon(Icons.auto_awesome_rounded, size: 96, color: Colors.white.withValues(alpha: 0.045))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.wb_twilight_rounded, size: 16, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 7),
            Text(fmtData(DateTime.now().millisecondsSinceEpoch ~/ 1000, hora: false).toUpperCase(),
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.05, color: Color(0xFFD5C5FF))),
          ]),
          const SizedBox(height: 12),
          Text(saudacao, style: const TextStyle(fontSize: 25, height: 1.1, fontWeight: FontWeight.w700, letterSpacing: -0.7)),
          const SizedBox(height: 7),
          Text('Acompanhe seus prazos e mantenha cada matéria no ritmo certo.',
              style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white.withValues(alpha: 0.72))),
          const SizedBox(height: 17),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.09), borderRadius: BorderRadius.circular(30)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(semana == 0 ? Icons.check_circle_outline_rounded : Icons.bolt_rounded, size: 15, color: const Color(0xFFD7C5FF)),
              const SizedBox(width: 6),
              Text(semana == 0 ? 'Tudo sob controle' : '$semana prazos nos próximos 7 dias',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFF4EEFF))),
            ]),
          ),
        ]),
      ]),
    );
  }

  /// Painel da tela inicial. Com [onTap], vira um botao (efeito de toque + seta).
  Widget _indicador(BuildContext context, IconData icon, String valor, String rotulo,
      {bool destaque = false, VoidCallback? onTap}) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Material(
        color: destaque ? cs.primary.withValues(alpha: 0.11) : cs.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: (destaque ? cs.primary : cs.outlineVariant).withValues(alpha: 0.18)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 10, 13),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 17, color: cs.primary),
            const Spacer(),
            if (onTap != null) Icon(Icons.chevron_right_rounded, size: 16, color: cs.onSurfaceVariant),
          ]),
          const SizedBox(height: 9),
          Text(valor, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 2),
          Text(rotulo, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itens = app.prazos();
    final agora = agoraSeg();
    final daSemana = itens.where((e) => (e['ts'] as int) >= agora && (e['ts'] as int) < agora + 7 * 86400).toList();
    final abertas = itens.where((e) => e['tipo'] == 'tarefa' && mapa(e['item'])['situacao'] != 'submitted').toList();
    final semana = daSemana.length;
    final pendentes = abertas.length;
    void abrirLista(String titulo, List<Map<String, dynamic>> l, String vazio) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => ListaItensTela(titulo: titulo, itens: l, vazio: vazio)));
    final resumo = Column(children: [
      _boasVindas(context, semana),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(children: [
          _indicador(context, Icons.event_available_rounded, '$semana', 'Nesta semana',
              destaque: true, onTap: () => abrirLista('Nesta semana', daSemana, 'Nada nos próximos 7 dias.')),
          const SizedBox(width: 9),
          _indicador(context, Icons.assignment_turned_in_outlined, '$pendentes', 'Tarefas abertas',
              onTap: () => abrirLista('Tarefas abertas', abertas, 'Nenhuma tarefa aberta.')),
          const SizedBox(width: 9),
          _indicador(context, Icons.menu_book_rounded, '${app.cursos.length}', 'Matérias', onTap: abrirMaterias),
        ]),
      ),
      AulasHoje(verSemana: abrirSemana),
      const SizedBox(height: 14),
    ]);
    if (itens.isEmpty) {
      return _atualizavel(ListView(children: [
        resumo,
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
        resumo,
        if (Cfg.verTodas)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text('Mostrando todas as matérias (inclusive de semestres anteriores).', style: TextStyle(fontSize: 12)),
          ),
        for (final g in grupos.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(children: [
              Container(width: 4, height: 18, decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(4))),
              const SizedBox(width: 9),
              Text(g.key, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 10),
              Expanded(child: Divider(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.35))),
            ]),
          ),
          for (final it in g.value)
            Card(child: ItemLinha(it, mostrarCurso: true)),
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
          'entrega' => Icons.task_alt,
          'nota' => Icons.grade_outlined,
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


/// Lista aberta pelos paineis da tela inicial ("Nesta semana", "Tarefas abertas").
class ListaItensTela extends StatelessWidget {
  final String titulo;
  final List<Map<String, dynamic>> itens;
  final String vazio;
  const ListaItensTela({super.key, required this.titulo, required this.itens, required this.vazio});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(titulo)),
      body: itens.isEmpty
          ? Vazio(Icons.celebration_outlined, vazio)
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [for (final it in itens) Card(child: ItemLinha(it, mostrarCurso: true))],
            ),
    );
  }
}
