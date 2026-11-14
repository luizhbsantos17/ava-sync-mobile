# Guia para agentes de IA (e pessoas) neste repositório

Este arquivo é a fonte única de regras para qualquer agente de IA (Claude Code, Codex,
Copilot, Cursor, Gemini...) e para quem contribui. `CLAUDE.md`, `GEMINI.md` e
`.github/copilot-instructions.md` só apontam para cá. **Leia tudo antes de mudar código.**
Se uma regra mudar, mude aqui, não nos atalhos.

## O que é

**AVA Sync**: app Android em Flutter que sincroniza o Moodle do Ifes (AVA,
`https://ava3.cefor.ifes.edu.br`) com o celular — prazos, atividades, avisos, materiais,
notas — e lê boletim, diários e horário do **Q-Acadêmico**. Tem também a área
**Social** (grupos e chat) com backend no Supabase. Público: um grupo pequeno de
estudantes. Idioma do app, dos commits e da documentação: **português do Brasil**.

## Regras que não podem ser quebradas

1. **Nada de segredo ou dado pessoal no Git**: senhas, tokens do Moodle, keystore
   (`*.jks`), `android/key.properties`, chave `service_role`/secret do Supabase,
   `social-*.json`, `server/data/`, `server/tls/`, HTMLs reais do Q-Acadêmico, notas,
   nomes, matrículas. Fixtures de teste usam dados fictícios ("Aluno Exemplo da Silva",
   matrícula `20990XXX0001`, COD_PAUTA `9001xx`, "Professor Exemplo ...").
2. **Assinatura do APK**: não altere `applicationId` (`io.github.avasync.mobile`), os
   secrets `ANDROID_*` do GitHub nem o `signingConfig`. O app instalado precisa
   atualizar por cima. Se um build não puder atualizar por cima, pare e avise o
   dono do repositório — nunca "resolva" pedindo para desinstalar ou apagar dados.
3. **Q-Acadêmico**: só é lido por WebView com o login da própria pessoa. Não tente
   contornar a proteção anti-robô (Radware/perfdrive) nem fazer HTTP direto.
4. **Social**: o app nunca recebe a chave administrativa do Supabase. Toda permissão
   (membro do grupo, professor da matéria) é conferida **no servidor**
   (`supabase/functions/social/index.ts`) validando o token do AVA. Mensagens são
   cifradas no aparelho; o servidor não deve ver texto claro. Professor não ganha
   acesso a grupos privados de alunos.
5. **Não faça push direto na `main` sem o dono pedir.** Trabalhe numa branch
   (`feature/...`, `fix/...`) e abra pull request.
6. **Toda versão nova tem notas no `CHANGELOG.md`** (veja "Versões" abaixo).

## Estrutura

| Caminho | O que tem |
|---|---|
| `lib/main.dart` | inicialização (Cfg, Social, tema, notificações) |
| `lib/moodle.dart` | cliente dos web services do Moodle (`token.php`, `server.php`) |
| `lib/sync.dart` | sincronização: matérias, tarefas, provas, avisos, arquivos, novidades |
| `lib/classificar.dart` | semestre atual, atividade x prova |
| `lib/estado_app.dart` | estado global (`app`), sync, dados acadêmicos |
| `lib/config.dart` | `Cfg`: preferências (SharedPreferences) e segredos (secure storage) |
| `lib/qacademico.dart` | leitor do HTML do Q-Acadêmico (boletim, diários, horário, faltas) |
| `lib/fundo.dart` | notificações e tarefas em segundo plano (workmanager) |
| `lib/atualizacao.dart`, `lib/telas/atualizar.dart` | atualização dentro do app via GitHub Releases |
| `lib/calendario.dart`, `lib/compromissos.dart` | agenda do celular e lembretes |
| `lib/social/` | Social: `repository.dart` (contrato), `moodle_social_repository.dart` (Supabase), `supabase_crypto.dart` (AES-GCM, convites) |
| `lib/telas/` | telas (inicio, curso, desempenho, perfil, ajustes, social...) |
| `supabase/` | migrations SQL e Edge Function `social` |
| `server/` | servidor Node antigo para testes locais do Social (não é usado em produção) |
| `test/` | testes; `test/fixtures/` só com HTML sanitizado |
| `docs/SOCIAL_BACKEND.md` | desenho e privacidade do Social |
| `scripts/notas_versao.sh` | extrai as notas de uma versão do CHANGELOG |

## Comandos

```bash
flutter pub get
flutter analyze          # precisa terminar com "No issues found!"
flutter test             # todos precisam passar
flutter run --flavor beta --dart-define=AVA_SYNC_CHANNEL=beta
```

O projeto tem dois *flavors* Android: `production` (app oficial) e `beta`
(`io.github.avasync.mobile.beta`, "AVA Sync Teste", instala ao lado do oficial).
Sempre passe `--flavor` ao compilar ou rodar.

## Como entregar uma mudança

1. Crie uma branch a partir da `main`: `feature/nome-curto` ou `fix/nome-curto`.
2. Faça a mudança com testes. Bug corrigido ganha teste de regressão.
3. Escreva a mudança em `## [Não lançado]` no `CHANGELOG.md`, para quem usa o app
   (o que mudou para a pessoa, não detalhes de código).
4. `flutter analyze` e `flutter test` limpos.
5. Commit em português, no estilo `feat: ...`, `fix: ...`, `chore: ...`, `docs: ...`.
6. Push da branch: o workflow **beta** publica a pré-release `beta` para testar no
   celular. Abra pull request para a `main`.

## Versões e patch notes

- `pubspec.yaml` → `version: X.Y.Z+N`. Mude `X.Y.Z` a cada versão oficial
  (Z = correções, Y = novidades). O `+N` não importa no CI: o número do build vem
  do `GITHUB_RUN_NUMBER`.
- Para lançar: renomeie `## [Não lançado]` para `## [X.Y.Z] - AAAA-MM-DD`, crie um
  `## [Não lançado]` vazio acima, suba a versão no `pubspec.yaml` e faça merge na `main`.
- O workflow oficial **falha** se a versão do `pubspec.yaml` não tiver seção no
  CHANGELOG. As notas vão para a release `latest`, e o app as mostra em
  "Nova versão disponível".
- O corpo da release começa com `Build: N` — o app depende disso para saber se há
  atualização. Não mude esse formato.

## Releases

| Release | Workflow | Quando | Quem recebe |
|---|---|---|---|
| `latest` | `.github/workflows/build.yml` | push na `main` | todos (app oficial) |
| `beta` (pré-release) | `.github/workflows/build-beta.yml` | push em `beta` ou `feature/**` | só quem instalou o AVA Sync Teste |

## Trabalho com vários agentes ao mesmo tempo

- Uma branch por tarefa; não edite a branch de outra pessoa/agente.
- Antes de começar, rode `git fetch` e confira se a `main` mudou.
- Conflitos no `CHANGELOG.md` são normais: mantenha as duas entradas.
- Decisões de produto que não estão aqui ou em `docs/`: pergunte ao dono, não invente.
- Ao terminar, deixe no pull request: o que mudou, como testou e o que não testou.
