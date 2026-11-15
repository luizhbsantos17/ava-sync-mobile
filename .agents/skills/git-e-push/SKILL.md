---
name: git-e-push
description: Regras de branch, commit, push e pull request do AVA Sync. Use antes de criar branch, commitar, dar push ou abrir PR.
---

# Git, commit, push e pull request

## Branches
| Branch | Para quê | Push gera |
|---|---|---|
| `main` | versão oficial | APK oficial na release `latest` (todos recebem) |
| `feature/nome-curto` | funcionalidade nova | APK beta na pré-release `beta` |
| `fix/nome-curto` | correção | nada (só o PR roda checagens); use `feature/` se quiser beta |
| `beta` | juntar várias mudanças para testar | APK beta |

- Comece sempre de `origin/main` atualizada:
  ```bash
  git fetch origin
  git switch -c feature/nome-curto origin/main
  ```
- Uma branch por tarefa. Não mexa na branch de outra pessoa ou agente.

## Regras de push
- A `main` tem o ruleset **"proteger main"**: exige pull request, exige a checagem
  `conferir` passando e bloqueia force push e deleção. Para colaboradores, um
  `git push origin main` é recusado pelo GitHub — isso é esperado; abra um PR.
- **Nunca** `git push` na `main` sem o dono pedir explicitamente naquela conversa
  (o dono pode pular a regra; não use isso por conta própria).
- Colaboradores criam branches neste repositório; quem não é colaborador usa fork.
- **Nunca** `git push --force` na `main`. Em branch própria, só `--force-with-lease`.
- **Nunca** pule hooks ou checagens (`--no-verify`).
- Antes de cada push: `flutter analyze` e `flutter test` limpos.
- Antes de commitar, confira `git status` e `git diff --cached`: nada de `*.jks`,
  `key.properties`, `social-*.json`, `.env`, HTMLs reais
  do Q-Acadêmico, prints com dados pessoais.

## Commits
- Português, no formato `tipo: resumo` em minúsculas. Tipos: `feat`, `fix`, `chore`,
  `docs`, `test`, `refactor`, `ci`.
- Corpo com a lista do que mudou, quando não for trivial.
- Commit que só mexe em documentação pode levar `[skip ci]` no título.
- Exemplo:
  ```
  fix: horário lê aulas de sábado

  - "SÁBADO" passa a ser reconhecido no cabeçalho
  - teste com fixture sanitizada
  ```

## Pull request
- Título igual ao commit principal. Preencha o modelo (`.github/pull_request_template.md`).
- O workflow `pr.yml` roda analyze, testes e confere se o `CHANGELOG.md` mudou.
  Mudança que não afeta quem usa o app (só docs, testes, CI) pode receber a label
  `sem-changelog`.
- Merge na `main` só pelo dono. Preferir "Squash and merge" para PRs de terceiros.
