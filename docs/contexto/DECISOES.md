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

## 2026-11-16 — Cargos personalizados ao lado de dono/admin
**Decisão:** dono e admin (`social_members.role`) continuam no topo e têm todas as
permissões. Cargos personalizados (`social_roles`) têm `position` (maior = mais alto),
cor, permissões em texto (`gerenciar_grupo`, `expulsar`...) e podem ser vários por pessoa
(`social_member_roles`). Quem tem `gerenciar_cargos` só mexe em cargos abaixo do seu e
não dá permissão que não tem; remover/banir/apagar seguem a mesma hierarquia.
Menção a cargo é `role:<id>` em `mentions`; o app escreve `@apelido_do_cargo`.
**Por quê:** issue #2 pede cargos como no Discord sem quebrar grupos e apps já existentes.
**Consequências:** o servidor confere tudo em `poder()`/`requirePerm()`; o app só esconde
botões. Eventos de amizade, grupo e cargo ficam em `social_events` e vão no `inbox`/push.

## 2026-11-16 — Push do Android pelo Firebase, só em código nativo
**Decisão:** app fechado no Android recebe aviso pelo Firebase Cloud Messaging. O servidor
manda só `{tipo, conversa, canal}`; o app acorda (`PushService.kt` sobe um Flutter sem tela
com `aoReceberPush`) e monta a notificação decifrando no aparelho. Firebase configurado por
código com valores `FCM_*` do build, sem `google-services.json` nem pacotes Flutter do Firebase.
**Por quê:** o dono escolheu Firebase em vez de conexão permanente (bateria, ícone fixo,
celulares que matam o app). Os pacotes `firebase_core`/`firebase_messaging` baixariam o SDK
C++ do Firebase no build do Windows; o nativo só existe no Android.
**Consequências:** sem os secrets `FCM_*` o APK sai sem push (tudo funciona, só demora).
O Google vê que existe aviso para o app, não o conteúdo. Tokens inválidos são apagados
quando o Firebase responde UNREGISTERED.

## 2026-11-16 — Notificação do Social em tempo real por long polling da caixa de entrada
**Decisão:** ação `inbox` na Edge Function segura a chamada (até 20 s) até chegar mensagem
de outra pessoa numa conversa não silenciada. O app (`EscutaSocial`) chama em sequência:
sempre no computador, e no celular com o app aberto. A notificação é montada no aparelho,
que decifra a mensagem: uma por conversa/canal, com nome e texto, acumulando até ler
(`Cfg.socialNotifPendentes`), no Android com o estilo de conversa do sistema.
**Por quê:** o dono quer ver na hora qual mensagem chegou, de quem e em qual grupo. Sem
Realtime do Supabase (exigiria acesso direto às tabelas, veja a decisão de 2026-11-15).
**Consequências:** o servidor continua sem ver texto. App fechado no Android ainda depende
do workmanager (~15 min) até decidir push (FCM) ou conexão permanente.

## 2026-11-16 — App de computador no mesmo projeto Flutter
**Decisão:** Windows, Linux e macOS saem do mesmo código e do mesmo repositório do Android
(pastas `windows/`, `linux/`, `macos/`). O que muda por sistema fica isolado em
`lib/plataforma.dart`, `lib/navegador_web.dart` e `lib/desktop/`. As telas se adaptam pela
largura da janela (`InicioTela.larguraLarga`), não pelo sistema. O computador sai no mesmo
workflow, com o mesmo número de build e na mesma release do APK (`desktop.yml`).
**Por quê:** o dono pediu que atualizações e integrações (AVA, Q-Acadêmico, Social)
valham para os dois sem trabalho dobrado. App separado obrigaria a copiar cada mudança.
**Consequências:** no computador não há workmanager: o app fica na bandeja e relógios
(`SegundoPlanoDesktop`) fazem sync, Social (a cada 1 min), lembretes e atualização.
`window_manager`/`tray_manager` 0.7/0.9 compilam código nativo até nos testes, então o CI
do Linux instala GTK/X11 e o Windows precisa do Visual Studio com C++. "Abrir com o sistema"
foi feito sem pacote (o `launch_at_startup` não resolve com o SDK atual).

## 2026-11-16 — Canais de voz com LiveKit e E2EE
**Decisão:** a mídia passa pelo LiveKit (Cloud, plano grátis; o dono cria a conta). A Edge
Function só emite o token (JWT HS256 com os segredos `LIVEKIT_*`) e guarda quem está em cada
canal (`social_voice_presence`, renovada a cada 20 s, expira em 45 s). Áudio e vídeo vão
cifrados (E2EE do LiveKit) com uma chave derivada da chave do grupo
(`SHA-256("ava-sync-voz-v1|canal|" + chave)`).
**Por quê:** fazer WebRTC com várias pessoas e tela compartilhada exige um servidor de mídia
(SFU); o LiveKit tem cliente Flutter para Android, Windows, Linux e macOS. O E2EE mantém a
promessa do Social: o servidor não ouve nem vê.
**Consequências:** quem não tem a chave do grupo não entra na voz. Uma pessoa fica em um canal
de voz por vez. No Android, a chamada usa um serviço em primeiro plano (notificação) para
seguir com o app em segundo plano.

## 2026-11-16 — Notificações por grupo e ordem dos grupos
**Decisão:** `social_members.notify` (`all`, `mentions`, `none`) com `suppress_everyone` e
`suppress_roles`; `muted` continua existindo e vale `notify <> 'all'` para o app antigo.
A ordem dos grupos na barra lateral é só do aparelho (`Cfg.socialOrdemGrupos`); a dos
canais e categorias é do grupo (ação `arrange_channels`, quem gerencia canais).
**Por quê:** o "silenciar" sozinho não deixava escolher receber só menções nem ignorar
@todos; ordem de grupos é preferência pessoal, ordem de canais é do grupo (como no Discord).

## 2026-11-16 — Turma de ingresso
**Decisão:** `social_profiles.cohort` ("2024/2") é preenchido só pelo servidor, a partir do
`username` do AVA (`core_webservice_get_site_info`) quando ele começa com ano+semestre.
**Por quê:** cargo fixo pedido pelo dono, que ninguém consegue mudar pelo app.

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

## Presença sobre o total do semestre (2026-11-16)
O % principal de presença é `1 - faltas / total de aulas do semestre` (carga horária em aulas
de 50 min), não o % do Q-Acadêmico (sobre aulas já dadas). Reprovar por falta depende do total,
então esse é o número útil. O % do Q-Acadêmico fica em `Frequencia.percentualDadas` e só vira o
principal quando não há carga horária. As aulas do dia mostram "pode faltar mais N dias".

## Serviço do flutter_background só para compartilhar tela (2026-11-16)
O plugin sobe o serviço com todos os `foregroundServiceType` do manifesto. Com
`mediaProjection|microphone`, subir o serviço ao entrar na chamada derrubava o app no Android 14+
(SecurityException nativa). Agora o tipo é só `mediaProjection` e o serviço sobe apenas depois
de autorizar a captura de tela. Efeito: só com voz, o Android pode cortar o microfone com o app
em segundo plano. Para resolver isso, seria preciso um serviço próprio de microfone, ligado só
depois de RECORD_AUDIO concedida.

## Widgets do livekit_client que usam Material (2026-11-17)
O app usa `material_ui`, não o `package:flutter/material.dart`. Widgets prontos de pacotes que
dependem do Material do Flutter (ex.: `ScreenSelectDialog` do livekit) não acham
`MaterialLocalizations` e quebram com "Null check operator". Use telas próprias com material_ui.

## Avaliação docente respondida pelo app (2026-11-19)
O dono pediu para o app responder sozinho os questionários obrigatórios que bloqueiam o
Q-Acadêmico. Decisão: o app nunca escolhe as respostas; a pessoa define a nota (0 a 10) de cada
disciplina e confirma. O app marca a opção com aquela nota em todas as perguntas e envia pelo
próprio formulário, no WebView logado (sem HTTP direto). Só os questionários obrigatórios.

## Pacote do AUR para o Linux (2026-11-20)
O dono pediu para instalar o app de Linux pelo terminal com `yay`. Decisão: pacote binário
`ava-sync-bin` no AUR, que baixa o `AVA-Sync-Linux.tar.gz` da release `latest` (o mesmo do
app) e instala em `/opt/ava-sync`, com `/usr/bin/ava-sync`, atalho no menu e ícone. Como a
release `latest` é sobrescrita a cada push na `main`, `pkgver` = versão do pubspec + número do
build (ex.: `1.3.1.250`) e o CI grava o sha256 do arquivo que acabou de publicar. Só o canal
oficial vai para o AUR. O app detecta a instalação em `/opt/ava-sync/` e manda atualizar com
`yay`, porque não tem permissão de escrever lá.
