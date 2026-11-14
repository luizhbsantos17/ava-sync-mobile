import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../estado_app.dart';
import '../tema.dart';
import '../util.dart';
import 'ajustes.dart';
import 'aparencia.dart';
import 'desempenho.dart';
import '../qacademico.dart';

String nomeExibido() {
  final a = Cfg.perfilApelido;
  if (a.isNotEmpty) return a;
  return Cfg.usuarioNome.isEmpty ? 'Estudante' : Cfg.usuarioNome;
}

String iniciais(String nome) {
  final p = nome.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  if (p.length == 1) return p.first[0].toUpperCase();
  return (p.first[0] + p.last[0]).toUpperCase();
}

/// Foto (ou iniciais) com anel no gradiente do tema.
class Avatar extends StatelessWidget {
  final double tamanho;
  const Avatar({super.key, this.tamanho = 38});

  @override
  Widget build(BuildContext context) {
    final t = temaAtual.value;
    final foto = Cfg.perfilFoto;
    final temFoto = foto.isNotEmpty && File(foto).existsSync();
    return Container(
      width: tamanho,
      height: tamanho,
      padding: EdgeInsets.all(tamanho * 0.06),
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [t.cor, t.segundaCor])),
      child: ClipOval(
        child: temFoto
            ? Image.file(File(foto), fit: BoxFit.cover, key: ValueKey(foto))
            : Container(
                color: Theme.of(context).colorScheme.surface,
                alignment: Alignment.center,
                child: Text(iniciais(nomeExibido()),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: tamanho * 0.36, color: t.cor)),
              ),
      ),
    );
  }
}

class PerfilAba extends StatefulWidget {
  const PerfilAba({super.key});
  @override
  State<PerfilAba> createState() => _PerfilAbaState();
}

class _PerfilAbaState extends State<PerfilAba> {
  Future<void> _trocarFoto() async {
    final r = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('Escolher foto'), onTap: () => Navigator.pop(ctx, 'escolher')),
          if (Cfg.perfilFoto.isNotEmpty)
            ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Remover foto'), onTap: () => Navigator.pop(ctx, 'remover')),
        ]),
      ),
    );
    if (r == 'remover') {
      final f = File(Cfg.perfilFoto);
      if (await f.exists()) await f.delete();
      await Cfg.setPerfilFoto('');
    } else if (r == 'escolher') {
      final res = await FilePicker.pickFiles(type: FileType.image, dialogTitle: 'Foto de perfil');
      if (res.isEmpty) return;
      final bytes = await res.first.readAsBytes();
      final dir = await getApplicationSupportDirectory();
      // nome novo a cada troca: o Flutter guarda a imagem em cache pelo caminho
      final antigo = Cfg.perfilFoto;
      final f = File('${dir.path}/perfil_${agoraSeg()}.img');
      await f.writeAsBytes(bytes);
      await Cfg.setPerfilFoto(f.path);
      if (antigo.isNotEmpty && antigo != f.path) {
        try {
          await File(antigo).delete();
        } catch (_) {}
      }
    }
    if (mounted) setState(() {});
    app.avisarMudanca();
  }

  Future<void> _editar() async {
    final apelido = TextEditingController(text: Cfg.perfilApelido);
    final curso = TextEditingController(text: Cfg.perfilCurso);
    final bio = TextEditingController(text: Cfg.perfilBio);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar perfil'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: apelido, decoration: InputDecoration(labelText: 'Nome de exibição', hintText: Cfg.usuarioNome)),
            const SizedBox(height: 10),
            TextField(controller: curso, decoration: const InputDecoration(labelText: 'Curso / período', hintText: 'Ex.: Sistemas de Informação · 3º período')),
            const SizedBox(height: 10),
            TextField(controller: bio, maxLines: 3, maxLength: 160, decoration: const InputDecoration(labelText: 'Sobre você')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    if (ok != true) return;
    await Cfg.setPerfilApelido(apelido.text);
    await Cfg.setPerfilCurso(curso.text);
    await Cfg.setPerfilBio(bio.text);
    if (mounted) setState(() {});
    app.avisarMudanca();
  }

  Future<void> _exportarPagina() async {
    final fs = await QAcademico.paginasGuardadas();
    if (fs.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Nada para exportar: abra o Q-Acadêmico e importe primeiro.')));
      return;
    }
    await SharePlus.instance.share(ShareParams(
        files: [for (final f in fs) XFile(f.path)],
        text: 'Páginas do Q-Acadêmico (AVA Sync). Contêm suas notas: mande só para quem for ajustar o app.'));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final cursos = app.cursos;
    var entregues = 0, pendentes = 0;
    final agora = agoraSeg();
    for (final c in cursos) {
      for (final t in lista(c['tarefas']).map(mapa)) {
        if (t['situacao'] == 'submitted') {
          entregues++;
        } else if (((t['entrega'] as num?)?.toInt() ?? 0) > agora) {
          pendentes++;
        }
      }
    }
    final emRisco = app.academico.where((d) => app.freqDe(d).emRisco).length;
    final aulasHoje = aulasDoDia(app.horario, DateTime.now().weekday).fold<int>(0, (s, a) => s + a.aulas);
    Widget numero(String v, String rotulo) => Expanded(
          child: Column(children: [
            Text(v, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            Text(rotulo, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant), textAlign: TextAlign.center),
          ]),
        );

    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      const SizedBox(height: 12),
      Center(
        child: Stack(children: [
          GestureDetector(onTap: _trocarFoto, child: const Avatar(tamanho: 104)),
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: cs.primary,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _trocarFoto,
                child: Padding(padding: const EdgeInsets.all(7), child: Icon(Icons.photo_camera, size: 18, color: cs.onPrimary)),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 12),
      Center(child: Text(nomeExibido(), style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800))),
      if (Cfg.perfilCurso.isNotEmpty)
        Center(child: Text(Cfg.perfilCurso, style: TextStyle(color: cs.onSurfaceVariant))),
      if (Cfg.perfilBio.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 6, 32, 0),
          child: Text(Cfg.perfilBio, textAlign: TextAlign.center),
        ),
      Center(child: TextButton.icon(onPressed: _editar, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar perfil'))),
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          child: Row(children: [
            numero('${cursos.length}', 'matérias'),
            numero('$entregues', 'entregues'),
            numero('$pendentes', 'pendentes'),
            if (app.horario.isNotEmpty) numero('$aulasHoje', 'aulas hoje'),
            if (app.academico.isNotEmpty) numero('$emRisco', 'perto do limite de faltas'),
          ]),
        ),
      ),
      ListTile(
        leading: const Icon(Icons.school_outlined),
        title: const Text('Q-Acadêmico'),
        subtitle: Text(app.academico.isEmpty
            ? 'Conectar para ver notas, faltas e frequência'
            : '${app.academico.length} disciplina(s) · atualizado ${fmtRelativo(app.academicoEm)}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await abrirQAcademico(context);
          if (mounted) setState(() {});
        },
      ),
      if (Cfg.qaLogin.isNotEmpty) ...[
        SwitchListTile(
          secondary: const Icon(Icons.sync),
          title: const Text('Atualizar Q-Acadêmico junto com o AVA'),
          subtitle: const Text('Com o app aberto, usando a senha lembrada'),
          value: Cfg.qaAuto,
          onChanged: (v) async {
            await Cfg.setQaAuto(v);
            setState(() {});
          },
        ),
        ListTile(
          leading: const Icon(Icons.percent),
          title: const Text('Frequência mínima'),
          subtitle: const Text('Usada para calcular quantas faltas ainda pode ter'),
          trailing: DropdownButton<int>(
            value: Cfg.frequenciaMinima,
            items: const [
              DropdownMenuItem(value: 75, child: Text('75%')),
              DropdownMenuItem(value: 70, child: Text('70%')),
              DropdownMenuItem(value: 80, child: Text('80%')),
              DropdownMenuItem(value: 85, child: Text('85%')),
            ],
            onChanged: (v) async {
              await Cfg.setFrequenciaMinima(v ?? 75);
              setState(() {});
              app.avisarMudanca();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.event_busy_outlined),
          title: const Text('Faltar um dia conta'),
          subtitle: const Text('Quando o horário não diz quantas aulas seguidas a disciplina tem'),
          trailing: DropdownButton<int>(
            value: Cfg.faltasPorDia,
            items: [for (final n in [1, 2, 3, 4]) DropdownMenuItem(value: n, child: Text('$n falta${n == 1 ? '' : 's'}'))],
            onChanged: (v) async {
              await Cfg.setFaltasPorDia(v ?? 2);
              setState(() {});
              app.avisarMudanca();
            },
          ),
        ),
        ListTile(
          leading: const Icon(Icons.key_off_outlined),
          title: const Text('Esquecer login do Q-Acadêmico'),
          onTap: () async {
            await Cfg.setQaSenha(null);
            await Cfg.setQaLogin('');
            setState(() {});
          },
        ),
      ],
      ListTile(
        leading: const Icon(Icons.palette_outlined),
        title: const Text('Aparência'),
        subtitle: const Text('Cores, modo claro/escuro, cantos, texto, tema em JSON'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AparenciaTela())),
      ),
      ListTile(
        leading: const Icon(Icons.settings_outlined),
        title: const Text('Ajustes'),
        subtitle: const Text('Conta, sincronização, notificações, agenda, IA, atualizações'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => Scaffold(appBar: AppBar(title: const Text('Ajustes')), body: const AjustesAba()))),
      ),
      ListTile(
        leading: const Icon(Icons.bug_report_outlined),
        title: const Text('Exportar páginas do Q-Acadêmico'),
        subtitle: const Text('Boletim, diários e horário lidos, para ajustar o leitor se algo vier errado'),
        onTap: _exportarPagina,
      ),
    ]);
  }
}
