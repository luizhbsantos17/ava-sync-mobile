# Área Social do AVA Sync

Grupos com canais, mensagens diretas, amigos, perfis e presença, no estilo Discord.
Login é a conta do AVA que já está no app: não há cadastro nem senha separada.

## Peças

| Onde | O quê |
|---|---|
| `supabase/functions/social/index.ts` | Edge Function `social`: única porta de entrada; confere toda permissão |
| `supabase/migrations/` | tabelas, RPCs (`social_overview`, `social_key_requests`), gatilhos e bucket `social` |
| `lib/social/api.dart` | chamadas HTTP e sessão (troca o token do AVA por uma sessão de 12 h) |
| `lib/social/service.dart` | `SocialService`: conversas, perfis em cache, chaves, mídia, notificações com o app aberto |
| `lib/social/feed.dart` | `ChannelFeed`: mensagens de um canal, "long polling", envio otimista, reações, edição |
| `lib/social/supabase_crypto.dart` | AES-GCM das mensagens e arquivos, chave X25519 do aparelho, envelopes, convites |
| `lib/social/formatacao.dart` | **negrito**, *itálico*, `código`, blocos, spoiler, citação, links e @menções |
| `lib/social/notificacoes.dart` | verificação em segundo plano (workmanager, ~15 min) |
| `lib/telas/social/` | telas: `home` (barra de grupos), `chat`, `grupo` (configurações), `amigos`, `perfil`, `widgets`, `emojis` |

## Identidade e sessão

1. Ação `session`: o app manda o token do AVA; a função valida com
   `core_webservice_get_site_info` e devolve uma sessão assinada com HMAC (12 h).
   A chave do HMAC é derivada da chave de serviço do projeto; não há segredo extra.
2. As demais ações usam só a sessão (sem consultar o AVA a cada chamada).
3. Ações de professor (`teacher_courses`, `create_course_group`) sempre revalidam no AVA.
4. Usuário = `host:idDoMoodle`. O nome vem do AVA até a pessoa trocar o nome de exibição.

O token do AVA não é guardado no Supabase. A sessão fica no armazenamento seguro do celular.

## Privacidade e chaves

- O servidor só guarda texto cifrado (AES-GCM 256 feito no aparelho). Formato 2 da
  mensagem: JSON `{t: texto, a: [anexos]}`, com conversa, canal e autor no AAD.
  Mensagens antigas (formato 1, só texto) continuam abrindo.
- Anexos são cifrados com a mesma chave da conversa antes do envio e ficam no bucket
  privado `social`; o download é por URL assinada (1 h) emitida só para membros.
  Fotos de perfil e ícones de grupo **não** são cifrados (qualquer usuário do Social
  com sessão pode pedir a URL de um avatar).
- Cada aparelho tem um par X25519 (semente no armazenamento seguro); a pública vai no
  perfil. A chave de cada conversa chega por:
  - **convite** `AVASYNC1.…` (traz a chave), ou
  - **envelope**: qualquer membro que tem a chave a embrulha (X25519 + HKDF + AES-GCM)
    para a chave pública de quem ainda não tem. `social_key_requests` lista quem falta;
    o app faz isso sozinho ao atualizar a visão geral. Assim funcionam: amigo
    adicionado direto no grupo, mensagens diretas, turma no grupo da matéria e troca
    de celular (o histórico volta quando outro membro abrir o app).
- Limite conhecido: o servidor poderia trocar a chave pública de alguém (não há
  verificação de chave entre pessoas). Aceito para o tamanho do projeto.
- Busca de mensagens é feita no aparelho (o servidor não consegue ler).
- Menções (`mentions`) ficam em texto claro, só com o ID de quem foi mencionado,
  para contar menções e notificar.
- Professor não ganha acesso a grupos de alunos: só entra em conversa em que é membro.
  No grupo da matéria, o professor é dono e outros professores da disciplina viram admin.

## Permissões (conferidas na função)

| Quem | Pode |
|---|---|
| membro | ler e escrever (exceto canal de avisos), reagir, responder, editar/apagar as próprias mensagens, criar convite, adicionar **amigos** ao grupo, apelido, silenciar, sair |
| admin | + editar grupo (nome, descrição, ícone), canais (criar, editar, ordenar, apagar), fixar, apagar mensagens de quem tem cargo menor, remover e banir membros, revogar convites, adicionar qualquer pessoa |
| dono | + promover/rebaixar admin, transferir posse, apagar o grupo |
| mensagem direta | só entre amigos ou pessoas que dividem um grupo; bloqueio impede |

Quando o dono sai, a posse vai para um admin ou para o membro mais antigo.

## Tempo real

Sem WebSocket: o app usa *long polling*. A ação `poll` segura a chamada por até
20 s e responde assim que muda algo no canal (mensagem nova, edição, reação,
alguém digitando). Cada mudança aumenta a coluna `rev` (sequência), e o app pede
"tudo depois do `rev` que já tenho". Em segundo plano o laço para; ao voltar,
continua de onde parou. Falha de rede mostra "Reconectando…" e tenta de novo.

Com o app aberto, a visão geral (conversas, não lidas, menções) atualiza a cada 15 s
e gera notificação local de mensagens em outros canais. Com o app fechado, uma tarefa
do workmanager confere a cada ~15 min (`notifications`). Não há push (FCM).

## Compatibilidade

O app 0.7.0 (build 11) continua funcionando: as ações `me`, `list`, `messages`
(por conversa), `send_message` (sem canal) e `join_group` aceitam o formato antigo.
Mensagem sem canal cai no primeiro canal da conversa (gatilho `social_message_defaults`).

## Publicar mudanças no servidor

1. Migration nova em `supabase/migrations/` (nunca edite uma já aplicada).
2. Edite `supabase/functions/social/index.ts`.
3. Aplicar e publicar no projeto `zfyxjqdiffuuofwrgvat` é tarefa do dono (ou de um
   agente que ele autorizou): `supabase db push` e `supabase functions deploy social --no-verify-jwt`.
4. Sem token, a função responde "Endereço do AVA ausente."; sessão inválida responde
   401 "Sessão do Social expirada.".

## Notificações em tempo real (`inbox`)
- `inbox {since}`: long polling (até 20 s) da caixa de entrada da pessoa. Responde assim que
  existe mensagem de outra pessoa, não apagada, em conversa não silenciada, criada depois
  de `since`. Mesmo formato de `notifications` (mensagens cifradas, títulos, canais, perfis).
- O aparelho decifra e mostra; o servidor nunca vê o texto. Apps antigos seguem usando
  `notifications`, que não mudou.

## Push (Firebase Cloud Messaging)
- Tabela `social_push_tokens` (token, user_key, platform), só para a Edge Function.
- `push_register {token}` / `push_unregister {token}`: o celular registra o token ao abrir
  o Social e o apaga ao sair da conta.
- `send_message` dispara, em segundo plano (`EdgeRuntime.waitUntil`), um aviso de dados
  `{tipo: "social", conversa, canal}` para os aparelhos dos outros membros não silenciados.
  Sem conteúdo: o aparelho decifra e monta a notificação.
- Segredo `FCM_SERVICE_ACCOUNT` (JSON da conta de serviço). Sem ele, nada é enviado.
  Configuração completa em `docs/FIREBASE_PUSH.md`.

## Social v3 (cargos, categorias, personalização, eventos)
- `social_roles` / `social_member_roles`: cargos com cor, `position`, `permissions[]`,
  `mentionable`, `hoist`. Ações: `create_role`, `update_role`, `reorder_roles`,
  `delete_role`, `set_member_roles`. Permissão conferida por `poder()` (dono > admin > cargo).
- `social_categories` + `social_channels.category_id`: `create_category`,
  `update_category`, `delete_category`; `create_channel`/`update_channel` aceitam `categoryId`.
- Fundo: `social_profiles.banner_path` (`banner/<hash>/...`, público como o avatar) e
  `social_conversations.banner_path` (`gbanner/<grupo>/...`, só membros) + `accent_color`.
  `banner_color` virou `bigint` (cor 0xAARRGGBB estourava o `integer`, issue #5).
- `social_events` (amizade_pedido, amizade_aceita, adicionado, removido, banido, cargo):
  voltam em `inbox`/`notifications` como `events` e acordam o celular por push.

