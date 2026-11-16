import 'package:material_ui/material_ui.dart';

import '../../social/models.dart';
import 'chat.dart';

/// Conversa aberta no painel da direita (tela larga, como no Discord).
class ChatAberto {
  final SocialConversation conversa;
  final SocialChannel canal;
  const ChatAberto(this.conversa, this.canal);
}

/// Existe acima das telas do Social só quando a janela é larga. Quem quer abrir uma
/// conversa chama [abrirChat]: com painel, ela aparece ao lado da lista; sem painel
/// (celular ou janela estreita), abre numa tela nova como sempre.
class PainelConversa extends InheritedNotifier<ValueNotifier<ChatAberto?>> {
  const PainelConversa({super.key, required ValueNotifier<ChatAberto?> super.notifier, required super.child});

  static ValueNotifier<ChatAberto?>? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PainelConversa>()?.notifier;

  /// Como [maybeOf], mas redesenha quem chamou quando outra conversa é aberta.
  static ValueNotifier<ChatAberto?>? watch(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PainelConversa>()?.notifier;
}

/// Abre a conversa no painel (tela larga) ou numa tela nova (celular).
/// [trocandoCanal]: veio do seletor de canal de dentro da conversa (troca sem empilhar).
Future<void> abrirChat(BuildContext context, SocialConversation c, SocialChannel canal, {bool trocandoCanal = false}) async {
  final painel = PainelConversa.maybeOf(context);
  if (painel != null) {
    painel.value = ChatAberto(c, canal);
    return;
  }
  final nav = Navigator.of(context);
  if (trocandoCanal) {
    await nav.pushReplacement(PageRouteBuilder(
      pageBuilder: (_, _, _) => ChatTela(conversa: c, canal: canal),
      transitionDuration: const Duration(milliseconds: 160),
      transitionsBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    ));
  } else {
    await nav.push(MaterialPageRoute(builder: (_) => ChatTela(conversa: c, canal: canal)));
  }
}
