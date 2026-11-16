import 'dart:io';

/// Abre o app quando a pessoa entra no computador (escondido na bandeja).
/// Sem pacote externo: cada sistema tem um jeito simples e documentado.
/// - Windows: chave `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`;
/// - Linux: arquivo `.desktop` em `~/.config/autostart`;
/// - macOS: LaunchAgent em `~/Library/LaunchAgents`.
class IniciarComSistema {
  static String _id(String nome) => nome.replaceAll(' ', '');

  static Future<void> aplicar(bool ligado, {required String nome, List<String> argumentos = const []}) async {
    final exe = Platform.resolvedExecutable;
    try {
      if (Platform.isWindows) {
        const chave = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';
        if (ligado) {
          final cmd = ['"$exe"', ...argumentos].join(' ');
          await Process.run('reg', ['add', chave, '/v', _id(nome), '/t', 'REG_SZ', '/d', cmd, '/f']);
        } else {
          await Process.run('reg', ['delete', chave, '/v', _id(nome), '/f']);
        }
      } else if (Platform.isLinux) {
        final f = File('${Platform.environment['HOME']}/.config/autostart/${_id(nome).toLowerCase()}.desktop');
        if (ligado) {
          await f.parent.create(recursive: true);
          await f.writeAsString(conteudoDesktop(nome, exe, argumentos));
        } else if (await f.exists()) {
          await f.delete();
        }
      } else if (Platform.isMacOS) {
        final id = 'io.github.avasync.${_id(nome).toLowerCase()}';
        final f = File('${Platform.environment['HOME']}/Library/LaunchAgents/$id.plist');
        if (ligado) {
          await f.parent.create(recursive: true);
          await f.writeAsString(conteudoPlist(id, exe, argumentos));
        } else if (await f.exists()) {
          await f.delete();
        }
      }
    } catch (_) {
      // sem permissão ou comando ausente: o app segue funcionando, só não abre sozinho
    }
  }

  static String conteudoDesktop(String nome, String exe, List<String> args) =>
      '''[Desktop Entry]
Type=Application
Name=$nome
Exec="$exe"${args.map((a) => ' $a').join()}
X-GNOME-Autostart-enabled=true
''';

  static String conteudoPlist(String id, String exe, List<String> args) {
    final itens = [exe, ...args].map((a) => '    <string>${_xml(a)}</string>').join('\n');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$id</string>
  <key>ProgramArguments</key>
  <array>
$itens
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';
  }

  static String _xml(String s) => s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
}
