---
name: nova-mudanca
description: Fluxo completo para qualquer mudança no AVA Sync (funcionalidade, ajuste, refatoração). Use no começo de toda tarefa que mexe em código.
---

# Nova mudança (fluxo padrão)

Siga na ordem. Cada passo tem uma skill própria quando precisa de detalhe.

## 1. Entender antes de mexer
- Leia `AGENTS.md` e `docs/contexto/ESTADO_ATUAL.md`. Se a tarefa tocar numa área,
  leia a parte dela em `docs/contexto/ARQUITETURA.md`.
- Procure em `docs/contexto/DECISOES.md` se já existe decisão sobre o assunto.
  **Não desfaça uma decisão registrada sem o dono pedir.**
- Se o pedido for ambíguo ou mudar comportamento que outras pessoas usam, pergunte
  antes de codar.

## 2. Branch
Skill `git-e-push`. Resumo: `git fetch`, branch nova a partir de `origin/main`,
nome `feature/...` ou `fix/...`.

## 3. Código
- Português nos textos da interface, nomes de variáveis no estilo do arquivo.
- Siga o padrão do arquivo que já existe (veja skills `nova-tela`, `nova-configuracao`,
  `leitor-qacademico`, `social-backend`).
- Toda operação de rede pode falhar: mostre mensagem clara, nunca deixe a tela vazia.
- Nada de segredo, dado pessoal ou URL de serviço novo sem o dono aprovar.

## 4. Testes
- Adicione ou ajuste testes em `test/`. Bug corrigido ganha teste que falhava antes.
- `flutter analyze` → "No issues found!"; `flutter test` → todos passando.

## 5. Registrar
- `CHANGELOG.md` → skill `changelog` (seção `## [Não lançado]`).
- `docs/contexto/` → skill `atualizar-contexto`.

## 6. Entregar
- Commit e push da branch (skill `git-e-push`). O push gera o APK beta.
- Abra pull request para a `main` com o modelo do repositório.
- Diga no PR (e para quem pediu) o que foi testado e o que **não** foi.
