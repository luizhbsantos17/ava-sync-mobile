import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

/// O que muda entre celular e computador. Telas e regras de negócio são as mesmas;
/// só as partes de sistema (segundo plano, notificação, agenda, instalador) dependem daqui.
class Plataforma {
  /// Só para testes: força desktop (true) ou celular (false).
  static bool? teste;

  static bool get desktop => teste ?? (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static bool get celular => !desktop;

  /// Agenda do aparelho (Google Agenda etc.) só existe no celular.
  static bool get temAgenda => celular;

  /// Nome do sistema, para textos e para escolher o arquivo de atualização.
  static String get nome => Platform.isWindows
      ? 'Windows'
      : Platform.isMacOS
      ? 'macOS'
      : Platform.isLinux
      ? 'Linux'
      : 'Android';
}

/// Abre um arquivo com o programa padrão do sistema. Devolve o erro, ou null se abriu.
Future<String?> abrirNoSistema(String caminho, {String? tipo}) async {
  if (Plataforma.desktop) {
    final ok = await launchUrl(Uri.file(caminho));
    return ok ? null : 'Nenhum programa para abrir este arquivo.';
  }
  final r = await OpenFilex.open(caminho, type: tipo);
  if (r.type == ResultType.done) return null;
  return r.type == ResultType.permissionDenied ? 'permissao' : r.message;
}
