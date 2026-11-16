# Estado atual

Atualize esta página **no fim de toda tarefa**: mova itens entre as seções, registre
problemas conhecidos e ideias. Mantenha curta; o histórico detalhado fica no CHANGELOG.

Última atualização: 2026-11-16 (versão 0.8.0; correção de faltas ainda não lançada)

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

## Em andamento
- (nada)

## Problemas conhecidos / não verificado
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

## Ideias / próximos passos (não decididos)
- **Decidido pelo dono, fazer depois do teste da beta:** guardar a chave de cada conversa
  no servidor (cifrada com segredo da Edge Function), estilo Discord, no lugar de só no
  aparelho. Aparelhos que já têm chave enviam ao servidor na migração.
- Notificação push do Social (Firebase Cloud Messaging).
- Categorias de canais, cargos personalizados com cores, chamadas de voz.
- Verificação de chave entre pessoas (código de segurança) nas mensagens diretas.
- Rede social com avaliações (projeto separado `Rede-Social`, mesmo backend Supabase).
