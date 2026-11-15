# Arquitetura

## Visão rápida
```
Moodle (AVA) --web services--> lib/moodle.dart --> lib/sync.dart --> Store (snapshot.json, estado.json, arquivos)
                                                                          |
Q-Acadêmico --WebView (login da pessoa)--> lib/qacademico.dart --> AppEstado (lib/estado_app.dart) --> telas (lib/telas/)
                                                                          |
GitHub Releases <-- lib/atualizacao.dart        Supabase Edge Function "social" <-- lib/social/
```

## Peças
- **Moodle** (`lib/moodle.dart`): login em `login/token.php` (serviço `moodle_mobile_app`)
  e chamadas a `webservice/rest/server.php`. `Moodle.tentar` devolve vazio se a função
  não estiver liberada no site, em vez de quebrar o sync.
- **Sync** (`lib/sync.dart`): lista cursos, filtra (`filtrarCursos`: ignorar/somente por
  nome e por ID), classifica o semestre atual (`lib/classificar.dart`), busca tarefas,
  quizzes, páginas, livros, fóruns e calendário, baixa arquivos e calcula novidades.
  O sync comum detalha só matérias do semestre atual; a primeira vez e "Sincronizar
  todas" detalham todas (`estado['sync_completa']`). Matérias não detalhadas mantêm os
  dados do snapshot anterior.
- **Armazenamento** (`lib/armazenamento.dart`, `Store`): `snapshot.json` (o que as telas
  mostram), `estado.json` (o que já foi visto, para avisos) e arquivos baixados.
- **Configuração** (`lib/config.dart`, `Cfg`): SharedPreferences para preferências;
  FlutterSecureStorage para o token do AVA e a senha do Q-Acadêmico.
- **Estado** (`lib/estado_app.dart`, `app`): `ChangeNotifier` global; dispara o sync,
  guarda dados acadêmicos (`academico`, `horario`) e chama `avisarMudanca()`.
- **Segundo plano** (`lib/fundo.dart`): workmanager (sync periódico a cada 6/12/24 h e
  verificação de atualização) e `Notif` (notificações e lembretes agendados 3d/1d/3h).
- **Agenda** (`lib/calendario.dart`, `lib/compromissos.dart`): device_calendar_plus.
- **Q-Acadêmico** (`lib/qacademico.dart`, `lib/telas/qacademico_tela.dart`): o
  `ColetorQA` abre o site num WebView oculto com o login da pessoa e lê as páginas
  t=2032 (boletim), t=2071 (diários) e t=2010 (horário). Os leitores (`lerBoletim`,
  `lerDiarios`, `lerHorario`) só olham tabelas "folha" (sem tabela dentro). Faltas:
  limite = aulas previstas x (100 - mínimo%) / 100; os dias que ainda pode faltar
  dividem pelas aulas daquele dia no horário (padrão 2).
- **IA de estudo** (`lib/ia.dart`, `lib/telas/ia_tela.dart`): monta guias por matéria
  para provedores de IA configurados pela pessoa.
- **Atualização** (`lib/atualizacao.dart`, `lib/telas/atualizar.dart`): lê a release
  `latest` (ou `beta`, no canal beta) pela API do GitHub. O corpo começa com
  `Build: N` e `Versão: X.Y.Z`, seguido das notas do CHANGELOG. Baixa o APK com
  progresso e abre o instalador.
- **Social** (`lib/social/`, `lib/telas/social/`, `supabase/`): veja
  `docs/SOCIAL_BACKEND.md`. O token do AVA é trocado por uma sessão HMAC de 12 h na
  Edge Function `social`, que confere toda permissão. Tabelas com RLS e sem acesso
  direto de clientes. Mensagens e anexos cifrados com AES-GCM no aparelho; a chave da
  conversa vem do convite ou de um envelope X25519 de outro membro. Tempo real por
  long polling (`poll`, até 20 s). Professor confirmado por `core_enrol_get_enrolled_users`.

## Build e distribuição
- Flavors Android: `production` (`io.github.avasync.mobile`, "AVA Sync") e `beta`
  (`io.github.avasync.mobile.beta`, "AVA Sync Teste"). Mesma chave de assinatura.
- `--dart-define=AVA_SYNC_CHANNEL=production|beta` e `AVA_SYNC_BUILD=<número do build>`.
- `.github/workflows/build.yml`: push na `main` publica a release `latest`.
- `.github/workflows/build-beta.yml`: push em `beta` ou `feature/**` publica a pré-release `beta`.
- `.github/workflows/pr.yml`: confere pull requests (analyze, testes, CHANGELOG).
- Push que só muda documentação (`*.md`, `docs/`, `.agents/`, `.claude/`) não gera APK.
