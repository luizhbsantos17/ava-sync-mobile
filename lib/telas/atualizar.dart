import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../atualizacao.dart';
import '../config.dart';
import '../util.dart';

/// Pergunta se quer atualizar. [automatico]: veio da verificacao ao abrir o app
/// (oferece "Depois", que silencia este build por 1 dia).
Future<void> oferecerAtualizacao(BuildContext context, AtualizacaoInfo info, {bool automatico = false}) async {
  final atualizar = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.system_update_alt_rounded),
      title: const Text('Nova versão disponível'),
      content: Text('A versão ${info.build} do AVA Sync está pronta (você tem a ${info.buildInstalado}).\n\n'
          'O app baixa a atualização e o Android pede para confirmar a instalação. '
          'Seus dados e o login continuam.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(automatico ? 'Depois' : 'Fechar')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.download_rounded),
          label: const Text('Atualizar agora'),
        ),
      ],
    ),
  );
  if (atualizar != true) {
    if (automatico) await Cfg.adiarAtualizacao(info.build, agoraSeg() + 86400);
    return;
  }
  if (!context.mounted) return;
  await baixarEInstalar(context, info);
}

Future<void> baixarEInstalar(BuildContext context, AtualizacaoInfo info) async {
  final progresso = ValueNotifier<(int, int?)>((0, null));
  var cancelado = false;
  final nav = Navigator.of(context, rootNavigator: true);
  final mensageiro = ScaffoldMessenger.maybeOf(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Baixando atualização'),
        content: ValueListenableBuilder<(int, int?)>(
          valueListenable: progresso,
          builder: (_, v, _) {
            final (rec, total) = v;
            final frac = total == null || total == 0 ? null : rec / total;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              LinearProgressIndicator(value: frac),
              const SizedBox(height: 12),
              Text(total == null ? fmtTamanho(rec) : '${fmtTamanho(rec)} de ${fmtTamanho(total)}'),
            ]);
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              cancelado = true;
            },
            child: const Text('Cancelar'),
          ),
        ],
      ),
    ),
  );

  String? erro;
  try {
    final pasta = await getTemporaryDirectory();
    final apk = await DownloadApk.baixar(
      info.apkUrl,
      Directory('${pasta.path}/atualizacao'),
      progresso: (r, t) => progresso.value = (r, t),
      cancelado: () => cancelado,
    );
    nav.pop();
    final r = await OpenFilex.open(apk.path, type: 'application/vnd.android.package-archive');
    if (r.type != ResultType.done) {
      erro = r.type == ResultType.permissionDenied
          ? 'Permita que o AVA Sync instale apps (Configurações > Apps > AVA Sync > Instalar apps desconhecidos) e tente de novo.'
          : 'Não consegui abrir o instalador: ${r.message}';
    }
  } on DownloadCancelado {
    nav.pop();
    return;
  } catch (e) {
    nav.pop();
    erro = '$e'.replaceFirst('Exception: ', '');
  } finally {
    progresso.dispose();
  }
  if (erro != null) {
    mensageiro?.showSnackBar(SnackBar(
      content: Text(erro),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
          label: 'No navegador',
          onPressed: () => launchUrl(Uri.parse(info.releaseUrl), mode: LaunchMode.externalApplication)),
    ));
  }
}
