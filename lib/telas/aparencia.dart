import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../config.dart';
import '../tema.dart';

Future<void> aplicarTema(Tema t) async {
  temaAtual.value = t;
  await Cfg.setTemaJson(jsonEncode(t.toJson()));
}

const _cores = [
  Color(0xFFB49AFF), Color(0xFF6EC6FF), Color(0xFF7BD88F), Color(0xFFFFA36C), Color(0xFFFF8AC6),
  Color(0xFFFFD166), Color(0xFF5EEAD4), Color(0xFFF87171), Color(0xFFA3A3A3), Color(0xFF818CF8),
];

class AparenciaTela extends StatelessWidget {
  const AparenciaTela({super.key});

  Future<void> _editarJson(BuildContext context) async {
    final c = TextEditingController(text: temaAtual.value.paraTexto());
    String? erro;
    final novo = await showDialog<Tema>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Tema em JSON'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Campos: cor, modo (escuro/claro/sistema), fundo, cartao, destaque (cores "#RRGGBB"), '
                  'raio (0-40), fonte (0.8-1.4), compacto (true/false).',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Flexible(
                child: TextField(
                  controller: c,
                  maxLines: 14,
                  minLines: 8,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(errorText: erro, errorMaxLines: 3),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: c.text));
                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Tema copiado.')));
                },
                child: const Text('Copiar')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                try {
                  final j = jsonDecode(c.text);
                  if (j is! Map) throw const FormatException('O tema precisa ser um objeto { ... }.');
                  Navigator.pop(ctx, Tema.fromJson(Map<String, dynamic>.from(j)));
                } on FormatException catch (e) {
                  set(() => erro = e.message);
                }
              },
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (novo != null) await aplicarTema(novo);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Tema>(
      valueListenable: temaAtual,
      builder: (context, t, _) {
        final cs = Theme.of(context).colorScheme;
        Widget secao(String s) => Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
              child: Text(s, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: cs.primary)),
            );
        return Scaffold(
          appBar: AppBar(title: const Text('Aparência'), actions: [
            IconButton(
                tooltip: 'Restaurar padrão', icon: const Icon(Icons.restart_alt), onPressed: () => aplicarTema(Tema.padrao)),
          ]),
          body: ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            secao('Temas prontos'),
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                for (final p in Tema.presets.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => aplicarTema(p.value.copyWith(raio: t.raio, fonte: t.fonte, compacto: t.compacto)),
                      child: Container(
                        width: 86,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: p.value.fundo ?? (p.value.modo == 'claro' ? const Color(0xFFF8F6FC) : Colors.black),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: p.value.cor == t.cor ? cs.primary : cs.outlineVariant, width: p.value.cor == t.cor ? 2 : 1),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(colors: [p.value.cor, p.value.segundaCor]))),
                          const SizedBox(height: 6),
                          Text(p.key,
                              style: TextStyle(
                                  fontSize: 11, color: p.value.modo == 'claro' ? Colors.black87 : Colors.white70),
                              overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                    ),
                  ),
              ]),
            ),
            secao('Cor principal'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in _cores)
                  GestureDetector(
                    onTap: () => aplicarTema(t.copyWith(cor: c)),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(color: c == t.cor ? cs.onSurface : Colors.transparent, width: 3),
                      ),
                    ),
                  ),
              ]),
            ),
            secao('Modo'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'escuro', label: Text('Escuro'), icon: Icon(Icons.dark_mode_outlined)),
                  ButtonSegment(value: 'claro', label: Text('Claro'), icon: Icon(Icons.light_mode_outlined)),
                  ButtonSegment(value: 'sistema', label: Text('Sistema'), icon: Icon(Icons.brightness_auto_outlined)),
                ],
                selected: {t.modo},
                onSelectionChanged: (s) => aplicarTema(t.copyWith(modo: s.first)),
              ),
            ),
            secao('Cantos arredondados'),
            Slider(
                value: t.raio, min: 0, max: 32, divisions: 16, label: t.raio.toStringAsFixed(0), onChanged: (v) => aplicarTema(t.copyWith(raio: v))),
            secao('Tamanho do texto'),
            Slider(
                value: t.fonte,
                min: 0.85,
                max: 1.3,
                divisions: 9,
                label: '${(t.fonte * 100).round()}%',
                onChanged: (v) => aplicarTema(t.copyWith(fonte: v))),
            SwitchListTile(
              title: const Text('Modo compacto'),
              subtitle: const Text('Listas e botões mais juntos'),
              value: t.compacto,
              onChanged: (v) => aplicarTema(t.copyWith(compacto: v)),
            ),
            secao('Para quem gosta de mexer'),
            ListTile(
              leading: const Icon(Icons.data_object),
              title: const Text('Editar tema em JSON'),
              subtitle: const Text('Controle total das cores (fundo, cartões, destaque) e copie/cole temas'),
              onTap: () => _editarJson(context),
            ),
            secao('Prévia'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.assignment_outlined),
                title: const Text('Relatório de Redes'),
                subtitle: const Text('Entrega amanhã 23:59 · não entregue'),
                trailing: FilledButton(onPressed: () {}, child: const Text('Abrir')),
              ),
            ),
          ]),
        );
      },
    );
  }
}
