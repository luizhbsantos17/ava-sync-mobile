---
name: reservar-tarefa
description: Como avisar que você (pessoa ou IA) está fazendo uma tarefa ou issue, para duas pessoas não fazerem a mesma coisa. Use ANTES de começar qualquer mudança e ao desistir ou terminar.
---

# Reservar uma tarefa

Várias pessoas e IAs mexem neste repositório. Antes de escrever código, deixe claro que
a tarefa é sua, e confira se ninguém já pegou.

## 1. Conferir se está livre
```bash
gh issue view <N>                      # tem alguém em "Assignees" ou a etiqueta "em andamento"?
gh pr list --search "<N> in:body"      # já existe pull request citando a issue?
```
Leia também a seção **Em andamento** de `docs/contexto/ESTADO_ATUAL.md`.
Se já tem dono: não comece. Comente na issue se quiser ajudar, ou escolha outra.

## 2. Reservar (antes do primeiro commit)
```bash
gh issue edit <N> --add-assignee @me --add-label "em andamento"
gh issue comment <N> --body "Pegando esta: branch \`feature/nome-curto\`."
```
- IA trabalhando para alguém: atribua à pessoa que pediu e diga no comentário que é uma IA.
- Tarefa sem issue: crie a issue antes (`gh issue create`), ou anote em "Em andamento".
- Sem acesso ao GitHub: escreva em `docs/contexto/ESTADO_ATUAL.md` > **Em andamento**
  `- <o quê> — <quem>, branch <x>, desde AAAA-MM-DD` e dê push nessa linha logo.

## 3. Mostrar o progresso cedo
Crie a branch, dê push e abra um **pull request em rascunho** com `Resolve #<N>` no texto:
```bash
gh pr create --draft --title "..." --body "Resolve #<N>"
```

## 4. Ao terminar ou desistir
- Terminou: o pull request com `Resolve #<N>` fecha a issue no merge. Tire a etiqueta.
- Desistiu ou parou no meio: `gh issue edit <N> --remove-assignee @me --remove-label "em andamento"`
  e comente até onde chegou e em qual branch ficou.
- Reserva parada há mais de 7 dias sem commit pode ser assumida por outra pessoa,
  depois de comentar na issue.
