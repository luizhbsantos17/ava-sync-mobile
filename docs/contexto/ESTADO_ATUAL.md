# Estado atual

Atualize esta página **no fim de toda tarefa**: mova itens entre as seções, registre
problemas conhecidos e ideias. Mantenha curta; o histórico detalhado fica no CHANGELOG.

Última atualização: 2026-11-14 (versão 0.7.0, build 11)

## Pronto
- Sync do AVA com prazos, provas, avisos, materiais offline, livros e envio de atividades.
- Notificações (novidades, entrega, nota, prazo alterado/vencido) e lembretes 3d/1d/3h.
- Integração com a agenda do celular (Google Agenda).
- Atualização dentro do app, com "O que mudou" vindo do CHANGELOG.
- Perfil com foto e aparência personalizável (temas e JSON).
- Aba Acadêmico: disciplinas, boletim, horário, faltas restantes e simulador.
- Social: login pela conta do AVA, grupos privados por convite, grupo da matéria
  criado por professor com a turma incluída, mensagens cifradas.
- Canal beta instalável ao lado do oficial.
- Sync só do semestre atual; seleção de matérias por lista.

## Em andamento
- (nada)

## Problemas conhecidos / não verificado
- Grupo da matéria não foi testado com conta de professor real.
- Mensagens do Social chegam por polling (4 s); sem notificação push.
- Trocar de celular exige receber o convite de novo para ler o histórico do grupo.
- Duas branches `feature/**` publicando ao mesmo tempo sobrescrevem a mesma release beta.

## Ideias / próximos passos (não decididos)
- Canais dentro dos grupos (estilo Discord); no grupo da matéria, canais por semestre
  definidos pelo professor.
- Notificação push do Social (Firebase Cloud Messaging).
- Rede social com avaliações (projeto separado `Rede-Social`, mesmo backend Supabase).
