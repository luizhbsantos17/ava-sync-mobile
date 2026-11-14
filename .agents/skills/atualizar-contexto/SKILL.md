---
name: atualizar-contexto
description: Atualiza a memória compartilhada em docs/contexto/ no fim de uma tarefa no AVA Sync. Use sempre antes do commit final de qualquer tarefa.
---

# Atualizar o contexto do projeto

Outras pessoas e outras IAs só vão saber o que você fez pelo que estiver em
`docs/contexto/`. Faça isto **no fim de toda tarefa**, no mesmo commit/PR.

## Checklist
1. **`ESTADO_ATUAL.md`** (sempre):
   - Mova o item para "Pronto" (ou "Em andamento", se ficou pela metade, dizendo o que falta
     e em qual branch).
   - Registre em "Problemas conhecidos / não verificado" o que você não conseguiu testar
     (ex.: "não testado em celular", "não testado com conta de professor").
   - Ideias que surgiram e não foram feitas vão para "Ideias / próximos passos".
   - Atualize a linha "Última atualização" com a data (AAAA-MM-DD) e a versão.
2. **`DECISOES.md`** (se decidiu algo não óbvio): entrada nova no topo com Decisão e
   Por quê. Ex.: escolheu uma biblioteca, mudou um formato, recusou uma abordagem.
3. **`ARQUITETURA.md`** (se mudou fluxo, arquivo central, formato de dado, workflow).
4. **`GLOSSARIO.md`** (se criou ou usou termo novo).
5. **`AGENTS.md`** só se mudou uma regra do projeto (com aprovação do dono).

## Regras
- Português, curto, sem dados pessoais, datas absolutas.
- Escreva fatos, não intenções vagas ("falta testar envio com arquivo > 20 MB",
  e não "melhorar depois").
- Não apague histórico de decisões; marque como substituída.
