# Decisões

Registro curto do que foi decidido e **por quê**. Entradas novas no topo. Não apague
decisões antigas: se mudar de ideia, crie uma entrada nova dizendo qual ela substitui.

Formato:
```
## AAAA-MM-DD — Título
**Decisão:** ...
**Por quê:** ...
**Consequências:** ... (opcional)
```

## 2026-11-15 — Social v2: sessão, envelopes, long polling
**Decisão:** o token do AVA vira uma sessão HMAC de 12 h; chaves das conversas também
circulam por envelopes X25519 entre aparelhos; mensagens chegam por long polling.
Removidos `server/` (Node local) e as camadas `SocialRepository`/`HttpSocialRepository`.
**Por quê:** validar no AVA a cada 4 s era lento e pesado; convite como único jeito de
receber a chave impedia DM, adicionar amigo e trocar de celular; Realtime do Supabase
exigiria dar acesso direto às tabelas. O servidor Node não era usado em produção.
**Consequências:** o servidor poderia trocar chaves públicas (sem verificação entre
pessoas). Avatares e ícones não são cifrados. Substitui a parte "polling 4 s" e
"chave só por convite" da decisão "Social no Supabase com identidade do AVA".

## 2026-11-14 — Main protegida, colaboradores com branches no repositório
**Decisão:** amigos de confiança entram como colaboradores e criam branches aqui. A
`main` tem o ruleset "proteger main": só por pull request com a checagem `conferir`
passando, sem force push nem deleção; o dono (admin) pode pular.
**Por quê:** permitir que os amigos gerem o APK beta sem poder mudar a versão oficial.
**Consequências:** a chave de assinatura continua nos secrets do repositório, ao alcance
de workflows de colaboradores. Foi uma escolha consciente do dono (confia em quem mexe).
Se um dia entrar alguém menos conhecido, mover a chave para um environment com aprovação.

## 2026-11-14 — Regras compartilhadas para agentes de IA
**Decisão:** `AGENTS.md` é a fonte única de regras; contexto em `docs/contexto/` e
receitas em `.agents/skills/`. `CLAUDE.md`, `GEMINI.md` e Copilot apontam para lá.
**Por quê:** várias pessoas usam IAs diferentes; todas precisam seguir as mesmas regras
e saber o que as outras fizeram.

## 2026-11-14 — Patch notes obrigatórias
**Decisão:** toda versão tem seção no `CHANGELOG.md`; o build oficial falha sem ela e
o pull request falha se não mexer no CHANGELOG.
**Por quê:** quem atualiza vê "O que mudou" no app.

## 2026-11-14 — Canal beta por flavor, mesma chave
**Decisão:** a beta usa `applicationId` com sufixo `.beta` e a pré-release `beta`.
**Por quê:** instalar junto com o oficial sem desinstalar. A chave pode ser a mesma:
o que permite os dois instalados é o identificador diferente.

## 2026-11-14 — Social no Supabase com identidade do AVA
**Decisão:** o login do Social é a conta do AVA, validada no servidor a cada chamada.
Grupos e mensagens são do app, não do AVA. Professor é confirmado pelo papel na matéria.
**Por quê:** sem segundo cadastro; o app não pode "se declarar professor".
**Consequências:** professores não ganham acesso a conversas de alunos.

## 2026-11-14 — Sync detalha só o semestre atual
**Decisão:** o sync comum busca detalhes só das matérias atuais; a primeira vez e o
botão manual buscam todas.
**Por quê:** o sync consultava todas as matérias antigas a cada execução.

## 2026-11-14 — Q-Acadêmico só por WebView
**Decisão:** ler as páginas pelo WebView com o login da pessoa; senha só salva se ela marcar.
**Por quê:** não há API e o site tem proteção anti-robô que não deve ser contornada.

## 2026-11-14 — Distribuição pelo GitHub Releases, assinatura fixa
**Decisão:** o APK é publicado pelo GitHub Actions na release `latest`, assinado com
uma chave fixa guardada nos secrets do repositório.
**Por quê:** atualizar por cima sem desinstalar, sem custo de loja ou servidor.
