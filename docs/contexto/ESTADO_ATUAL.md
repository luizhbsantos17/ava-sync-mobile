# Estado atual

Atualize esta página **no fim de toda tarefa**: mova itens entre as seções, registre
problemas conhecidos e ideias. Mantenha curta; o histórico detalhado fica no CHANGELOG.

Última atualização: 2026-11-16 (versão 0.8.0 + app de computador na branch `feature/desktop`)

## Pronto
- Sync do AVA com prazos, provas, avisos, materiais offline, livros e envio de atividades.
- Notificações (novidades, entrega, nota, prazo alterado/vencido) e lembretes 3d/1d/3h.
- Integração com a agenda do celular (Google Agenda).
- Atualização dentro do app, com "O que mudou" vindo do CHANGELOG.
- Perfil com foto e aparência personalizável (temas e JSON).
- Aba Acadêmico: disciplinas, boletim, horário, faltas restantes e simulador.
- Social v2 (estilo Discord): grupos com canais, mensagens diretas, amigos, perfis,
  presença e status, reações, respostas, edição, fixados, anexos cifrados, digitando,
  moderação (admin, dono, remover, banir), convites com validade, notificações.
  Banco e Edge Function já publicados no Supabase (compatíveis com o app 0.7.0).
- Canal beta instalável ao lado do oficial.
- Sync só do semestre atual; seleção de matérias por lista.

## Em andamento
- **App de computador** (Windows, Linux, macOS) na branch `feature/desktop`: mesmo código
  do Android, com bandeja, segundo plano por relógios, abrir com o sistema, layout largo,
  Social em painéis e instalador do Windows (Inno Setup) com atualização automática.
  `flutter analyze` e `flutter test` passam no Windows. Falta: compilar e abrir o app de
  verdade (no Windows local precisa do Modo de Desenvolvedor) e conferir o CI de Linux e macOS.
- **Social em tempo real** (mesma branch, issue #1): ação `inbox` na Edge Function (long
  polling da caixa de entrada) e `EscutaSocial` no app; notificação por conversa com nome e
  texto, acumulando até ler. **A Edge Function nova ainda não foi publicada**: até lá o app
  pergunta `notifications` a cada 5 s.
- **Push do Android (Firebase)** na mesma branch: decidido pelo dono em 2026-11-16. Código
  pronto (PushService.kt, `lib/social/push.dart`, tabela `social_push_tokens`, envio em
  `send_message`). **Falta o dono configurar o Firebase** (passo a passo em
  `docs/FIREBASE_PUSH.md`), publicar migration e função, e testar com o app fechado.
  O Kotlin do push nunca foi compilado (este PC não tem Android SDK; o CI compila).

## Problemas conhecidos / não verificado
- Social v2 ainda não foi testado em celular com duas contas reais (só testes de
  unidade e chamadas de erro na função). Conferir: envio de foto, envelope de chave
  entre dois aparelhos, notificação em segundo plano.
- Grupo da matéria não foi testado com conta de professor real.
- Sem push (FCM): com o app fechado a notificação chega em até ~15 min.
- Fotos são reduzidas e salvas em PNG (o Flutter não codifica JPEG sem pacote extra),
  então fotos grandes podem ficar perto do limite de 8 MB.
- Busca só procura nas mensagens já carregadas no aparelho.
- No app 0.7.0, mensagens de grupo apareceram como protegidas para o dono (dados
  intactos no servidor). A v2 guarda várias chaves por conversa e recebe as que faltam
  por envelope; conferir no celular se as mensagens do outro membro voltam.
- Duas branches `feature/**` publicando ao mesmo tempo sobrescrevem a mesma release beta.
- Computador: Q-Acadêmico não funciona no Linux (sem navegador embutido); no Windows usa
  o WebView2 e não foi testado com o site real. Agenda do celular não existe no computador.
- Computador: Linux e macOS não se atualizam sozinhos (abrem o download no navegador);
  o app do macOS não é assinado pela Apple (na 1ª vez: clique direito > Abrir).
- Computador: bandeja, notificações e "abrir com o sistema" ainda não foram vistos rodando
  em nenhum sistema (só testes de unidade).

## Ideias / próximos passos (não decididos)
- Issues #1 a #5 (tempo real, cargos/categorias, voz, personalização, fundo do perfil):
  combinado com o dono fazer depois do app de computador, valendo para os dois.
- Computador: exportar prazos em `.ics` no lugar da agenda do celular.
- **Decidido pelo dono, fazer depois do teste da beta:** guardar a chave de cada conversa
  no servidor (cifrada com segredo da Edge Function), estilo Discord, no lugar de só no
  aparelho. Aparelhos que já têm chave enviam ao servidor na migração.
- Notificação push do Social (Firebase Cloud Messaging).
- Categorias de canais, cargos personalizados com cores, chamadas de voz.
- Verificação de chave entre pessoas (código de segurança) nas mensagens diretas.
- Rede social com avaliações (projeto separado `Rede-Social`, mesmo backend Supabase).
