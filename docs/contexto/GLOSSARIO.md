# Glossário

| Termo | Significado |
|---|---|
| AVA | Ambiente Virtual de Aprendizagem do Ifes, um Moodle (`ava3.cefor.ifes.edu.br`) |
| Matéria / curso | um curso do Moodle (`course`); no app chamamos de matéria |
| Semestre atual | matérias que o app considera em andamento (`cursosAtuais`); a pessoa pode corrigir |
| Snapshot | `snapshot.json`: tudo o que as telas mostram depois do sync |
| Estado | `estado.json`: o que já foi visto (para gerar avisos de novidade) |
| Q-Acadêmico | sistema acadêmico do Ifes (boletim, diários, horário); não tem API |
| Boletim | página t=2032: notas por etapa, média, faltas, situação |
| Diário | página t=2071: frequência, aulas previstas/ministradas, avaliações |
| Horário | página t=2010: aulas da semana |
| COD_PAUTA | código do diário no Q-Acadêmico; liga boletim e diário |
| Etapa | N1, N2, NS, EF...: períodos de nota do boletim |
| MF | média final |
| Aulas por dia | quantas aulas seguidas a matéria tem num dia (faltar o dia = essa quantidade de faltas) |
| Social | área de grupos e chat do app (backend Supabase) |
| Convite | código `AVASYNC1.…` com o ID do grupo, o segredo de entrada e a chave de leitura |
| Grupo da matéria | grupo criado por professor confirmado pelo AVA, com a turma incluída |
| Flavor | variante do APK: `production` ou `beta` |
| Build | número do GitHub Actions (`GITHUB_RUN_NUMBER`); o app compara para saber se há versão nova |
| `latest` / `beta` | releases do GitHub: oficial e de testes |
