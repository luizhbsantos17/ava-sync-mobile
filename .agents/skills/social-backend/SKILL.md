---
name: social-backend
description: Como mudar o Social (grupos e chat) do AVA Sync, no app e no Supabase (Edge Function e migrations), mantendo segurança e privacidade. Use para mudanças em lib/social/, lib/telas/social*.dart ou supabase/.
---

# Social: app + Supabase

Leia antes: `docs/SOCIAL_BACKEND.md` e a parte Social de `docs/contexto/ARQUITETURA.md`.

## Regras de segurança
- O app **nunca** recebe a chave `service_role`/secret. Só URL e chave publishable.
- Toda permissão é conferida **na Edge Function** (`supabase/functions/social/index.ts`):
  token do AVA validado a cada chamada; participação conferida com `requireMember`;
  professor confirmado pelo papel na matéria (`hasTeacherRole`).
- Nada de policy que dê acesso direto às tabelas para `anon`/`authenticated`.
- Mensagens continuam cifradas no aparelho (`lib/social/supabase_crypto.dart`); o
  servidor não pode passar a receber texto claro. Mudou o formato? Crie `v: 2` e
  continue lendo `v: 1`.
- O token do AVA não é gravado no banco nem em log.
- Professores não ganham acesso a grupos privados de alunos.

## Mudando o app
- A UI fala com `SocialRepository` (`lib/social/repository.dart`); acrescente métodos
  no contrato e implemente em `MoodleSocialRepository`.
- Nova ação → mesmo nome em `_call('acao', {...})` e no `if (action === "acao")` da função.

## Mudando o servidor
1. Banco: crie uma migration nova em `supabase/migrations/AAAAMMDDHHMM_descricao.sql`.
   Nunca edite migration já aplicada. Mantenha RLS ligado e `revoke` para anon/authenticated.
2. Função: edite `supabase/functions/social/index.ts`.
3. **Publicar no Supabase é tarefa do dono** (ou de um agente com acesso que ele
   autorizou): `supabase db push` e `supabase functions deploy social`
   (projeto `zfyxjqdiffuuofwrgvat`). Quem não tem acesso deixa isso descrito no PR.
4. App e servidor precisam continuar compatíveis com a versão anterior do app, porque
   nem todos atualizam na hora: ações novas são opcionais, campos novos têm padrão.

## Testar
- Testes de unidade para convite/cripto em `test/social_test.dart`.
- Para testar a função sem dado real: chamada sem token deve responder erro
  ("Endereço do AVA ausente." / token inválido).
