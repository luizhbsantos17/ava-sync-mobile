# Estado atual

Atualize esta página **no fim de toda tarefa**: mova itens entre as seções, registre
problemas conhecidos e ideias. Mantenha curta; o histórico detalhado fica no CHANGELOG.

Última atualização: 2026-11-16 (1.1.0 lançada; canais de voz na branch `feature/canais-voz`)

## Pronto
- Sync do AVA com prazos, provas, avisos, materiais offline, livros e envio de atividades.
- Notificações (novidades, entrega, nota, prazo alterado/vencido) e lembretes 3d/1d/3h.
- Integração com a agenda do celular (Google Agenda).
- Atualização dentro do app, com "O que mudou" vindo do CHANGELOG.
- Perfil com foto e aparência personalizável (temas e JSON).
- Aba Acadêmico: disciplinas, boletim, horário, faltas restantes e simulador.
- Limites de faltas para 30/60/90 horas corrigidos para 9/18/27 (aulas de 50 minutos).
- Testes acadêmicos atualizados para a conversão de horas em aulas, limites e notificações de faltas restantes.
- Social v2 (estilo Discord): grupos com canais, mensagens diretas, amigos, perfis,
  presença e status, reações, respostas, edição, fixados, anexos cifrados, digitando,
  moderação (admin, dono, remover, banir), convites com validade, notificações.
  Banco e Edge Function já publicados no Supabase (compatíveis com o app 0.7.0).
- Canal beta instalável ao lado do oficial.
- Sync só do semestre atual; seleção de matérias por lista.

- **App de computador** (Windows, Linux, macOS), mesmo código do Android: bandeja,
  segundo plano por relógios, abrir com o sistema, layout largo, Social em painéis,
  instalador do Windows com atualização automática. CI gera os três na mesma release.
- **Social em tempo real**: `inbox` (long polling) + notificação por conversa com nome e
  texto, acumulando até ler. **Push do Android pelo Firebase** com o app fechado
  (testado pelo dono no celular em 2026-11-16).
- **Social v3**: cargos personalizados (cor, hierarquia, permissões, vários por pessoa,
  @cargo), categorias de canais, fundo com foto no perfil e no grupo, cor do grupo,
  notificações de amizade, grupo e cargo (issues #1, #2, #4, #5).
- Regra de reservar tarefa (skill `reservar-tarefa`, etiqueta `em andamento`).
- Menções (#7): notificação, busca e prévia mostram o nome ("@Mikame") no lugar de
  "@ifes_..."; menção tem canal "Menções" de prioridade máxima e passa por grupo
  silenciado (só @você/@cargo, não @todos).

## Em andamento
- **Canais de voz (issue #3)**, branch `feature/canais-voz`: LiveKit com E2EE pela chave do
  grupo, presença em `social_voice_presence`, ações `voice_join`/`voice_state`/`voice_leave`/
  `voice_disconnect`. Banco (migration `202611160004_social_voice`) aplicado. **Falta o dono**
  criar o projeto no LiveKit Cloud e pôr `LIVEKIT_URL`, `LIVEKIT_API_KEY` e
  `LIVEKIT_API_SECRET` nos segredos da Edge Function. Sem isso, entrar mostra "ainda não foram ligados".

## Problemas conhecidos / não verificado
- Canais de voz não foram testados em chamada real (falta o LiveKit). Conferir: áudio entre
  celular e computador, E2EE (todos precisam da mesma chave do grupo), compartilhar tela no
  Android (pede permissão e liga um serviço com notificação) e no Windows/Linux/macOS.
- Turma de ingresso só aparece se o usuário do AVA começar com ano+semestre (ex.: 20242...).
  Se o login do AVA for CPF ou outro formato, fica sem turma. Aparece depois que a sessão
  do Social renova (até 12 h) ou ao entrar de novo.
- 1.1.0: testes não rodam no PC sem Visual Studio C++ (pacotes nativos do computador);
  conferidos no GitHub Actions.
- App de computador ainda não foi aberto por ninguém (só build no CI e testes). Conferir
  bandeja, notificação do Windows, layout largo, atualização automática e Q-Acadêmico no WebView2.
- Social v3 (cargos, categorias, fundo com foto, eventos) só tem testes de unidade e
  checagem de tipos do servidor; conferir com duas contas reais.
- Correção dos limites de faltas não testada em celular com importação real.
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
- Computador: exportar prazos em `.ics` no lugar da agenda do celular.
- **Decidido pelo dono, fazer depois do teste da beta:** guardar a chave de cada conversa
  no servidor (cifrada com segredo da Edge Function), estilo Discord, no lugar de só no
  aparelho. Aparelhos que já têm chave enviam ao servidor na migração.
- Notificação push do Social (Firebase Cloud Messaging).
- Categorias de canais, cargos personalizados com cores, chamadas de voz.
- Verificação de chave entre pessoas (código de segurança) nas mensagens diretas.
- Rede social com avaliações (projeto separado `Rede-Social`, mesmo backend Supabase).
